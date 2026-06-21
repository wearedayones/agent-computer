#!/usr/bin/env python3
"""dash-server.py — Agent Computer v4 dashboard (TV + remote control)"""
import argparse, json, os, re, select, subprocess, threading, time
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs, unquote

try:
    from http.server import ThreadingHTTPServer
except ImportError:
    import socketserver
    class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
        daemon_threads = True

HOME = Path.home()
_write_lock = threading.Lock()
_cache = {}
_cache_ts = 0.0
_CACHE_TTL = 10.0

# ── Data collectors ───────────────────────────────────────────────────────────

def disk_info():
    try:
        st = os.statvfs(HOME)
        free_gb  = round(st.f_bavail * st.f_frsize / 1e9, 1)
        total_gb = round(st.f_blocks * st.f_frsize / 1e9, 1)
        used_pct = int(100 * (1 - st.f_bavail / st.f_blocks))
        return {"free_gb": free_gb, "total_gb": total_gb, "used_pct": used_pct}
    except: return {}

def version_info():
    v, h = "?", "?"
    try: v = (HOME / "system/.version").read_text().strip()
    except: pass
    try: h = subprocess.check_output(["hostname"], text=True, stderr=subprocess.DEVNULL).strip()
    except: pass
    return {"version": v, "hostname": h}

def sessions_data():
    try:
        out = subprocess.check_output(["tmux", "ls"], text=True, stderr=subprocess.DEVNULL)
        return [l.split(":")[0].strip() for l in out.strip().splitlines() if l.strip()]
    except: return []

def tasks_data():
    try: return json.loads((HOME / "system/tasks.json").read_text()).get("tasks", [])
    except: return []

def budget_data():
    try: d = json.loads((HOME / "system/budget.json").read_text())
    except: return {"entries": [], "thresholds": {}}
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    entries = [e for e in d.get("entries", []) if e.get("month") == month]
    by_cat = {}
    for e in entries:
        cat = e.get("category", "uncategorized")
        by_cat[cat] = round(by_cat.get(cat, 0) + e.get("amount", 0), 4)
    return {"month": month, "total": round(sum(by_cat.values()), 4),
            "by_category": by_cat, "thresholds": d.get("thresholds", {})}

def trace_data(limit=25):
    try:
        lines = (HOME / "system/trace.jsonl").read_text().strip().splitlines()
        return [json.loads(l) for l in lines if l.strip()][-limit:]
    except: return []

def _find_app_dirs(base, depth=3):
    result = []
    if depth <= 0: return result
    try:
        for p in sorted(base.iterdir()):
            if not p.is_dir() or p.name.startswith('.') or p.name in ('envs','__pycache__','node_modules','.git','state','logs'):
                continue
            if (p / 'state').exists():
                result.append(p)
            else:
                result.extend(_find_app_dirs(p, depth - 1))
    except PermissionError: pass
    return result

def apps_data():
    apps_dir = HOME / "apps"
    if not apps_dir.exists(): return []
    cutoff7 = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d")
    result = []
    for app_dir in _find_app_dirs(apps_dir):
        info = {"name": app_dir.name, "path": str(app_dir.relative_to(HOME))}
        status_f = app_dir / "state" / "status.json"
        if status_f.exists():
            try: info["status"] = json.loads(status_f.read_text())
            except: info["status"] = {}
        mf = app_dir / "state" / "metrics.jsonl"
        if mf.exists():
            try:
                lines = [l for l in mf.read_text().strip().splitlines() if l.strip()]
                entries = [json.loads(l) for l in lines]
                recent = [e for e in entries if e.get("date","") >= cutoff7]
                views_7d, top_title, top_views = 0, "", 0
                for e in recent:
                    for v in e.get("videos", []):
                        vw = v.get("views", 0) or 0
                        views_7d += vw
                        if vw > top_views: top_views = vw; top_title = v.get("title","")[:60]
                    if "views" in e and "videos" not in e:
                        views_7d += e.get("views", 0) or 0
                info["views_7d"] = views_7d
                if top_title: info["top_video"] = top_title; info["top_views"] = top_views
            except: pass
        logs_dir = app_dir / "logs"
        info["has_logs"] = logs_dir.exists() and bool(list(logs_dir.glob("*.log")))
        result.append(info)
    return result

def activity_feed():
    events = []
    try:
        lines = (HOME / "system/trace.jsonl").read_text().strip().splitlines()
        for l in lines[-15:]:
            e = json.loads(l)
            ok = e.get("outcome") == "success"
            events.append({"type":"trace","ts":e.get("ts",""),"text":e.get("action",""),
                           "agent":e.get("agent","agent"),
                           "icon":"✓" if ok else "✗","color":"#00d08a" if ok else "#ff4466",
                           "outcome": e.get("outcome","")})
    except: pass
    inbox = HOME / "inbox"
    if inbox.exists():
        files = sorted([f for f in inbox.iterdir() if f.is_file() and "brief" not in f.name], reverse=True)
        for f in files[:5]:
            try:
                text = f.read_text().strip()
                first = text.splitlines()[0][:80] if text else ""
                ts = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                events.append({"type":"note","ts":ts,"text":first,"agent":"inbox","icon":"📧","color":"#ffa040","outcome":""})
            except: pass
    apps_dir = HOME / "apps"
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M")
    if apps_dir.exists():
        for alert_log in sorted(apps_dir.rglob("alerts.log"))[:5]:
            app = alert_log.relative_to(apps_dir).parts[0]
            try:
                lines = alert_log.read_text().strip().splitlines()[-20:]
                for line in lines:
                    if any(w in line.upper() for w in ("ERROR","FAIL","CRITICAL")):
                        ts_str = line[:16] if len(line) >= 16 else ""
                        if ts_str >= cutoff[:16]:
                            events.append({"type":"alert","ts":ts_str+"Z","text":f"{line.strip()[:80]}",
                                           "agent":app,"icon":"⚠","color":"#ff4466","outcome":"fail"})
            except: pass
    events.sort(key=lambda e: e["ts"], reverse=True)
    return events[:20]

def discover_logs():
    logs, seen = [], set()
    patterns = ["apps/*/logs/*.log","apps/*/*/logs/*.log","apps/*/*/state/*.log",
                "apps/*/state/*.log","system/*.log"]
    for pat in patterns:
        for p in sorted(HOME.glob(pat)):
            s = str(p)
            if s not in seen:
                seen.add(s)
                parts = p.relative_to(HOME).parts
                if len(parts) >= 4 and parts[0] == "apps":
                    label = f"{parts[-3]} / {p.name}"
                elif len(parts) >= 3 and parts[0] == "apps":
                    label = f"{parts[1]} / {p.name}"
                else:
                    label = str(p.relative_to(HOME))
                logs.append({"label": label, "path": s})
    return logs

def agents_data():
    try:
        d = json.loads((HOME / "system/agents.json").read_text())
        result = {}
        for name, info in d.get("agents", {}).items():
            chk = info.get("check", "")
            alive = None
            if chk:
                try:
                    r = subprocess.run(chk, shell=True, capture_output=True, timeout=2)
                    alive = r.returncode == 0
                except: alive = False
            result[name] = {"alive": alive, "url": info.get("url",""), "check": chk}
        return result
    except: return {}

def inbox_data():
    inbox = HOME / "inbox"
    notes = []
    if inbox.exists():
        files = sorted([f for f in inbox.iterdir()
                        if f.is_file() and "brief" not in f.name], reverse=True)
        for f in files[:6]:
            try:
                text = f.read_text().strip()
                first = text.splitlines()[0] if text else ""
                notes.append({"file": f.name, "text": first[:200], "full": text[:500]})
            except: pass
    return notes

def alerts_data():
    apps_dir = HOME / "apps"
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M")
    alerts = []
    if not apps_dir.exists(): return []
    for alert_log in apps_dir.rglob("alerts.log"):
        app = alert_log.relative_to(apps_dir).parts[0]
        try:
            lines = alert_log.read_text().strip().splitlines()[-100:]
            for line in lines:
                if any(w in line.upper() for w in ("ERROR","FAIL","CRITICAL")):
                    ts = line[:16] if len(line) >= 16 else ""
                    if ts >= cutoff[:16]:
                        alerts.append({"app": app, "line": line.strip()[:160]})
        except: pass
    return alerts[-20:]

def env_data():
    try: return json.loads((HOME / "system/env.json").read_text())
    except: return {}

def cron_data():
    try:
        out = subprocess.check_output(["crontab","-l"], text=True, stderr=subprocess.DEVNULL)
        return [l.strip() for l in out.splitlines() if l.strip() and not l.startswith("#")]
    except: return []

def sched_data():
    try: return json.loads((HOME / "system/sched.json").read_text()).get("jobs", [])
    except: return []

def build_state():
    global _cache, _cache_ts
    now = time.monotonic()
    if now - _cache_ts >= _CACHE_TTL:
        _cache = {
            "agents":   agents_data(),
            "cron":     cron_data(),
            "ver":      version_info(),
            "sessions": sessions_data(),
        }
        _cache_ts = now
    return {
        "ts":          datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "system":      {**_cache["ver"], **disk_info(), "sessions": _cache["sessions"]},
        "env":         env_data(),
        "tasks":       tasks_data(),
        "budget":      budget_data(),
        "trace":       trace_data(),
        "apps":        apps_data(),
        "activity":    activity_feed(),
        "log_sources": discover_logs(),
        "agents":      _cache["agents"],
        "inbox":       inbox_data(),
        "alerts":      alerts_data(),
        "cron":        _cache["cron"],
        "sched":       sched_data(),
    }

# ── Dashboard HTML ────────────────────────────────────────────────────────────

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Agent Computer</title>
<style>
:root{
  --bg:#0d0d14;--sb:#0a0a12;--surf:#161622;--surf2:#1c1c2e;--surf3:#222238;
  --bdr:#252535;--bdr2:#2e2e48;
  --tx:#e8e8f0;--tx2:#8888aa;--tx3:#505070;
  --blue:#4f9fff;--bdim:rgba(79,159,255,.13);
  --green:#00d08a;--gdim:rgba(0,208,138,.13);
  --red:#ff4466;--rdim:rgba(255,68,102,.13);
  --yel:#ffa040;--ydim:rgba(255,160,64,.13);
  --pur:#9b6dff;
  --sbw:220px;--tbh:52px;--r:9px;--rsm:5px;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
html,body{height:100%;overflow:hidden}
body{background:var(--bg);color:var(--tx);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:14px;line-height:1.5;display:flex}
button{font-family:inherit;cursor:pointer;border:none;outline:none}

/* ── SIDEBAR ── */
#sidebar{
  width:var(--sbw);flex-shrink:0;background:var(--sb);
  border-right:1px solid var(--bdr);
  display:flex;flex-direction:column;
  position:fixed;left:0;top:0;bottom:0;z-index:50;
}
.sb-logo{padding:14px 16px;border-bottom:1px solid var(--bdr);display:flex;align-items:center;gap:9px}
.live-dot{width:8px;height:8px;border-radius:50%;background:var(--red);flex-shrink:0;animation:ldot 1.6s ease-in-out infinite}
@keyframes ldot{0%,100%{box-shadow:0 0 0 2px rgba(255,68,102,.25)}50%{box-shadow:0 0 0 5px rgba(255,68,102,.05)}}
.sb-logo-name{font-size:13px;font-weight:700;color:var(--tx);letter-spacing:-.3px;flex:1}
.sb-ver{font-size:10px;color:var(--tx3);font-family:monospace}
.sb-sec{padding:8px 0}
.sb-lbl{font-size:10px;font-weight:700;color:var(--tx3);text-transform:uppercase;letter-spacing:.1em;padding:5px 16px 3px}
.nav-item{
  display:flex;align-items:center;gap:9px;padding:8px 16px;
  color:var(--tx2);font-size:13px;font-weight:500;
  cursor:pointer;transition:all .12s;
  border:none;background:none;width:100%;text-align:left;position:relative;
}
.nav-item:hover{color:var(--tx);background:rgba(255,255,255,.04)}
.nav-item.active{color:var(--blue);background:var(--bdim)}
.nav-item.active::before{content:'';position:absolute;left:0;top:5px;bottom:5px;width:3px;background:var(--blue);border-radius:0 3px 3px 0}
.nav-icon{width:17px;text-align:center;flex-shrink:0;font-size:13px}
.nav-badge{margin-left:auto;background:var(--red);color:#fff;font-size:10px;font-weight:700;min-width:17px;height:17px;padding:0 4px;border-radius:9px;display:none;align-items:center;justify-content:center}
.sb-actions{border-top:1px solid var(--bdr);padding:8px 0}
.sb-act-btn{
  display:flex;align-items:center;gap:9px;padding:7px 16px;
  color:var(--tx2);font-size:12px;font-weight:500;
  cursor:pointer;transition:all .12s;border:none;background:none;width:100%;text-align:left;
}
.sb-act-btn:hover{color:var(--tx);background:rgba(255,255,255,.04)}
.sb-act-btn.act-open{color:var(--green);background:var(--gdim)}
.sb-disk{margin-top:auto;padding:12px 16px;border-top:1px solid var(--bdr)}
.sb-disk-row{display:flex;justify-content:space-between;font-size:11px;color:var(--tx2);margin-bottom:5px}
.sb-disk-bar{height:3px;background:var(--surf3);border-radius:2px;overflow:hidden}
.sb-disk-fill{height:3px;border-radius:2px;transition:width .5s}

/* ── PAGE ── */
#page{margin-left:var(--sbw);flex:1;display:flex;flex-direction:column;height:100vh;overflow:hidden}

/* ── TOPBAR ── */
#topbar{
  height:var(--tbh);flex-shrink:0;
  background:rgba(13,13,20,.92);border-bottom:1px solid var(--bdr);
  backdrop-filter:blur(12px);
  display:flex;align-items:center;padding:0 20px;gap:10px;
}
.tb-title{font-size:14px;font-weight:700;color:var(--tx);min-width:120px}
.tb-mission{font-size:12px;color:#8888cc;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.tb-disk{font-size:11px;font-weight:700;padding:3px 9px;border-radius:20px;flex-shrink:0}
.tb-time{font-size:12px;color:var(--tx3);white-space:nowrap;font-family:monospace;flex-shrink:0}

/* ── MAIN ── */
#main{flex:1;overflow-y:auto;padding:18px 20px}
.section{display:none}
.section.active{display:block}
#s-logs.active{display:flex;flex-direction:column;height:100%}

/* ── SECTION HEADER ── */
.sec-hdr{display:flex;align-items:baseline;justify-content:space-between;margin-bottom:16px}
.sec-title{font-size:18px;font-weight:700;color:var(--tx)}
.sec-sub{font-size:12px;color:var(--tx2)}

/* ── NOW PLAYING hero ── */
.hero{
  background:linear-gradient(135deg,#0f0f22,#161630);
  border:1px solid #2a2a4e;border-radius:var(--r);
  padding:16px 20px;margin-bottom:16px;
  position:relative;overflow:hidden;
}
.hero::after{
  content:'';position:absolute;top:0;left:0;right:0;height:2px;
  background:linear-gradient(90deg,var(--blue),var(--pur),var(--green),var(--blue));
  background-size:200% 100%;animation:hline 4s linear infinite;
}
@keyframes hline{0%{background-position:0% 0}100%{background-position:200% 0}}
.hero-badge{position:absolute;top:12px;right:14px;font-size:9px;font-weight:700;color:var(--red);text-transform:uppercase;letter-spacing:.12em;display:flex;align-items:center;gap:4px}
.hero-idle{font-size:13px;color:var(--tx3);font-style:italic;padding:4px 0}
.hero-beat{display:flex;align-items:center;gap:12px}
.hero-char{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.1em;color:var(--tx2);min-width:130px;flex-shrink:0}
.hero-icon{font-size:22px;flex-shrink:0;line-height:1}
.hero-action{font-size:17px;font-weight:700;color:var(--tx);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.hero-detail{font-size:12px;color:var(--tx2);margin-top:6px;padding-left:142px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.hero-ts{font-size:11px;color:var(--tx3);margin-top:5px;padding-left:142px}

/* ── LIVE STATS STRIP ── */
.stats-strip{display:grid;grid-template-columns:repeat(4,1fr);gap:1px;background:var(--bdr);border:1px solid var(--bdr);border-radius:var(--r);overflow:hidden;margin-bottom:16px}
.stat-cell{background:var(--surf);padding:11px 14px}
.stat-lbl{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--tx3);margin-bottom:2px}
.stat-val{font-size:20px;font-weight:800;color:var(--tx);line-height:1.1}
.stat-sub{font-size:11px;color:var(--tx2);margin-top:1px}

/* ── LIVE GRID ── */
.live-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}

/* ── SCENE FEED ── */
.card{background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);overflow:hidden}
.card-hdr{padding:9px 14px;border-bottom:1px solid var(--bdr);display:flex;align-items:center;gap:7px}
.card-ttl{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:var(--tx3);flex:1}
.card-sub{font-size:10px;color:var(--tx3)}
.scene-feed{max-height:320px;overflow-y:auto}
.scene-item{display:flex;align-items:flex-start;gap:0;padding:8px 14px;border-bottom:1px solid var(--bdr);transition:background .1s}
.scene-item:last-child{border:none}
.scene-item:hover{background:var(--surf2)}
.scene-item.is-new{animation:slide-in .3s ease}
@keyframes slide-in{from{opacity:0;transform:translateX(-10px)}to{opacity:1;transform:none}}
.scene-char{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--tx2);min-width:90px;flex-shrink:0;padding-top:1px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.scene-sep{color:var(--tx3);margin:0 8px;flex-shrink:0;font-size:11px;padding-top:1px}
.scene-icon{font-size:12px;flex-shrink:0;margin-right:8px;padding-top:1px}
.scene-body{flex:1;min-width:0}
.scene-txt{font-size:12px;color:var(--tx);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.scene-meta{font-size:10px;color:var(--tx3);margin-top:1px;display:flex;gap:8px}

/* ── MINI LOG ── */
.mini-log{display:flex;flex-direction:column}
.mini-log-tabs{display:flex;flex-wrap:nowrap;overflow-x:auto;border-bottom:1px solid var(--bdr);background:var(--sb);padding:0 6px;scrollbar-width:none;flex-shrink:0}
.mini-log-tabs::-webkit-scrollbar{display:none}
.mini-log-term{background:#060610;color:#3ddc84;font-family:'SF Mono','Fira Code',ui-monospace,monospace;font-size:10.5px;line-height:1.6;padding:8px 10px;height:220px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;flex:1}

/* ── LOG TABS shared ── */
.log-tab{background:none;border:none;border-bottom:2px solid transparent;color:var(--tx2);padding:7px 11px;font-size:11px;cursor:pointer;font-family:inherit;transition:all .12s;white-space:nowrap}
.log-tab:hover{color:var(--tx)}
.log-tab.active{color:var(--green);border-bottom-color:var(--green)}

/* ── AGENTS ── */
.agent-row{display:flex;align-items:center;gap:9px;padding:8px 14px;border-bottom:1px solid var(--bdr)}
.agent-row:last-child{border:none}
.agent-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.dot-g{background:var(--green);box-shadow:0 0 0 3px rgba(0,208,138,.15)}
.dot-r{background:var(--red)}
.dot-x{background:var(--surf3)}
.agent-name{font-size:12px;color:var(--tx);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.alive{color:var(--green);font-size:11px}.dead{color:var(--red);font-size:11px}.unk{color:var(--tx3);font-size:11px}

/* ── INBOX / ALERTS ── */
.inbox-msg{padding:9px 14px;border-bottom:1px solid var(--bdr);cursor:default}
.inbox-msg:last-child{border:none}
.inbox-file{font-size:10px;color:var(--tx3);margin-bottom:2px;font-family:monospace}
.inbox-text{font-size:12px;color:var(--tx);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.alert-row{display:flex;gap:9px;padding:8px 14px;border-bottom:1px solid var(--bdr)}
.alert-row:last-child{border:none}
.alert-app{font-size:11px;font-weight:700;color:var(--yel);flex-shrink:0;min-width:80px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.alert-line{font-size:11px;color:#fca5a5;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.no-alerts{padding:14px;text-align:center;font-size:12px;color:var(--green)}

/* ── APPS ── */
.apps-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px}
.app-card{background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);overflow:hidden;transition:border-color .15s}
.app-card:hover{border-color:var(--bdr2)}
.app-card-hdr{padding:11px 14px;border-bottom:1px solid var(--bdr);display:flex;align-items:center;gap:8px}
.app-health{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.app-name{font-size:13px;font-weight:700;color:var(--tx);flex:1}
.app-body{padding:10px 14px}
.app-views{font-size:22px;font-weight:800;color:var(--tx);line-height:1}
.app-views-sub{font-size:11px;color:var(--tx2);margin-top:2px}
.app-top{font-size:10px;color:var(--tx3);margin-top:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.app-prog{margin-top:8px}
.app-prog-row{display:flex;justify-content:space-between;font-size:11px;color:var(--tx2);margin-bottom:3px}
.app-prog-bar{height:4px;background:var(--surf3);border-radius:2px;overflow:hidden}
.app-prog-fill{height:4px;border-radius:2px;transition:width .5s}
.kv-row{display:flex;justify-content:space-between;font-size:11px;margin-top:4px;gap:8px}
.kv-k{color:var(--tx2);flex-shrink:0}.kv-v{color:var(--tx);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right}

/* ── TASKS ── */
.tasks-layout{display:grid;grid-template-columns:1fr 320px;gap:16px;align-items:start}
.task-row{display:flex;align-items:center;gap:9px;padding:10px 14px;border-bottom:1px solid var(--bdr);transition:background .1s}
.task-row:last-child{border:none}
.task-row:hover{background:var(--surf2)}
.task-pri{font-size:10px;font-weight:700;padding:2px 7px;border-radius:20px;flex-shrink:0;text-transform:uppercase;letter-spacing:.04em}
.ph{background:var(--rdim);color:var(--red)}.pm{background:var(--bdim);color:var(--blue)}.pl{background:rgba(255,255,255,.06);color:var(--tx2)}
.task-desc{flex:1;font-size:13px;color:var(--tx);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.task-id{font-size:11px;color:var(--tx3);flex-shrink:0}
.task-btn{background:none;border:1px solid var(--bdr2);color:var(--tx2);font-size:11px;padding:3px 8px;border-radius:4px;font-family:inherit;transition:all .12s;flex-shrink:0}
.task-btn:hover{background:var(--gdim);border-color:var(--green);color:var(--green)}
.task-empty{padding:22px;text-align:center;color:var(--tx3);font-size:13px}
.add-form{background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);padding:16px}
.form-ttl{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:var(--tx3);margin-bottom:12px}
.finput{display:block;width:100%;background:var(--surf2);border:1px solid var(--bdr2);border-radius:var(--rsm);padding:8px 10px;font-size:13px;color:var(--tx);font-family:inherit;outline:none;margin-bottom:8px;transition:border-color .12s;resize:none}
.finput:focus{border-color:var(--blue)}
.frow{display:flex;gap:8px;align-items:center}
.fselect{flex:1;background:var(--surf2);border:1px solid var(--bdr2);border-radius:var(--rsm);padding:8px 10px;font-size:12px;color:var(--tx);font-family:inherit;outline:none;cursor:pointer}
.fbtn{background:var(--blue);color:#fff;border:none;border-radius:var(--rsm);padding:8px 16px;font-size:13px;font-weight:600;font-family:inherit;cursor:pointer;transition:opacity .12s;flex-shrink:0}
.fbtn:hover{opacity:.85}
.fbtn.g{background:var(--green)}.fbtn.s{background:var(--surf2);border:1px solid var(--bdr2);color:var(--tx2)}
.ffb{font-size:12px;margin-top:8px;min-height:20px}

/* ── LOGS (full) ── */
#s-logs.active .log-panel{flex:1;display:flex;flex-direction:column;min-height:0;background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);overflow:hidden}
.log-term-hdr{display:flex;align-items:center;gap:8px;padding:8px 14px;border-bottom:1px solid var(--bdr);flex-shrink:0}
.log-term-lbl{font-size:11px;color:var(--tx2);font-family:monospace;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.log-term-live{font-size:10px;color:var(--green);display:flex;align-items:center;gap:4px}
.log-full-tabs{display:flex;flex-wrap:nowrap;overflow-x:auto;border-bottom:1px solid var(--bdr);background:var(--sb);padding:0 8px;flex-shrink:0;scrollbar-width:none}
.log-full-tabs::-webkit-scrollbar{display:none}
.log-terminal{flex:1;min-height:0;background:#060610;color:#3ddc84;font-family:'SF Mono','Fira Code',ui-monospace,monospace;font-size:11.5px;line-height:1.65;padding:12px 16px;overflow-y:auto;white-space:pre-wrap;word-break:break-all}
.log-line{animation:fl .1s ease}
@keyframes fl{from{opacity:0}to{opacity:1}}

/* ── BUDGET ── */
.budget-layout{display:grid;grid-template-columns:260px 1fr;gap:16px;align-items:start}
.budget-sum{background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);padding:20px}
.b-total{font-size:36px;font-weight:800;color:var(--tx);line-height:1}
.b-month{font-size:12px;color:var(--tx2);margin-top:4px}
.b-prog{background:var(--surf3);border-radius:4px;height:8px;overflow:hidden;margin-top:14px}
.b-prog-fill{height:8px;border-radius:4px;transition:width .6s}
.b-limit{font-size:12px;color:var(--tx2);margin-top:8px}
.budget-cats{background:var(--surf);border:1px solid var(--bdr);border-radius:var(--r);padding:16px}
.bcat-row{display:flex;align-items:center;gap:10px;margin-bottom:13px}
.bcat-row:last-child{margin:0}
.bcat-name{font-size:13px;color:var(--tx);width:130px;flex-shrink:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bcat-bar{flex:1;background:var(--surf3);border-radius:3px;height:5px;overflow:hidden}
.bcat-fill{height:5px;border-radius:3px;transition:width .5s}
.bcat-val{font-size:12px;color:var(--tx2);width:100px;text-align:right;flex-shrink:0}

/* ── TRACE ── */
.trace-row{display:flex;align-items:flex-start;gap:10px;padding:11px 16px;border-bottom:1px solid var(--bdr)}
.trace-row:last-child{border:none}
.trace-char{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--tx2);min-width:110px;flex-shrink:0;padding-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-icon{width:24px;height:24px;border-radius:6px;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:11px;margin-top:0}
.ti-ok{background:var(--gdim);color:var(--green)}.ti-fail{background:var(--rdim);color:var(--red)}
.trace-body{flex:1;min-width:0}
.trace-action{font-size:13px;color:var(--tx);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-detail{font-size:11px;color:var(--tx2);margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-foot{display:flex;align-items:center;gap:6px;margin-top:4px;flex-wrap:wrap}
.trace-tag{font-size:10px;padding:1px 6px;border-radius:8px;background:var(--surf3);color:var(--tx3)}
.trace-ts{font-size:10px;color:var(--tx3);margin-left:auto;flex-shrink:0}

/* ── ACTION DRAWER ── */
.drawer{
  position:fixed;bottom:0;left:var(--sbw);right:0;z-index:200;
  background:rgba(13,13,20,.97);border-top:1px solid var(--bdr2);
  backdrop-filter:blur(16px);
  transform:translateY(100%);transition:transform .2s cubic-bezier(.4,0,.2,1);
  padding:16px 20px 18px;
}
.drawer.open{transform:translateY(0)}
.drawer-ttl{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:var(--tx2);margin-bottom:12px;display:flex;align-items:center;justify-content:space-between}
.drawer-close{background:none;border:none;color:var(--tx2);font-size:18px;cursor:pointer;padding:0 2px;line-height:1;transition:color .12s}
.drawer-close:hover{color:var(--tx)}

/* ── MOBILE TABS ── */
#mob-tabs{
  display:none;
  position:fixed;bottom:0;left:0;right:0;z-index:100;
  background:rgba(10,10,18,.97);border-top:1px solid var(--bdr);
  backdrop-filter:blur(12px);height:56px;
  flex-direction:row;align-items:stretch;
}
.mob-tab{flex:1;background:none;border:none;color:var(--tx2);font-size:10px;font-weight:600;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;cursor:pointer;transition:color .12s;position:relative}
.mob-tab.active{color:var(--blue)}
.mob-icon{font-size:16px;line-height:1}
.mob-badge{position:absolute;top:6px;right:calc(50% - 15px);background:var(--red);color:#fff;font-size:9px;font-weight:700;min-width:15px;height:15px;border-radius:8px;padding:0 3px;display:none;align-items:center;justify-content:center}

/* ── UTILS ── */
.badge{display:inline-flex;align-items:center;justify-content:center;font-size:10px;font-weight:700;min-width:18px;height:18px;padding:0 5px;border-radius:9px}
.b-blue{background:var(--bdim);color:var(--blue)}.b-green{background:var(--gdim);color:var(--green)}
.b-red{background:var(--rdim);color:var(--red)}.b-yel{background:var(--ydim);color:var(--yel)}
.empty{padding:20px;text-align:center;color:var(--tx3);font-size:13px}
.mt16{margin-top:16px}
.row2{display:grid;grid-template-columns:1fr 1fr;gap:14px}

@media(max-width:1100px){.live-grid,.row2{grid-template-columns:1fr}}
@media(max-width:768px){
  :root{--sbw:0px}
  #sidebar{display:none}
  #page{margin-left:0}
  #mob-tabs{display:flex}
  #main{padding:12px 12px 68px}
  .tasks-layout,.budget-layout,.live-grid,.row2{grid-template-columns:1fr}
  .drawer{left:0}
  .stats-strip{grid-template-columns:1fr 1fr}
  .stat-cell:last-child,.stat-cell:nth-child(3){display:none}
}
</style>
</head>
<body>

<!-- SIDEBAR -->
<div id="sidebar">
  <div class="sb-logo">
    <div class="live-dot"></div>
    <span class="sb-logo-name">Agent Computer</span>
    <span class="sb-ver" id="sb-ver">v?</span>
  </div>
  <div class="sb-sec">
    <div class="sb-lbl">MONITOR</div>
    <button class="nav-item active" data-nav="live" onclick="navTo('live')"><span class="nav-icon">⬤</span>Live Feed</button>
    <button class="nav-item" data-nav="apps" onclick="navTo('apps')"><span class="nav-icon">⊞</span>Apps</button>
    <button class="nav-item" data-nav="logs" onclick="navTo('logs')"><span class="nav-icon">≡</span>Log Viewer</button>
  </div>
  <div class="sb-sec">
    <div class="sb-lbl">MANAGE</div>
    <button class="nav-item" data-nav="tasks" onclick="navTo('tasks')"><span class="nav-icon">✓</span>Tasks<span id="sb-tasks-badge" class="nav-badge">0</span></button>
    <button class="nav-item" data-nav="budget" onclick="navTo('budget')"><span class="nav-icon">$</span>Budget</button>
    <button class="nav-item" data-nav="trace" onclick="navTo('trace')"><span class="nav-icon">◎</span>Trace</button>
  </div>
  <div class="sb-actions">
    <div class="sb-lbl">ACTIONS</div>
    <button class="sb-act-btn" data-act="add-task" onclick="openDrawer('add-task')"><span class="nav-icon">＋</span>Add Task</button>
    <button class="sb-act-btn" data-act="log" onclick="openDrawer('log')"><span class="nav-icon">✓</span>Log Outcome</button>
    <button class="sb-act-btn" data-act="run" onclick="openDrawer('run')"><span class="nav-icon">▶</span>Run Job</button>
    <button class="sb-act-btn" data-act="note" onclick="openDrawer('note')"><span class="nav-icon">✎</span>Note</button>
    <button class="sb-act-btn" onclick="clearAlerts()"><span class="nav-icon">✗</span>Clear Alerts</button>
  </div>
  <div class="sb-disk">
    <div class="sb-disk-row"><span>Disk</span><span id="sb-disk-txt">—</span></div>
    <div class="sb-disk-bar"><div id="sb-disk-fill" class="sb-disk-fill" style="width:0%;background:var(--green)"></div></div>
  </div>
</div>

<!-- PAGE -->
<div id="page">
  <div id="topbar">
    <div class="tb-title" id="tb-title">Live Feed</div>
    <div class="tb-mission" id="tb-mission"></div>
    <span class="tb-disk" id="tb-disk">—</span>
    <span class="tb-time" id="tb-time">connecting…</span>
  </div>

  <div id="main">

    <!-- LIVE -->
    <div id="s-live" class="section active">
      <!-- NOW PLAYING -->
      <div class="hero" id="hero">
        <div class="hero-badge"><span style="width:6px;height:6px;border-radius:50%;background:var(--red);display:inline-block;animation:ldot 1.6s ease-in-out infinite"></span>NOW PLAYING</div>
        <div id="hero-content"><div class="hero-idle">Waiting for agent activity…</div></div>
      </div>
      <!-- Stats -->
      <div class="stats-strip" id="stats-strip">
        <div class="stat-cell"><div class="stat-lbl">Disk Used</div><div class="stat-val" id="st-disk">—</div><div class="stat-sub" id="st-disk-sub">—</div></div>
        <div class="stat-cell"><div class="stat-lbl">Open Tasks</div><div class="stat-val" id="st-tasks">—</div><div class="stat-sub">tasks</div></div>
        <div class="stat-cell"><div class="stat-lbl">Agents</div><div class="stat-val" id="st-agents">—</div><div class="stat-sub">alive</div></div>
        <div class="stat-cell"><div class="stat-lbl">Cron Jobs</div><div class="stat-val" id="st-cron">—</div><div class="stat-sub">scheduled</div></div>
      </div>
      <!-- Feed + Log -->
      <div class="live-grid">
        <div class="card">
          <div class="card-hdr">
            <div class="live-dot" style="width:6px;height:6px"></div>
            <span class="card-ttl">Scene Feed</span>
            <span class="card-sub">trace · inbox · alerts</span>
          </div>
          <div id="scene-feed" class="scene-feed"><div class="empty">connecting…</div></div>
        </div>
        <div class="card mini-log">
          <div class="card-hdr"><span class="card-ttl">Log Stream</span><span class="card-sub" id="mini-log-lbl">no source</span></div>
          <div class="mini-log-tabs" id="mini-log-tabs"></div>
          <div class="mini-log-term" id="mini-log-term"></div>
        </div>
      </div>
      <!-- Agents + Inbox + Alerts -->
      <div class="row2 mt16">
        <div>
          <div class="card">
            <div class="card-hdr"><span class="card-ttl">Cast — Agents</span></div>
            <div id="agent-list"><div class="empty">loading…</div></div>
          </div>
          <div class="card mt16">
            <div class="card-hdr"><span class="card-ttl">Alerts</span><button class="task-btn" style="font-size:10px;padding:2px 7px" onclick="clearAlerts()">clear</button></div>
            <div id="alerts-list"><div class="no-alerts">✓ No errors in last 24h</div></div>
          </div>
        </div>
        <div class="card">
          <div class="card-hdr"><span class="card-ttl">Inbox</span><span id="inbox-badge" class="badge b-yel" style="display:none"></span></div>
          <div id="inbox-list"><div class="empty">inbox empty</div></div>
        </div>
      </div>
    </div>

    <!-- APPS -->
    <div id="s-apps" class="section">
      <div class="sec-hdr"><span class="sec-title">Apps</span><span class="sec-sub" id="apps-count"></span></div>
      <div class="apps-grid" id="apps-grid"><div class="empty">scanning ~/apps/…</div></div>
    </div>

    <!-- TASKS -->
    <div id="s-tasks" class="section">
      <div class="sec-hdr"><span class="sec-title">Tasks</span></div>
      <div class="tasks-layout">
        <div>
          <div class="card" id="task-card"><div id="task-list"><div class="empty">loading…</div></div></div>
          <div class="card mt16" id="sched-card" style="display:none">
            <div class="card-hdr"><span class="card-ttl">Scheduled Jobs</span><span id="sched-count" class="badge b-blue"></span></div>
            <div id="sched-list"></div>
          </div>
        </div>
        <div class="add-form">
          <div class="form-ttl">Add New Task</div>
          <input class="finput" id="task-desc" placeholder="Describe the task…" maxlength="500" autocomplete="off">
          <div class="frow">
            <select class="fselect" id="task-pri">
              <option value="medium">Medium priority</option>
              <option value="high">High priority</option>
              <option value="low">Low priority</option>
            </select>
            <button class="fbtn" onclick="addTask()">Add Task</button>
          </div>
          <div class="ffb" id="task-fb"></div>
        </div>
      </div>
    </div>

    <!-- LOGS -->
    <div id="s-logs" class="section">
      <div class="log-panel">
        <div class="log-term-hdr">
          <span class="log-term-lbl" id="log-lbl">select a log source below</span>
          <span class="log-term-live"><span style="width:6px;height:6px;border-radius:50%;background:var(--green);display:inline-block"></span>live</span>
        </div>
        <div class="log-full-tabs" id="log-tabs"></div>
        <div class="log-terminal" id="log-terminal"></div>
      </div>
    </div>

    <!-- BUDGET -->
    <div id="s-budget" class="section">
      <div class="sec-hdr"><span class="sec-title">Budget</span></div>
      <div class="budget-layout">
        <div class="budget-sum" id="budget-sum"></div>
        <div class="budget-cats" id="budget-cats"></div>
      </div>
    </div>

    <!-- TRACE -->
    <div id="s-trace" class="section">
      <div class="sec-hdr"><span class="sec-title">Trace Log</span><span class="sec-sub" id="trace-count"></span></div>
      <div class="card"><div id="trace-list"><div class="empty">loading…</div></div></div>
    </div>

  </div><!-- #main -->
</div><!-- #page -->

<!-- ACTION DRAWER -->
<div id="drawer" class="drawer"></div>

<!-- MOBILE TABS -->
<div id="mob-tabs">
  <button class="mob-tab active" data-nav="live" onclick="mobNav('live')"><span class="mob-icon">⬤</span><span>Live</span></button>
  <button class="mob-tab" data-nav="apps" onclick="mobNav('apps')"><span class="mob-icon">⊞</span><span>Apps</span></button>
  <button class="mob-tab" data-nav="tasks" onclick="mobNav('tasks')"><span class="mob-icon">✓</span><span>Tasks</span><span class="mob-badge" id="mob-badge" style="display:none">0</span></button>
  <button class="mob-tab" data-nav="logs" onclick="mobNav('logs')"><span class="mob-icon">≡</span><span>Logs</span></button>
  <button class="mob-tab" data-nav="trace" onclick="mobNav('trace')"><span class="mob-icon">◎</span><span>Trace</span></button>
</div>

<script>
const $ = id => document.getElementById(id)
const esc = s => String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
const fmt = n => Number(n||0).toLocaleString()

function timeAgo(ts) {
  if (!ts) return ''
  try {
    const s = Math.floor((Date.now() - new Date(ts).getTime()) / 1000)
    if (s < 10) return 'just now'
    if (s < 60) return s+'s ago'
    if (s < 3600) return Math.floor(s/60)+'m ago'
    if (s < 86400) return Math.floor(s/3600)+'h ago'
    return Math.floor(s/86400)+'d ago'
  } catch { return '' }
}

function barColor(p) { return p>=90?'var(--red)':p>=70?'var(--yel)':'var(--blue)' }
function diskColor(p) { return p>=90?'var(--red)':p>=75?'var(--yel)':'var(--green)' }

// ── Navigation ────────────────────────────────────────────────────────────────

const SEC_TITLES = {live:'Live Feed',apps:'Apps',tasks:'Tasks',logs:'Log Viewer',budget:'Budget',trace:'Trace Log'}
let _cur = 'live'

function navTo(name) {
  _cur = name
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'))
  document.querySelectorAll('[data-nav]').forEach(n => n.classList.remove('active'))
  const sec = $('s-'+name); if (sec) sec.classList.add('active')
  document.querySelectorAll(`[data-nav="${name}"]`).forEach(n => n.classList.add('active'))
  const tt = $('tb-title'); if (tt) tt.textContent = SEC_TITLES[name] || 'Agent Computer'
}
function mobNav(name) { navTo(name) }

// ── Hero ──────────────────────────────────────────────────────────────────────

function updateHero(trace) {
  const el = $('hero-content'); if (!el) return
  const items = [...trace].reverse()
  const latest = items[0]
  if (!latest) { el.innerHTML = '<div class="hero-idle">Watching for agent activity…</div>'; return }
  const ok = latest.outcome === 'success'
  const agent = latest.agent || 'agent'
  el.innerHTML = `
    <div class="hero-beat">
      <div class="hero-char">${esc(agent)}</div>
      <div class="hero-icon" style="color:${ok?'var(--green)':'var(--red)'}">${ok?'✓':'✗'}</div>
      <div class="hero-action">${esc(latest.action)}</div>
    </div>
    ${latest.detail?`<div class="hero-detail">${esc(latest.detail)}</div>`:''}
    <div class="hero-ts">${timeAgo(latest.ts)}</div>`
}

// ── Scene Feed ────────────────────────────────────────────────────────────────

let _lastActKeys = []

function renderActivity(events) {
  const el = $('scene-feed'); if (!el) return
  const keys = events.map(e => e.ts+'|'+e.type+'|'+(e.text||'').slice(0,30))
  const newSet = new Set(keys.filter(k => !_lastActKeys.includes(k)))
  _lastActKeys = keys
  if (!events.length) { el.innerHTML = '<div class="empty">watching for agent activity…</div>'; return }
  el.innerHTML = events.map(e => {
    const isNew = newSet.has(e.ts+'|'+e.type+'|'+(e.text||'').slice(0,30))
    const agent = e.agent || e.type
    return `<div class="scene-item${isNew?' is-new':''}">
      <div class="scene-char" title="${esc(agent)}">${esc(agent)}</div>
      <div class="scene-sep">→</div>
      <div class="scene-icon" style="color:${e.color}">${esc(e.icon)}</div>
      <div class="scene-body">
        <div class="scene-txt" title="${esc(e.text)}">${esc(e.text)}</div>
        <div class="scene-meta"><span>${esc(e.type)}</span><span>${timeAgo(e.ts)}</span></div>
      </div>
    </div>`
  }).join('')
}

// ── Agents ────────────────────────────────────────────────────────────────────

function renderAgents(agents) {
  const el = $('agent-list'); if (!el) return
  const entries = Object.entries(agents)
  if (!entries.length) { el.innerHTML = '<div class="empty">no agents registered in ~/system/agents.json</div>'; return }
  el.innerHTML = entries.map(([name,info]) => {
    const a = info.alive
    const dc = a===true?'dot-g':a===false?'dot-r':'dot-x'
    const sc = a===true?'alive':a===false?'dead':'unk'
    const sl = a===true?'● alive':a===false?'○ unreachable':'– no check'
    return `<div class="agent-row"><div class="agent-dot ${dc}"></div><div class="agent-name">${esc(name)}</div><div class="${sc}">${sl}</div></div>`
  }).join('')
}

// ── Inbox / Alerts ────────────────────────────────────────────────────────────

function renderInbox(inbox) {
  const el = $('inbox-list'), badge = $('inbox-badge'); if (!el) return
  if (badge) { badge.textContent = inbox.length||''; badge.style.display = inbox.length?'inline-flex':'none' }
  el.innerHTML = inbox.length ? inbox.map(n => `
    <div class="inbox-msg">
      <div class="inbox-file">${esc(n.file)}</div>
      <div class="inbox-text" title="${esc(n.text)}">${esc(n.text)}</div>
    </div>`).join('') : '<div class="empty">inbox empty</div>'
}

function renderAlerts(alerts) {
  const el = $('alerts-list'); if (!el) return
  el.innerHTML = alerts.length ? alerts.map(a =>
    `<div class="alert-row"><span class="alert-app">${esc(a.app)}</span><span class="alert-line">${esc(a.line)}</span></div>`
  ).join('') : '<div class="no-alerts">✓ No errors in last 24h</div>'
}

// ── Apps ──────────────────────────────────────────────────────────────────────

function renderApps(apps) {
  const SKIP = new Set(['done_today','expected_today','errors_today','healthy','checked','live_processes','alerts','fixes'])
  const grid = $('apps-grid'), cnt = $('apps-count'); if (!grid) return
  if (!apps.length) { grid.innerHTML = '<div class="empty">no apps found under ~/apps/ with a state/ directory</div>'; return }
  if (cnt) cnt.textContent = apps.length + ' app' + (apps.length===1?'':'s') + ' discovered'
  grid.innerHTML = apps.map(app => {
    const st = app.status||{}, healthy = st.healthy
    const hc = healthy===true?'var(--green)':healthy===false?'var(--red)':'var(--tx3)'
    const hshadow = healthy===true?`box-shadow:0 0 0 3px rgba(0,208,138,.2)`:''
    const hasP = st.done_today!==undefined && st.expected_today!==undefined
    const done = st.done_today||0, exp = st.expected_today||1, prog = Math.round(done/exp*100)
    const errors = st.errors_today||0
    const kv = Object.entries(st).filter(([k])=>!SKIP.has(k)).slice(0,4)
      .map(([k,v])=>`<div class="kv-row"><span class="kv-k">${esc(k)}</span><span class="kv-v">${esc(typeof v==='object'?JSON.stringify(v).slice(0,40):String(v).slice(0,50))}</span></div>`).join('')
    return `<div class="app-card">
      <div class="app-card-hdr">
        <div class="app-health" style="background:${hc};${hshadow}"></div>
        <div class="app-name">${esc(app.name)}</div>
        ${errors>0?`<span class="badge b-red">${errors}err</span>`:''}
      </div>
      <div class="app-body">
        ${app.views_7d?`<div class="app-views">${fmt(app.views_7d)}</div><div class="app-views-sub">views · last 7 days</div>`:''}
        ${app.top_video?`<div class="app-top">"${esc(app.top_video)}" · ${fmt(app.top_views||0)} views</div>`:''}
        ${hasP?`<div class="app-prog"><div class="app-prog-row"><span>Progress</span><span>${done}/${st.expected_today}</span></div><div class="app-prog-bar"><div class="app-prog-fill" style="width:${prog}%;background:${hc}"></div></div></div>`:''}
        ${kv}
      </div>
    </div>`
  }).join('')
}

// ── Tasks + Sched ─────────────────────────────────────────────────────────────

function renderTasks(tasks, sched) {
  const open = tasks.filter(t => t.status === 'open')
  // badges
  const sb = $('sb-tasks-badge'), mb = $('mob-badge')
  if (sb) { sb.textContent = open.length||''; sb.style.display = open.length?'inline-flex':'none' }
  if (mb) { mb.textContent = open.length||''; mb.style.display = open.length?'inline-flex':'none' }
  // Live stats
  const st = $('st-tasks'); if (st) st.textContent = open.length
  // Task list
  const el = $('task-list'); if (!el) return
  el.innerHTML = open.length ? open.map(t => {
    const pc = {high:'ph',medium:'pm',low:'pl'}[t.priority||'medium']||'pm'
    return `<div class="task-row">
      <span class="task-pri ${pc}">${esc(t.priority||'med')}</span>
      <span class="task-desc" title="${esc(t.desc)}">${esc(t.desc)}</span>
      <span class="task-id">#${t.id}</span>
      <button class="task-btn" onclick="markDone(${t.id},this)">done</button>
    </div>`
  }).join('') : '<div class="task-empty">✓ All tasks complete</div>'
  // Sched
  const sc = $('sched-card'), sl = $('sched-list'), scnt = $('sched-count')
  if (!sc||!sl) return
  if (sched.length) {
    sc.style.display=''; if(scnt) scnt.textContent=sched.length
    sl.innerHTML = sched.map(j => {
      const lr = j.last_run?j.last_run.slice(0,10):'never'
      const le = j.last_exit!==null?(j.last_exit===0?'<span style="color:var(--green)">✓</span>':'<span style="color:var(--red)">✗</span>'):'–'
      return `<div class="task-row">
        <span class="task-pri ${j.paused?'pl':'pm'}" style="min-width:80px">${j.paused?'paused':esc(j.schedule_human||j.cron||'?')}</span>
        <span class="task-desc">${esc(j.name)}</span>
        <span class="task-id">${lr} ${le}</span>
        <button class="task-btn" onclick="runJobBtn('${esc(j.name)}',this)">▶</button>
      </div>`
    }).join('')
  } else sc.style.display = 'none'
}

// ── Budget ────────────────────────────────────────────────────────────────────

function renderBudget(budget) {
  const total = budget.total||0, bycat = budget.by_category||{}, thresh = budget.thresholds||{}
  const sum = $('budget-sum'), cats = $('budget-cats'); if (!sum||!cats) return
  const tt = parseFloat(thresh.total||0), tp = tt?Math.min(100,total/tt*100):0
  sum.innerHTML = `
    <div class="b-total">$${total.toFixed(4)}</div>
    <div class="b-month">${esc(budget.month||'')} spend</div>
    ${tt?`<div class="b-prog"><div class="b-prog-fill" style="width:${tp.toFixed(1)}%;background:${barColor(tp)}"></div></div><div class="b-limit">of $${tt.toFixed(2)} limit · ${tp.toFixed(0)}%</div>`:'<div class="b-limit">no limit set</div>'}`
  if (!Object.keys(bycat).length) { cats.innerHTML = '<div class="empty">no spend logged this month</div>'; return }
  cats.innerHTML = '<div class="form-ttl" style="margin-bottom:14px">By Category</div>' +
    Object.entries(bycat).map(([cat,val]) => {
      const ct = parseFloat(thresh[cat]||0), cp = ct?Math.min(100,val/ct*100):0
      return `<div class="bcat-row">
        <div class="bcat-name" title="${esc(cat)}">${esc(cat)}</div>
        <div class="bcat-bar"><div class="bcat-fill" style="width:${Math.max(2,cp).toFixed(1)}%;background:${barColor(cp)}"></div></div>
        <div class="bcat-val">$${val.toFixed(4)}${ct?' / $'+ct.toFixed(2):''}</div>
      </div>`
    }).join('')
}

// ── Trace ─────────────────────────────────────────────────────────────────────

function renderTrace(trace) {
  const el = $('trace-list'), cnt = $('trace-count'); if (!el) return
  const items = [...trace].reverse().slice(0,25)
  if (cnt) cnt.textContent = items.length + ' entries'
  el.innerHTML = items.length ? items.map(e => {
    const ok = e.outcome === 'success'
    const agent = e.agent || 'agent'
    const tags = (e.tags||[]).map(t=>`<span class="trace-tag">${esc(t)}</span>`).join('')
    return `<div class="trace-row">
      <div class="trace-char" title="${esc(agent)}">${esc(agent)}</div>
      <div class="trace-icon ${ok?'ti-ok':'ti-fail'}">${ok?'✓':'✗'}</div>
      <div class="trace-body">
        <div class="trace-action" title="${esc(e.action)}">${esc(e.action)}</div>
        ${e.detail?`<div class="trace-detail">${esc(e.detail)}</div>`:''}
        <div class="trace-foot">${tags}<span class="trace-ts">${timeAgo(e.ts)}</span></div>
      </div>
    </div>`
  }).join('') : '<div class="empty">no outcomes logged yet — use: axis trace log</div>'
}

// ── Log viewer ────────────────────────────────────────────────────────────────

let logEs=null, activeLogPath='', miniLogEs=null, miniLogPath='', _logKey=''

function populateLogTabs(sources) {
  const key = JSON.stringify(sources.map(s=>s.path))
  if (key === _logKey) return
  _logKey = key
  const tabs = $('log-tabs'), miniTabs = $('mini-log-tabs')
  if (!sources.length) {
    if (tabs) tabs.innerHTML = '<span style="color:var(--tx3);padding:7px 12px;font-size:11px">no .log files found under ~/apps/ or ~/system/</span>'
    return
  }
  const mkTab = (s,i,mini) => `<button class="log-tab${i===0?' active':''}" data-path="${esc(s.path)}" data-label="${esc(s.label)}" onclick="switchLog(this,${mini})">${esc(s.label)}</button>`
  if (tabs) tabs.innerHTML = sources.map((s,i)=>mkTab(s,i,false)).join('')
  if (miniTabs) miniTabs.innerHTML = sources.map((s,i)=>mkTab(s,i,true)).join('')
  if (!activeLogPath && sources.length) {
    const b = tabs&&tabs.querySelector('.log-tab'); if (b) switchLog(b,false)
  }
  if (!miniLogPath && sources.length) {
    const b = miniTabs&&miniTabs.querySelector('.log-tab'); if (b) switchLog(b,true)
  }
}

function switchLog(btn, isMini) {
  if (!btn) return
  const cont = isMini ? $('mini-log-tabs') : $('log-tabs')
  const term = isMini ? $('mini-log-term') : $('log-terminal')
  if (cont) cont.querySelectorAll('.log-tab').forEach(b=>b.classList.remove('active'))
  btn.classList.add('active')
  const path = btn.dataset.path, label = btn.dataset.label
  if (isMini) {
    if (!path || path===miniLogPath) return
    miniLogPath = path
    const lbl = $('mini-log-lbl'); if(lbl) lbl.textContent = label||''
    if (miniLogEs) { miniLogEs.close(); miniLogEs=null }
    if (term) term.innerHTML = ''
    miniLogEs = new EventSource('/api/logs/stream?path='+encodeURIComponent(path))
    miniLogEs.addEventListener('log', e => appendLog(term, e.data, 120))
  } else {
    if (!path || path===activeLogPath) return
    activeLogPath = path
    const lbl = $('log-lbl'); if(lbl) lbl.textContent = label||''
    if (logEs) { logEs.close(); logEs=null }
    if (term) term.innerHTML = ''
    logEs = new EventSource('/api/logs/stream?path='+encodeURIComponent(path))
    logEs.addEventListener('log', e => appendLog(term, e.data, 400))
  }
}

function appendLog(term, text, maxLines) {
  if (!term) return
  const d = document.createElement('div')
  d.className = 'log-line'
  d.textContent = text
  term.appendChild(d)
  while (term.children.length > maxLines) term.removeChild(term.firstChild)
  term.scrollTop = term.scrollHeight
}

// ── Master render ─────────────────────────────────────────────────────────────

function render(s) {
  window._lastSched = s.sched || []
  const sys = s.system||{}, env = s.env||{}
  const pct = sys.used_pct||0, dc = diskColor(pct)
  // Topbar
  const tt = $('tb-time'); if(tt) tt.textContent = (s.ts||'').slice(11,16)+' UTC'
  const td = $('tb-disk')
  if(td) { td.textContent=(sys.free_gb||'?')+' GB free'; td.style.cssText=`color:${dc};background:${dc}18;padding:3px 9px;border-radius:20px;font-size:11px;font-weight:700` }
  const tm = $('tb-mission'); if(tm && env.mission) tm.textContent = env.mission
  // Sidebar
  const sv = $('sb-ver'); if(sv) sv.textContent='v'+(sys.version||'?')
  const sf = $('sb-disk-fill'), st = $('sb-disk-txt')
  if(sf) { sf.style.width=pct+'%'; sf.style.background=dc }
  if(st) st.textContent=(sys.free_gb||'?')+' GB · '+pct+'%'
  // Live stats
  const sd = $('st-disk'), sds = $('st-disk-sub')
  if(sd) { sd.textContent=pct+'%'; sd.style.color=dc }
  if(sds) sds.textContent=(sys.free_gb||'?')+' GB free'
  const ag = s.agents||{}, agCount = Object.keys(ag).length, agAlive = Object.values(ag).filter(a=>a.alive===true).length
  const sa = $('st-agents'); if(sa) { sa.textContent=agCount?`${agAlive}/${agCount}`:'none'; sa.style.color=agCount?'var(--tx)':'var(--tx3)' }
  const sc2 = $('st-cron'); if(sc2) sc2.textContent=(s.cron||[]).length
  // Sections
  updateHero(s.trace||[])
  renderActivity(s.activity||[])
  populateLogTabs(s.log_sources||[])
  renderApps(s.apps||[])
  renderTasks(s.tasks||[], s.sched||[])
  renderBudget(s.budget||{})
  renderTrace(s.trace||[])
  renderAgents(ag)
  renderInbox(s.inbox||[])
  renderAlerts(s.alerts||[])
}

// ── SSE ───────────────────────────────────────────────────────────────────────

let stateEs = null
function connectSSE() {
  if (stateEs) stateEs.close()
  stateEs = new EventSource('/api/stream')
  stateEs.addEventListener('state', e => { try { render(JSON.parse(e.data)) } catch(err) { console.warn(err) } })
  stateEs.onerror = () => { const t=$('tb-time'); if(t) t.textContent='reconnecting…' }
}
connectSSE()
navTo('live')

// ── Task actions ──────────────────────────────────────────────────────────────

async function markDone(id, btn) {
  btn.textContent='…'; btn.disabled=true
  const r = await fetch('/api/task/done',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})})
  if (r.ok) { btn.textContent='✓'; btn.style.color='var(--green)' }
  else { btn.textContent='err'; btn.disabled=false }
}

async function addTask() {
  const desc=($('task-desc')||{}).value?.trim(), pri=($('task-pri')||{}).value
  const fb=$('task-fb')
  if (!desc) { if(fb) fb.innerHTML='<span style="color:var(--red)">Enter a description</span>'; return }
  const r = await fetch('/api/task/add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({desc,priority:pri})})
  const res = await r.json()
  if (res.ok) {
    $('task-desc').value=''
    if(fb) fb.innerHTML='<span style="color:var(--green)">✓ Task added</span>'
    setTimeout(()=>{ if(fb) fb.innerHTML='' },2000)
  } else {
    if(fb) fb.innerHTML=`<span style="color:var(--red)">✗ ${esc(res.error||'error')}</span>`
  }
}

async function runJobBtn(name, btn) {
  btn.textContent='…'; btn.disabled=true
  const r = await fetch('/api/sched/run',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name})})
  const res = await r.json()
  btn.textContent=res.ok?'✓':'✗'; btn.style.color=res.ok?'var(--green)':'var(--red)'
  setTimeout(()=>{ btn.textContent='▶'; btn.style.color=''; btn.disabled=false },2500)
}

// ── Action drawer ─────────────────────────────────────────────────────────────

let _drawerOpen = null

function openDrawer(name) {
  const el = $('drawer')
  if (_drawerOpen===name) { closeDrawer(); return }
  _drawerOpen = name
  document.querySelectorAll('.sb-act-btn').forEach(b=>b.classList.remove('act-open'))
  const ab = document.querySelector(`[data-act="${name}"]`); if(ab) ab.classList.add('act-open')
  const forms = {
    'add-task':`
      <div class="drawer-ttl">Add Task <button class="drawer-close" onclick="closeDrawer()">×</button></div>
      <input class="finput" id="d-desc" placeholder="Task description" maxlength="500" autocomplete="off">
      <div class="frow">
        <select class="fselect" id="d-pri"><option value="medium">Medium</option><option value="high">High</option><option value="low">Low</option></select>
        <button class="fbtn" onclick="dPost('task/add',{desc:($('d-desc')||{}).value?.trim(),priority:($('d-pri')||{}).value})">Add</button>
      </div><div class="ffb" id="d-fb"></div>`,
    'log':`
      <div class="drawer-ttl">Log Outcome <button class="drawer-close" onclick="closeDrawer()">×</button></div>
      <input class="finput" id="d-act" placeholder="What did the agent do?" maxlength="300" autocomplete="off">
      <div class="frow">
        <select class="fselect" id="d-out"><option value="success">Success</option><option value="fail">Fail</option></select>
        <input class="finput" id="d-det" placeholder="Detail (optional)" maxlength="500" style="flex:2;margin:0">
        <button class="fbtn g" onclick="dPost('trace/log',{action:($('d-act')||{}).value?.trim(),outcome:($('d-out')||{}).value,detail:($('d-det')||{}).value?.trim()})">Log</button>
      </div><div class="ffb" id="d-fb"></div>`,
    'run':`
      <div class="drawer-ttl">Run Job <button class="drawer-close" onclick="closeDrawer()">×</button></div>
      <div class="frow">
        <select class="fselect" id="d-job">${(window._lastSched||[]).map(j=>`<option value="${esc(j.name)}">${esc(j.name)} — ${esc(j.schedule_human||j.cron||'')}</option>`).join('')||'<option>no jobs found</option>'}</select>
        <button class="fbtn" onclick="dPost('sched/run',{name:($('d-job')||{}).value})">▶ Run</button>
      </div><div class="ffb" id="d-fb"></div>`,
    'note':`
      <div class="drawer-ttl">Send Note <button class="drawer-close" onclick="closeDrawer()">×</button></div>
      <textarea class="finput" id="d-note" placeholder="Message for the next agent…" rows="2" maxlength="2000" style="resize:none"></textarea>
      <button class="fbtn" onclick="dPost('note',{text:($('d-note')||{}).value?.trim()})">Send Note</button>
      <div class="ffb" id="d-fb"></div>`,
  }
  el.innerHTML = forms[name] || ''
  el.classList.add('open')
  setTimeout(()=>{ const inp=el.querySelector('input,textarea'); if(inp) inp.focus() },80)
}

function closeDrawer() {
  _drawerOpen = null
  const el = $('drawer'); if(el) el.classList.remove('open')
  document.querySelectorAll('.sb-act-btn').forEach(b=>b.classList.remove('act-open'))
}

async function dPost(endpoint, payload) {
  const fb = $('d-fb')
  if (payload.desc === '' || payload.action === '') {
    if(fb) fb.innerHTML='<span style="color:var(--red)">Required field is empty</span>'; return
  }
  try {
    const r = await fetch('/api/'+endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})
    const res = await r.json()
    if (res.ok) { if(fb) fb.innerHTML='<span style="color:var(--green)">✓ Done</span>'; setTimeout(closeDrawer,1200) }
    else { if(fb) fb.innerHTML=`<span style="color:var(--red)">✗ ${esc(res.error||'error')}</span>` }
  } catch { if(fb) fb.innerHTML='<span style="color:var(--red)">✗ network error</span>' }
}

async function clearAlerts() {
  await fetch('/api/alert/clear',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
}
</script>
</body>
</html>"""

# ── HTTP handler ──────────────────────────────────────────────────────────────

class DashHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def check_auth(self):
        token = getattr(self.server, "token", "")
        if not token: return True
        return self.headers.get("Authorization","") == f"Bearer {token}"

    def send_json(self, data, status=200):
        body = json.dumps(data, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",len(body))
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html):
        b = html.encode()
        self.send_response(200)
        self.send_header("Content-Type","text/html; charset=utf-8")
        self.send_header("Content-Length",len(b))
        self.end_headers()
        self.wfile.write(b)

    def _sse_headers(self):
        self.send_response(200)
        self.send_header("Content-Type","text/event-stream")
        self.send_header("Cache-Control","no-cache")
        self.send_header("Connection","keep-alive")
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()

    def _serve_sse_state(self):
        self._sse_headers()
        TRACE = HOME / "system/trace.jsonl"
        try: last_sz = TRACE.stat().st_size if TRACE.exists() else 0
        except OSError: last_sz = 0
        try:
            while True:
                payload = json.dumps(build_state(), default=str)
                self.wfile.write(f"event: state\ndata: {payload}\n\n".encode())
                self.wfile.flush()
                # Check every 0.25s for trace changes; push immediately on change
                for _ in range(4):
                    time.sleep(0.25)
                    try:
                        sz = TRACE.stat().st_size
                        if sz != last_sz: last_sz = sz; break
                    except OSError: pass
        except (BrokenPipeError, ConnectionResetError, OSError): pass

    def _serve_sse_logs(self, query_string):
        params = parse_qs(query_string)
        raw = unquote(params.get("path",[""])[0])
        try: abs_path = str(Path(raw).resolve())
        except: abs_path = ""
        home_str = str(HOME)
        if not abs_path or not abs_path.startswith(home_str) or not abs_path.endswith(".log"):
            self._sse_headers()
            self.wfile.write(b"event: error\ndata: forbidden\n\n")
            self.wfile.flush(); return
        allowed = {d["path"] for d in discover_logs()}
        if abs_path not in allowed:
            self._sse_headers()
            self.wfile.write(b"event: error\ndata: forbidden\n\n")
            self.wfile.flush(); return
        self._sse_headers()
        try:
            result = subprocess.run(["tail","-n","40",abs_path], capture_output=True, text=True, timeout=5)
            for line in result.stdout.splitlines():
                clean = line.rstrip()
                if clean:
                    self.wfile.write(f"event: log\ndata: {clean}\n\n".encode())
            self.wfile.flush()
        except (OSError, subprocess.TimeoutExpired): pass
        proc = subprocess.Popen(["tail","-f","-n","0",abs_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        try:
            while True:
                readable, _, _ = select.select([proc.stdout],[],[],1.0)
                if readable:
                    line = proc.stdout.readline()
                    if not line: break
                    clean = line.decode(errors="replace").rstrip()
                    if clean:
                        self.wfile.write(f"event: log\ndata: {clean}\n\n".encode())
                        self.wfile.flush()
                else:
                    self.wfile.write(b"event: ping\ndata: .\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError): pass
        finally:
            try: proc.terminate(); proc.wait(timeout=2)
            except: pass

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Access-Control-Allow-Methods","GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers","Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        if not self.check_auth():
            self.send_response(401)
            self.send_header("WWW-Authenticate",'Bearer realm="dash"')
            self.end_headers(); return
        parsed = urlparse(self.path)
        path, qs = parsed.path, parsed.query
        if path == "/":                        self.send_html(HTML)
        elif path == "/api/state":             self.send_json(build_state())
        elif path == "/api/stream":            self._serve_sse_state()
        elif path == "/api/logs/stream":       self._serve_sse_logs(qs)
        elif path.startswith("/api/logs/"):    self._serve_log(path[len("/api/logs/"):])
        else:                                  self.send_response(404); self.end_headers()

    def do_POST(self):
        if not self.check_auth():
            self.send_response(401); self.end_headers(); return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length",0))
        body = self.rfile.read(length) if length else b"{}"
        try: data = json.loads(body)
        except: data = {}

        if path == "/api/task/done":
            tid = data.get("id")
            if tid is None: return self.send_json({"ok":False,"error":"missing id"},400)
            store = HOME / "system/tasks.json"
            with _write_lock:
                try:
                    d = json.loads(store.read_text())
                    for t in d["tasks"]:
                        if t["id"] == int(tid): t["status"] = "done"
                    store.write_text(json.dumps(d, indent=2))
                    self.send_json({"ok":True})
                except Exception as e: self.send_json({"ok":False,"error":str(e)},500)

        elif path == "/api/task/add":
            desc = str(data.get("desc","")).strip()[:500]
            priority = data.get("priority","medium")
            if not desc: return self.send_json({"ok":False,"error":"empty desc"},400)
            if priority not in ("high","medium","low"): priority = "medium"
            store = HOME / "system/tasks.json"
            with _write_lock:
                try:
                    d = json.loads(store.read_text())
                    new_id = d.get("next_id",1)
                    d["tasks"].append({"id":new_id,"desc":desc,"priority":priority,"status":"open",
                                       "created":datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
                    d["next_id"] = new_id + 1
                    store.write_text(json.dumps(d, indent=2))
                    self.send_json({"ok":True,"id":new_id})
                except Exception as e: self.send_json({"ok":False,"error":str(e)},500)

        elif path == "/api/note":
            text = str(data.get("text","")).strip()
            if not text: return self.send_json({"ok":False,"error":"empty"},400)
            inbox = HOME / "inbox"; inbox.mkdir(exist_ok=True)
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H%M%S")
            (inbox / f"{ts}-dash.md").write_text(
                f"[{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}] (dashboard): {text}\n")
            self.send_json({"ok":True})

        elif path == "/api/trace/log":
            action = str(data.get("action","")).strip()[:300]
            outcome = data.get("outcome","")
            detail = str(data.get("detail","")).strip()[:500]
            if not action: return self.send_json({"ok":False,"error":"empty action"},400)
            if outcome not in ("success","fail"): return self.send_json({"ok":False,"error":"outcome must be success or fail"},400)
            entry = {"ts":datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                     "agent":"dashboard","action":action,"outcome":outcome,"detail":detail,"tags":[],"session":"dashboard"}
            trace_file = HOME / "system/trace.jsonl"
            with _write_lock:
                try:
                    with open(trace_file,"a") as f: f.write(json.dumps(entry)+"\n")
                    self.send_json({"ok":True})
                except Exception as e: self.send_json({"ok":False,"error":str(e)},500)

        elif path == "/api/sched/run":
            name = str(data.get("name","")).strip()
            if not re.match(r'^[a-zA-Z0-9_-]+$', name):
                return self.send_json({"ok":False,"error":"invalid job name"},400)
            try:
                d = json.loads((HOME / "system/sched.json").read_text())
                job = next((j for j in d.get("jobs",[]) if j["name"]==name), None)
                if not job: return self.send_json({"ok":False,"error":f"job '{name}' not found"},404)
                cmd = job.get("cmd","")
                subprocess.run(["bash","-c",cmd], timeout=30, capture_output=True)
                self.send_json({"ok":True})
            except subprocess.TimeoutExpired:
                self.send_json({"ok":True,"note":"started (timeout reached)"})
            except Exception as e: self.send_json({"ok":False,"error":str(e)},500)

        elif path == "/api/alert/clear":
            try:
                (HOME / "system/alert-cooldowns.json").write_text("{}")
                self.send_json({"ok":True})
            except Exception as e: self.send_json({"ok":False,"error":str(e)},500)

        else:
            self.send_response(404); self.end_headers()

    def _serve_log(self, app):
        apps_dir = HOME / "apps"
        candidates = list(apps_dir.glob(f"{app}/**/logs/*.log")) + list(apps_dir.glob(f"{app}/**/*.log"))
        if not candidates: return self.send_json({"lines":[],"error":f"no logs for {app}"})
        mf = max(candidates, key=lambda p: p.stat().st_mtime)
        try:
            lines = mf.read_text().strip().splitlines()[-100:]
            self.send_json({"file":str(mf),"lines":lines})
        except Exception as e: self.send_json({"error":str(e)})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), DashHandler)
    server.token = args.token
    print(f"dash listening on http://{args.bind}:{args.port}", flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__": main()
