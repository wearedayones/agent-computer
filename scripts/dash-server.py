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

def trace_data(limit=20):
    try:
        lines = (HOME / "system/trace.jsonl").read_text().strip().splitlines()
        return [json.loads(l) for l in lines if l.strip()][-limit:]
    except: return []

def _find_app_dirs(base, depth=3):
    """Recursively find dirs with a state/ subdir, skipping envs and hidden dirs."""
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
                           "icon":"✓" if ok else "✗","color":"#22c55e" if ok else "#ef4444"})
    except: pass
    inbox = HOME / "inbox"
    if inbox.exists():
        files = sorted([f for f in inbox.iterdir() if f.is_file() and "brief" not in f.name], reverse=True)
        for f in files[:5]:
            try:
                text = f.read_text().strip()
                first = text.splitlines()[0][:80] if text else ""
                ts = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                events.append({"type":"note","ts":ts,"text":first,"icon":"📧","color":"#eab308"})
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
                            events.append({"type":"alert","ts":ts_str+"Z","text":f"{app}: {line.strip()[:80]}",
                                           "icon":"⚠","color":"#ef4444"})
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
                    r = subprocess.run(chk, shell=True, capture_output=True, timeout=4)
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
    return {
        "ts":          datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "system":      {**version_info(), **disk_info(), "sessions": sessions_data()},
        "env":         env_data(),
        "tasks":       tasks_data(),
        "budget":      budget_data(),
        "trace":       trace_data(),
        "apps":        apps_data(),
        "activity":    activity_feed(),
        "log_sources": discover_logs(),
        "agents":      agents_data(),
        "inbox":       inbox_data(),
        "alerts":      alerts_data(),
        "cron":        cron_data(),
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
  --bg:#09090b;--surface:#111114;--surface2:#18181b;--border:#27272a;
  --text:#e4e4e7;--muted:#71717a;--faint:#3f3f46;
  --blue:#3b82f6;--green:#22c55e;--red:#ef4444;--yellow:#eab308;--purple:#a855f7;
  --blue-dim:#1d3557;--green-dim:#14532d;--red-dim:#450a0a;--yellow-dim:#422006;
  --r:10px;--r-sm:6px;
}
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:14px;line-height:1.5;min-height:100vh;padding-bottom:80px}
button{font-family:inherit;cursor:pointer;border:none;outline:none}
a{color:var(--blue);text-decoration:none}
a:hover{text-decoration:underline}

/* ── Header ── */
#hdr{
  position:sticky;top:0;z-index:100;
  background:rgba(9,9,11,.92);backdrop-filter:blur(12px);
  border-bottom:1px solid var(--border);
  padding:0 16px;height:54px;
  display:flex;align-items:center;justify-content:space-between;gap:12px;
}
#hdr-left{display:flex;align-items:center;gap:10px}
#hdr h1{font-size:15px;font-weight:700;color:var(--text);letter-spacing:-.3px}
#hdr-right{display:flex;align-items:center;gap:8px}
#ts{font-size:11px;color:var(--muted);white-space:nowrap}
#disk-badge{font-size:11px;font-weight:600;padding:3px 8px;border-radius:20px}
#live-label{display:flex;align-items:center;gap:5px;font-size:11px;font-weight:700;color:var(--red)}
.live-dot{width:7px;height:7px;border-radius:50%;background:var(--red);flex-shrink:0;animation:live-pulse 1.5s ease-in-out infinite}
@keyframes live-pulse{0%,100%{box-shadow:0 0 0 2px rgba(239,68,68,.3)}50%{box-shadow:0 0 0 6px rgba(239,68,68,.05)}}

/* ── Mission ── */
#mission-bar{
  background:linear-gradient(135deg,#1e1b4b,#162032);
  border-bottom:1px solid #3730a3;
  padding:10px 16px;font-size:13px;color:#a5b4fc;
  display:none;align-items:center;gap:8px;
}

/* ── Layout ── */
#main{padding:14px;display:flex;flex-direction:column;gap:12px;max-width:900px;margin:0 auto}

/* ── Cards ── */
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);overflow:hidden;animation:fadein .2s ease}
.card-hdr{padding:12px 14px 10px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border)}
.card-title{font-size:11px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}
.card-body{padding:12px 14px}
.card-body.no-pad{padding:0}

/* ── Stat grid ── */
.stat-grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border)}
.stat-cell{background:var(--surface);padding:12px 14px}
.stat-label{font-size:11px;color:var(--muted);margin-bottom:3px}
.stat-value{font-size:18px;font-weight:700;color:var(--text);line-height:1.2}

/* ── Disk arc ── */
.disk-wrap{display:flex;align-items:center;gap:14px;padding:12px 14px}
.disk-arc{position:relative;width:64px;height:64px;flex-shrink:0}
.disk-arc svg{transform:rotate(-90deg)}
.disk-arc-text{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700}
.disk-detail{flex:1;min-width:0}
.disk-bar-wrap{background:var(--faint);border-radius:4px;height:6px;margin:6px 0 4px;overflow:hidden}
.disk-bar{height:6px;border-radius:4px;transition:width .6s cubic-bezier(.4,0,.2,1)}
.sessions-row{display:flex;flex-wrap:wrap;gap:5px;margin-top:6px}
.session-chip{background:var(--surface2);border:1px solid var(--border);border-radius:4px;padding:2px 7px;font-size:11px;color:var(--muted)}

/* ── Activity feed ── */
.act-item{display:flex;align-items:flex-start;gap:10px;padding:9px 14px;border-bottom:1px solid var(--border);animation:fadein .25s ease}
.act-item:last-child{border:none}
.act-icon{width:22px;height:22px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:11px;margin-top:1px}
.act-body{flex:1;min-width:0}
.act-text{font-size:12px;color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.act-time{font-size:10px;color:var(--faint);margin-top:2px}

/* ── Log viewer ── */
#log-tabs{display:flex;flex-wrap:wrap;gap:2px;padding:6px 10px;border-bottom:1px solid var(--border);background:var(--surface2)}
.log-tab{background:transparent;border:none;border-bottom:2px solid transparent;color:var(--muted);padding:3px 8px;font-size:11px;cursor:pointer;font-family:inherit;transition:all .15s}
.log-tab:hover{color:var(--text)}
.log-tab.active{color:#4ade80;border-bottom-color:#4ade80}
#log-lines{background:#000;color:#4ade80;font-family:'SF Mono','Fira Code',ui-monospace,monospace;font-size:11px;line-height:1.6;padding:8px 10px;max-height:260px;overflow-y:auto;white-space:pre-wrap;word-break:break-all}
#log-empty{padding:20px;text-align:center;color:var(--muted);font-size:12px}

/* ── App cards (generic) ── */
.ch-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:1px;background:var(--border)}
.ch-card{background:var(--surface);padding:12px 14px}
.ch-name{font-size:12px;font-weight:600;color:var(--text);margin-bottom:8px;display:flex;align-items:center;gap:6px}
.ch-dot{width:6px;height:6px;border-radius:50%;flex-shrink:0}
.ch-progress{display:flex;align-items:center;gap:8px;margin-bottom:8px}
.ch-prog-bar{flex:1;background:var(--faint);border-radius:3px;height:5px;overflow:hidden}
.ch-prog-fill{height:5px;border-radius:3px;background:var(--blue);transition:width .5s}
.ch-prog-text{font-size:11px;color:var(--muted);white-space:nowrap;min-width:36px;text-align:right}
.ch-views{font-size:13px;font-weight:700;color:var(--text)}
.ch-top{font-size:10px;color:var(--muted);margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kv-row{display:flex;justify-content:space-between;font-size:11px;margin-top:3px;gap:8px}
.kv-k{color:var(--muted);flex-shrink:0}
.kv-v{color:var(--text);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-align:right}

/* ── Tasks ── */
.task-item{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid var(--border)}
.task-item:last-child{border:none}
.task-pri{font-size:10px;font-weight:700;padding:2px 7px;border-radius:20px;flex-shrink:0;text-transform:uppercase}
.pri-high{background:rgba(239,68,68,.15);color:#fca5a5}
.pri-medium{background:rgba(59,130,246,.15);color:#93c5fd}
.pri-low{background:var(--faint);color:var(--muted)}
.task-desc{flex:1;font-size:13px;color:var(--text);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.task-id{font-size:11px;color:var(--faint);flex-shrink:0}
.task-done-btn{flex-shrink:0;background:transparent;border:1px solid var(--faint);color:var(--muted);font-size:11px;padding:3px 8px;border-radius:5px;transition:all .15s}
.task-done-btn:hover{background:var(--green-dim);border-color:var(--green);color:var(--green)}
.task-empty{padding:14px;text-align:center;color:var(--muted);font-size:13px}

/* ── Budget ── */
.budget-total{display:flex;align-items:baseline;gap:6px;margin-bottom:10px}
.budget-amount{font-size:24px;font-weight:700;color:var(--text)}
.budget-limit{font-size:13px;color:var(--muted)}
.budget-month{font-size:11px;color:var(--muted);margin-left:auto}
.budget-item{margin-bottom:10px}
.budget-item:last-child{margin:0}
.budget-row{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:4px}
.budget-cat{font-size:12px;color:var(--text)}
.budget-val{font-size:12px;color:var(--muted)}
.bbar{background:var(--faint);border-radius:3px;height:5px;overflow:hidden}
.bbar-fill{height:5px;border-radius:3px;transition:width .6s cubic-bezier(.4,0,.2,1)}

/* ── Trace ── */
.trace-item{display:flex;align-items:flex-start;gap:10px;padding:10px 14px;border-bottom:1px solid var(--border)}
.trace-item:last-child{border:none}
.trace-icon{width:22px;height:22px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:11px;margin-top:1px}
.ti-success{background:var(--green-dim);color:var(--green)}
.ti-fail{background:var(--red-dim);color:var(--red)}
.trace-body{flex:1;min-width:0}
.trace-action{font-size:13px;color:var(--text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-detail{font-size:11px;color:var(--muted);margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-meta{display:flex;align-items:center;gap:6px;margin-top:4px;flex-wrap:wrap}
.trace-tag{font-size:10px;padding:1px 6px;border-radius:10px;background:var(--faint);color:var(--muted)}
.trace-ts{font-size:10px;color:var(--faint);margin-left:auto;flex-shrink:0}

/* ── Agents ── */
.agent-item{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid var(--border)}
.agent-item:last-child{border:none}
.agent-dot{width:9px;height:9px;border-radius:50%;flex-shrink:0}
.dot-green{background:var(--green);box-shadow:0 0 0 3px rgba(34,197,94,.15)}
.dot-red{background:var(--red);box-shadow:0 0 0 3px rgba(239,68,68,.15)}
.dot-grey{background:var(--faint)}
.agent-name{font-size:13px;font-weight:600;color:var(--text);flex:1}
.agent-status{font-size:11px}
.alive{color:var(--green)}.dead{color:var(--red)}.unknown{color:var(--muted)}

/* ── Inbox ── */
.inbox-item{padding:11px 14px;border-bottom:1px solid var(--border)}
.inbox-item:last-child{border:none}
.inbox-file{font-size:10px;color:var(--muted);margin-bottom:4px;font-family:'SF Mono',monospace}
.inbox-text{font-size:12px;color:var(--text);line-height:1.5;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}

/* ── Alerts ── */
.alert-item{display:flex;gap:8px;padding:9px 14px;border-bottom:1px solid var(--border)}
.alert-item:last-child{border:none}
.alert-app{font-size:11px;font-weight:600;color:var(--yellow);flex-shrink:0;min-width:80px}
.alert-line{font-size:11px;color:#fca5a5;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.no-alerts{padding:14px;text-align:center;font-size:13px;color:var(--green)}

/* ── Note form ── */
.note-form{display:flex;gap:8px;padding:10px 14px;border-top:1px solid var(--border)}
.note-input{flex:1;background:var(--surface2);border:1px solid var(--border);border-radius:var(--r-sm);padding:7px 10px;font-size:13px;color:var(--text);font-family:inherit;resize:none;outline:none;transition:border-color .15s}
.note-input:focus{border-color:var(--blue)}
.note-send{background:var(--blue);color:#fff;border-radius:var(--r-sm);padding:7px 14px;font-size:13px;font-weight:600;transition:opacity .15s;flex-shrink:0}
.note-send:hover{opacity:.85}

/* ── Remote control ── */
#rc-wrap{position:fixed;bottom:0;left:0;right:0;z-index:200;background:rgba(9,9,11,.96);border-top:1px solid var(--border);backdrop-filter:blur(12px)}
#rc-inner{max-width:900px;margin:0 auto;padding:8px 16px}
#rc-bar{display:flex;gap:6px;flex-wrap:wrap}
.rc-btn{background:var(--surface2);border:1px solid var(--border);color:var(--text);border-radius:var(--r-sm);padding:6px 12px;font-size:12px;font-weight:600;transition:all .15s;white-space:nowrap}
.rc-btn:hover{background:var(--faint);border-color:var(--muted)}
.rc-btn.active{background:var(--blue-dim);border-color:var(--blue);color:var(--blue)}
#rc-drawer{display:none;padding:10px 0 4px}
#rc-drawer input,#rc-drawer textarea,#rc-drawer select{display:block;width:100%;background:var(--surface2);border:1px solid var(--border);border-radius:var(--r-sm);padding:7px 10px;font-size:13px;color:var(--text);font-family:inherit;outline:none;margin-bottom:6px;transition:border-color .15s}
#rc-drawer input:focus,#rc-drawer textarea:focus,#rc-drawer select:focus{border-color:var(--blue)}
#rc-drawer textarea{resize:none}
#rc-drawer .rc-row{display:flex;gap:8px}
#rc-drawer .rc-row input,#rc-drawer .rc-row select{margin-bottom:0}
#rc-drawer .rc-submit{display:inline-block;background:var(--blue);color:#fff;border:none;border-radius:var(--r-sm);padding:7px 18px;font-size:13px;font-weight:600;cursor:pointer;margin-top:6px}
#rc-drawer .rc-submit:hover{opacity:.85}
#rc-feedback{font-size:13px;padding:6px 0}

/* ── Util ── */
.row-2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.empty{padding:14px;text-align:center;color:var(--muted);font-size:13px}
.badge{display:inline-flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;min-width:20px;height:20px;padding:0 5px;border-radius:10px;background:var(--blue-dim);color:var(--blue)}
.badge.green{background:var(--green-dim);color:var(--green)}
.badge.red{background:var(--red-dim);color:var(--red)}
.badge.yellow{background:var(--yellow-dim);color:var(--yellow)}
@keyframes fadein{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
@media(max-width:600px){.row-2{grid-template-columns:1fr}}
</style>
</head>
<body>

<div id="hdr">
  <div id="hdr-left">
    <div id="live-label"><div class="live-dot"></div>NOW LIVE</div>
    <h1>Agent Computer</h1>
  </div>
  <div id="hdr-right">
    <span id="ts">connecting…</span>
    <span id="disk-badge"></span>
  </div>
</div>

<div id="mission-bar">
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
  <span id="mission-text"></span>
</div>

<div id="main">

  <!-- Activity + Log Viewer row -->
  <div class="row-2">
    <div class="card">
      <div class="card-hdr">
        <span class="card-title">Activity</span>
        <span style="display:flex;align-items:center;gap:4px;font-size:10px;color:var(--muted)">trace · inbox · alerts</span>
      </div>
      <div id="act-list" class="card-body no-pad" style="max-height:280px;overflow-y:auto">
        <div class="empty">connecting…</div>
      </div>
    </div>
    <div class="card">
      <div class="card-hdr">
        <span class="card-title">Live Log</span>
        <span id="log-label" style="font-size:11px;color:var(--muted)">select a source</span>
      </div>
      <div id="log-tabs"><span style="font-size:11px;color:var(--muted);padding:6px 10px">loading sources…</span></div>
      <div id="log-lines"><div id="log-empty" style="padding:20px;text-align:center;color:var(--muted);font-size:12px">select a log tab above</div></div>
    </div>
  </div>

  <!-- Apps section (auto-discovered) -->
  <div class="card" id="apps-card" style="display:none">
    <div class="card-hdr">
      <span class="card-title">Apps</span>
      <span id="apps-badge" class="badge green"></span>
    </div>
    <div class="card-body no-pad"><div class="ch-grid" id="apps-grid"></div></div>
  </div>

  <!-- System pulse -->
  <div class="card" id="sys-card">
    <div class="card-hdr">
      <span class="card-title">System Pulse</span>
      <span id="sys-version" style="font-size:11px;color:var(--muted)"></span>
    </div>
    <div class="stat-grid" id="sys-stats"></div>
    <div class="disk-wrap" id="disk-section"></div>
  </div>

  <!-- Tasks + Agents -->
  <div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Tasks</span><span id="task-badge" class="badge">0</span></div>
      <div class="card-body no-pad" id="task-list"></div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Agents</span></div>
      <div class="card-body no-pad" id="agent-list"></div>
    </div>
  </div>

  <!-- Budget + Trace -->
  <div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Budget</span></div>
      <div class="card-body" id="budget-body"></div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Trace</span><span id="trace-count" style="font-size:11px;color:var(--muted)"></span></div>
      <div class="card-body no-pad" id="trace-list"></div>
    </div>
  </div>

  <!-- Inbox + Alerts -->
  <div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Inbox</span><span id="inbox-badge"></span></div>
      <div class="card-body no-pad" id="inbox-list"></div>
      <div class="note-form">
        <textarea class="note-input" id="note-input" rows="1" placeholder="Leave a note for next agent…"></textarea>
        <button class="note-send" onclick="sendNote()">Send</button>
      </div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Alerts</span><span id="alert-badge"></span></div>
      <div class="card-body no-pad" id="alert-list"></div>
    </div>
  </div>

  <!-- Scheduled jobs -->
  <div class="card" id="sched-card" style="display:none">
    <div class="card-hdr"><span class="card-title">Scheduled Jobs</span><span id="sched-badge" class="badge"></span></div>
    <div class="card-body no-pad" id="sched-list"></div>
  </div>

</div>

<!-- Remote Control (fixed bottom) -->
<div id="rc-wrap">
  <div id="rc-inner">
    <div id="rc-bar">
      <button class="rc-btn" onclick="toggleRC('add-task')" id="rcb-add-task">＋ Task</button>
      <button class="rc-btn" onclick="toggleRC('log-outcome')" id="rcb-log-outcome">✓ Log</button>
      <button class="rc-btn" onclick="toggleRC('run-job')" id="rcb-run-job">▶ Run Job</button>
      <button class="rc-btn" onclick="toggleRC('note')" id="rcb-note">✎ Note</button>
      <button class="rc-btn" onclick="clearAlerts()" id="rcb-alerts">✗ Clear Alerts</button>
    </div>
    <div id="rc-drawer"></div>
  </div>
</div>

<script>
const $ = id => document.getElementById(id)
const esc = s => String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
const fmt = n => Number(n||0).toLocaleString()

function timeAgo(ts) {
  if (!ts) return ''
  try {
    const s = Math.floor((Date.now() - new Date(ts).getTime()) / 1000)
    if (s < 60) return `${s}s ago`
    if (s < 3600) return `${Math.floor(s/60)}m ago`
    if (s < 86400) return `${Math.floor(s/3600)}h ago`
    return `${Math.floor(s/86400)}d ago`
  } catch { return '' }
}

function diskArc(pct, color) {
  const r=26,cx=32,cy=32,circ=2*Math.PI*r,dash=(pct/100)*circ
  return `<svg width="64" height="64" viewBox="0 0 64 64">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#27272a" stroke-width="8"/>
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="8"
      stroke-dasharray="${dash} ${circ}" stroke-linecap="round"/></svg>`
}
function barColor(p){return p>=90?'#ef4444':p>=70?'#eab308':'#3b82f6'}
function diskColor(p){return p>=90?'#ef4444':p>=75?'#eab308':'#22c55e'}

// ── Renderers ─────────────────────────────────────────────────────────────────

function render(s) {
  const sys=s.system||{}, env=s.env||{}
  window._lastSched = s.sched || []

  // Header
  const pct=sys.used_pct||0, dc=diskColor(pct)
  $('ts').textContent = 'live · '+(s.ts||'').slice(11,16)+' UTC'
  const db=$('disk-badge')
  db.textContent=(sys.free_gb||'?')+' GB free'
  db.style.cssText=`background:${dc}22;color:${dc};padding:3px 8px;border-radius:20px;font-size:11px;font-weight:700`

  // Mission
  if (env.mission) {
    $('mission-bar').style.display='flex'
    $('mission-text').textContent=env.mission
  }

  // System pulse
  $('sys-version').textContent='v'+(sys.version||'?')
  $('sys-stats').innerHTML=`
    <div class="stat-cell"><div class="stat-label">Host</div><div class="stat-value" style="font-size:13px;font-family:monospace">${esc(sys.hostname||'?')}</div></div>
    <div class="stat-cell"><div class="stat-label">Cron Jobs</div><div class="stat-value">${esc((s.cron||[]).length)}</div></div>`
  const sessions=(sys.sessions||[]).map(s=>`<span class="session-chip">● ${esc(s)}</span>`).join('')
  const color=diskColor(pct), arc=diskArc(pct,color)
  $('disk-section').innerHTML=`
    <div class="disk-arc">${arc}<div class="disk-arc-text" style="color:${color}">${pct}%</div></div>
    <div class="disk-detail">
      <div style="font-size:13px;font-weight:600;color:${color}">${sys.free_gb} GB free</div>
      <div style="font-size:11px;color:var(--muted)">of ${sys.total_gb} GB total</div>
      <div class="disk-bar-wrap"><div class="disk-bar" style="width:${pct}%;background:${color}"></div></div>
      <div class="sessions-row">${sessions||'<span style="font-size:11px;color:var(--muted)">no sessions</span>'}</div>
    </div>`

  // Apps (generic)
  renderApps(s.apps||[])

  // Activity feed
  renderActivity(s.activity||[])

  // Log tabs (dynamic)
  populateLogTabs(s.log_sources||[])

  // Tasks
  const tasks=s.tasks||[], open=tasks.filter(t=>t.status==='open')
  $('task-badge').textContent=open.length
  $('task-badge').className='badge'+(open.length?'':' green')
  $('task-list').innerHTML=open.length?open.map(t=>{
    const pc={high:'pri-high',medium:'pri-medium',low:'pri-low'}[t.priority||'medium']||'pri-medium'
    return `<div class="task-item">
      <span class="task-pri ${pc}">${esc(t.priority||'med')}</span>
      <span class="task-desc" title="${esc(t.desc)}">${esc(t.desc)}</span>
      <span class="task-id">#${t.id}</span>
      <button class="task-done-btn" onclick="markDone(${t.id},this)">done</button>
    </div>`
  }).join(''):`<div class="task-empty">✓ No open tasks</div>`

  // Agents
  const agents=s.agents||{}
  $('agent-list').innerHTML=Object.keys(agents).length?Object.entries(agents).map(([name,info])=>{
    const a=info.alive, dc2=a===true?'dot-green':a===false?'dot-red':'dot-grey'
    const sc=a===true?'alive':a===false?'dead':'unknown'
    const sl=a===true?'alive':a===false?'unreachable':'no check'
    return `<div class="agent-item"><div class="agent-dot ${dc2}"></div><div class="agent-name">${esc(name)}</div><div class="agent-status ${sc}">${sl}</div></div>`
  }).join(''):`<div class="empty">no agents registered</div>`

  // Budget
  const budget=s.budget||{}, bycat=budget.by_category||{}, thresh=budget.thresholds||{}
  const total=budget.total||0, tt=parseFloat(thresh.total||0), tp=tt?Math.min(100,total/tt*100):0
  let bh=`<div class="budget-total">
    <span class="budget-amount">$${total.toFixed(4)}</span>
    ${tt?`<span class="budget-limit">/ $${tt.toFixed(2)}</span>`:''}
    <span class="budget-month">${esc(budget.month||'')}</span></div>`
  if(tt) bh+=`<div class="bbar" style="margin-bottom:12px"><div class="bbar-fill" style="width:${tp.toFixed(1)}%;background:${barColor(tp)}"></div></div>`
  for(const[cat,val]of Object.entries(bycat)){
    const ct=parseFloat(thresh[cat]||0),cp=ct?Math.min(100,val/ct*100):0
    bh+=`<div class="budget-item"><div class="budget-row"><span class="budget-cat">${esc(cat)}</span><span class="budget-val">$${val.toFixed(4)}${ct?' / $'+ct.toFixed(2):''}</span></div>${ct?`<div class="bbar"><div class="bbar-fill" style="width:${cp.toFixed(1)}%;background:${barColor(cp)}"></div></div>`:''}</div>`
  }
  if(!Object.keys(bycat).length) bh+=`<div style="color:var(--muted);font-size:13px">no spend logged this month</div>`
  $('budget-body').innerHTML=bh

  // Trace
  const trace=s.trace||[], recent=[...trace].reverse().slice(0,12)
  $('trace-count').textContent=recent.length+' outcomes'
  $('trace-list').innerHTML=recent.length?recent.map(e=>{
    const ok=e.outcome==='success', tags=(e.tags||[]).map(t=>`<span class="trace-tag">${esc(t)}</span>`).join('')
    return `<div class="trace-item">
      <div class="trace-icon ${ok?'ti-success':'ti-fail'}">${ok?'✓':'✗'}</div>
      <div class="trace-body">
        <div class="trace-action" title="${esc(e.action)}">${esc(e.action)}</div>
        ${e.detail?`<div class="trace-detail">${esc(e.detail)}</div>`:''}
        <div class="trace-meta">${tags}<span class="trace-ts">${(e.ts||'').slice(5,10)}</span></div>
      </div></div>`
  }).join(''):`<div class="empty">no outcomes logged yet</div>`

  // Inbox
  const inbox=s.inbox||[]
  const ib=$('inbox-badge')
  ib.textContent=inbox.length||''
  ib.className='badge yellow'+(inbox.length?'':' green')
  $('inbox-list').innerHTML=inbox.length?inbox.map(n=>`<div class="inbox-item">
    <div class="inbox-file">${esc(n.file)}</div>
    <div class="inbox-text">${esc(n.text)}</div>
  </div>`).join(''):`<div class="empty">inbox empty</div>`

  // Alerts
  const alerts=s.alerts||[]
  const ab=$('alert-badge')
  ab.textContent=alerts.length||''
  ab.className=alerts.length?'badge red':'badge green'
  $('alert-list').innerHTML=alerts.length?alerts.map(a=>
    `<div class="alert-item"><span class="alert-app">${esc(a.app)}</span><span class="alert-line">${esc(a.line)}</span></div>`
  ).join(''):`<div class="no-alerts">✓ No errors in last 24h</div>`

  // Sched
  const sched=s.sched||[]
  if(sched.length){
    $('sched-card').style.display=''
    $('sched-badge').textContent=sched.length
    $('sched-list').innerHTML=sched.map(j=>{
      const paused=j.paused, lr=j.last_run?j.last_run.slice(0,10):'never'
      const le=j.last_exit!==null?(j.last_exit===0?'<span style="color:var(--green)">✓</span>':'<span style="color:var(--red)">✗</span>'):''
      return `<div class="task-item">
        <span class="task-pri ${paused?'pri-low':'pri-medium'}">${paused?'paused':esc(j.schedule_human||j.cron||'?')}</span>
        <span class="task-desc">${esc(j.name)}</span>
        <span class="task-id">${lr} ${le}</span>
      </div>`
    }).join('')
  } else $('sched-card').style.display='none'
}

function renderApps(apps) {
  const SKIP=new Set(['done_today','expected_today','errors_today','healthy','checked','live_processes','alerts','fixes'])
  if(!apps.length){$('apps-card').style.display='none';return}
  $('apps-card').style.display=''
  $('apps-badge').textContent=apps.length
  $('apps-grid').innerHTML=apps.map(app=>{
    const st=app.status||{}, healthy=st.healthy
    const hc=healthy===true?'var(--green)':healthy===false?'var(--red)':'var(--muted)'
    const hasP=st.done_today!==undefined&&st.expected_today!==undefined
    const done=st.done_today||0, exp=st.expected_today||0, prog=exp?Math.round(done/exp*100):0
    const errors=st.errors_today||0
    const kv=Object.entries(st).filter(([k])=>!SKIP.has(k)).slice(0,3)
      .map(([k,v])=>`<div class="kv-row"><span class="kv-k">${esc(k)}</span><span class="kv-v">${esc(typeof v==='object'?JSON.stringify(v).slice(0,40):String(v).slice(0,50))}</span></div>`).join('')
    const views7d=app.views_7d
    const topVideo=app.top_video
    return `<div class="ch-card">
      <div class="ch-name">
        <div class="ch-dot" style="background:${hc}"></div>
        ${esc(app.name)}
        ${errors>0?`<span class="badge red">${errors} err`+`</span>`:''}
      </div>
      ${hasP?`<div class="ch-progress"><div class="ch-prog-bar"><div class="ch-prog-fill" style="width:${prog}%;background:${hc}"></div></div><div class="ch-prog-text">${done}/${exp}</div></div>`:''}
      ${views7d?`<div class="ch-views">${fmt(views7d)}<span style="font-size:11px;color:var(--muted);font-weight:400"> views 7d</span></div>`:''}
      ${topVideo?`<div class="ch-top">"${esc(topVideo)}" · ${fmt(app.top_views||0)} views</div>`:''}
      ${kv}
    </div>`
  }).join('')
}

function renderActivity(events) {
  $('act-list').innerHTML=events.length?events.map(e=>`<div class="act-item">
    <div class="act-icon" style="background:${e.color}22;color:${e.color}">${esc(e.icon)}</div>
    <div class="act-body">
      <div class="act-text" title="${esc(e.text)}">${esc(e.text)}</div>
      <div class="act-time">${esc(e.type)} · ${timeAgo(e.ts)}</div>
    </div>
  </div>`).join(''):`<div class="empty">no activity yet</div>`
}

// ── Log viewer ────────────────────────────────────────────────────────────────
let logEs=null, lastLogSources='', activeLogPath=''

function populateLogTabs(sources) {
  const key=JSON.stringify(sources.map(s=>s.path))
  if(key===lastLogSources) return
  lastLogSources=key
  const tabs=$('log-tabs')
  if(!sources.length){tabs.innerHTML='<span style="font-size:11px;color:var(--muted);padding:6px 10px">no log files found</span>';return}
  tabs.innerHTML=sources.map((s,i)=>
    `<button class="log-tab${i===0?' active':''}" data-path="${esc(s.path)}" data-label="${esc(s.label)}" onclick="switchLog(this)">${esc(s.label)}</button>`
  ).join('')
  // Auto-connect to first log on first load
  if(!activeLogPath && sources.length) {
    switchLog(tabs.querySelector('.log-tab'))
  }
}

function switchLog(btn) {
  if(!btn) return
  document.querySelectorAll('.log-tab').forEach(b=>b.classList.remove('active'))
  btn.classList.add('active')
  const path=btn.dataset.path, label=btn.dataset.label
  if(!path || path===activeLogPath) return
  activeLogPath=path
  $('log-label').textContent=label||''
  if(logEs){logEs.close();logEs=null}
  const box=$('log-lines'); box.innerHTML=''
  logEs=new EventSource('/api/logs/stream?path='+encodeURIComponent(path))
  logEs.addEventListener('log',e=>{
    const d=document.createElement('div')
    d.textContent=e.data
    box.appendChild(d)
    while(box.children.length>200) box.removeChild(box.firstChild)
    box.scrollTop=box.scrollHeight
  })
  logEs.addEventListener('error',()=>{/* EventSource reconnects automatically */})
}

// ── SSE state stream ──────────────────────────────────────────────────────────
let stateEs=null
function connectSSE() {
  if(stateEs) stateEs.close()
  stateEs=new EventSource('/api/stream')
  stateEs.addEventListener('state',e=>{
    try{render(JSON.parse(e.data))}catch(err){console.warn('render error',err)}
  })
  stateEs.onerror=()=>{ $('ts').textContent='reconnecting…' }
}
connectSSE()

// ── Task actions ──────────────────────────────────────────────────────────────
async function markDone(id,btn){
  btn.textContent='…';btn.disabled=true
  try{
    const r=await fetch('/api/task/done',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})})
    if(r.ok){btn.textContent='✓';btn.style.color='var(--green)'}
    else{btn.textContent='err';btn.disabled=false}
  }catch{btn.textContent='err';btn.disabled=false}
}

async function sendNote(){
  const inp=$('note-input'),text=inp.value.trim()
  if(!text) return
  inp.disabled=true
  try{
    await fetch('/api/note',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})})
    inp.value=''
  }finally{inp.disabled=false}
}

// ── Remote control ─────────────────────────────────────────────────────────────
let _rcOpen=null

const RC={
  'add-task':{
    label:'＋ Task',
    html:()=>`
      <input id="rc-desc" placeholder="Task description" maxlength="500" autocomplete="off">
      <div class="rc-row">
        <select id="rc-pri"><option value="medium">Medium priority</option><option value="high">High priority</option><option value="low">Low priority</option></select>
        <button class="rc-submit" onclick="rcPost('task/add',{desc:$('rc-desc').value,priority:$('rc-pri').value})">Add Task</button>
      </div>`
  },
  'log-outcome':{
    label:'✓ Log',
    html:()=>`
      <input id="rc-action" placeholder="What did you do?" maxlength="300" autocomplete="off">
      <div class="rc-row">
        <select id="rc-outcome"><option value="success">Success</option><option value="fail">Fail</option></select>
        <input id="rc-detail" placeholder="Detail (optional)" maxlength="500" style="flex:2">
        <button class="rc-submit" onclick="rcPost('trace/log',{action:$('rc-action').value,outcome:$('rc-outcome').value,detail:$('rc-detail').value})">Log</button>
      </div>`
  },
  'run-job':{
    label:'▶ Run Job',
    html:()=>{
      const opts=(window._lastSched||[]).map(j=>`<option value="${esc(j.name)}">${esc(j.name)} — ${esc(j.schedule_human||j.cron||'')}</option>`).join('')
      return opts?`<div class="rc-row"><select id="rc-job">${opts}</select><button class="rc-submit" onclick="rcPost('sched/run',{name:$('rc-job').value})">Run Now</button></div>`
             :`<div style="color:var(--muted);font-size:13px;padding:4px 0">No scheduled jobs found</div>`
    }
  },
  'note':{
    label:'✎ Note',
    html:()=>`
      <textarea id="rc-note" placeholder="Leave a note for the next agent…" rows="2" maxlength="2000"></textarea>
      <button class="rc-submit" onclick="rcPost('note',{text:$('rc-note').value})">Send Note</button>`
  }
}

function toggleRC(name) {
  const drawer=$('rc-drawer')
  document.querySelectorAll('.rc-btn[id^="rcb-"]').forEach(b=>b.classList.remove('active'))
  if(_rcOpen===name){
    _rcOpen=null;drawer.style.display='none';drawer.innerHTML='';return
  }
  _rcOpen=name
  const form=RC[name]
  if(!form) return
  drawer.innerHTML=form.html()+'<div id="rc-feedback"></div>'
  drawer.style.display='block'
  const btn=document.getElementById('rcb-'+name)
  if(btn) btn.classList.add('active')
  const inp=drawer.querySelector('input,textarea,select')
  if(inp) setTimeout(()=>inp.focus(),50)
}

async function rcPost(endpoint,payload){
  const fb=$('rc-feedback')
  if(fb) fb.innerHTML=''
  try{
    const r=await fetch('/api/'+endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)})
    const result=await r.json()
    if(result.ok){
      if(fb) fb.innerHTML=`<span style="color:var(--green)">✓ Done</span>`
      setTimeout(()=>{toggleRC(_rcOpen)},1200)
    } else {
      if(fb) fb.innerHTML=`<span style="color:var(--red)">✗ ${esc(result.error||'error')}</span>`
    }
  }catch(e){
    if(fb) fb.innerHTML=`<span style="color:var(--red)">✗ network error</span>`
  }
}

async function clearAlerts(){
  const btn=$('rcb-alerts')
  if(btn){btn.textContent='…';btn.disabled=true}
  try{
    const r=await fetch('/api/alert/clear',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})
    const result=await r.json()
    if(btn){btn.textContent=result.ok?'✓ Cleared':'✗ Error';btn.style.color=result.ok?'var(--green)':'var(--red)';btn.disabled=false}
    setTimeout(()=>{if(btn){btn.textContent='✗ Clear Alerts';btn.style.color=''}},2000)
  }catch{if(btn){btn.textContent='✗ Error';btn.disabled=false}}
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
                for _ in range(6):
                    time.sleep(0.5)
                    try:
                        sz = TRACE.stat().st_size
                        if sz != last_sz: last_sz = sz; break
                    except OSError: pass
        except (BrokenPipeError, ConnectionResetError, OSError): pass

    def _serve_sse_logs(self, query_string):
        params = parse_qs(query_string)
        raw = unquote(params.get("path",[""])[0])
        # Validate: must be within HOME and end in .log
        try: abs_path = str(Path(raw).resolve())
        except: abs_path = ""
        home_str = str(HOME)
        if not abs_path or not abs_path.startswith(home_str) or not abs_path.endswith(".log"):
            self._sse_headers()
            self.wfile.write(b"event: error\ndata: forbidden\n\n")
            self.wfile.flush(); return
        # Must be in discovered log list
        allowed = {d["path"] for d in discover_logs()}
        if abs_path not in allowed:
            self._sse_headers()
            self.wfile.write(b"event: error\ndata: forbidden\n\n")
            self.wfile.flush(); return
        self._sse_headers()
        # Send last 30 lines as preamble
        try:
            result = subprocess.run(["tail","-n","30",abs_path], capture_output=True, text=True, timeout=5)
            for line in result.stdout.splitlines():
                clean = line.rstrip()
                if clean:
                    self.wfile.write(f"event: log\ndata: {clean}\n\n".encode())
            self.wfile.flush()
        except (OSError, subprocess.TimeoutExpired): pass
        # Follow with tail -f
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
