#!/usr/bin/env python3
"""dash-server.py — Agent Computer v4 dashboard (upgraded UI)"""
import argparse, json, os, subprocess
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

HOME = Path.home()

# ── Data collectors ──────────────────────────────────────────────────────────

def disk_info():
    try:
        st = os.statvfs(HOME)
        free_gb  = round(st.f_bavail * st.f_frsize / 1e9, 1)
        total_gb = round(st.f_blocks * st.f_frsize / 1e9, 1)
        used_pct = int(100 * (1 - st.f_bavail / st.f_blocks))
        return {"free_gb": free_gb, "total_gb": total_gb, "used_pct": used_pct}
    except:
        return {}

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
    except:
        return []

def tasks_data():
    try:
        return json.loads((HOME / "system/tasks.json").read_text()).get("tasks", [])
    except:
        return []

def budget_data():
    try:
        d = json.loads((HOME / "system/budget.json").read_text())
    except:
        return {"entries": [], "thresholds": {}}
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    entries = [e for e in d.get("entries", []) if e.get("month") == month]
    thresholds = d.get("thresholds", {})
    by_cat = {}
    for e in entries:
        cat = e.get("category", "uncategorized")
        by_cat[cat] = round(by_cat.get(cat, 0) + e.get("amount", 0), 4)
    return {
        "month": month,
        "total": round(sum(by_cat.values()), 4),
        "by_category": by_cat,
        "thresholds": thresholds,
    }

def trace_data(limit=20):
    try:
        lines = (HOME / "system/trace.jsonl").read_text().strip().splitlines()
        return [json.loads(l) for l in lines if l.strip()][-limit:]
    except:
        return []

def channels_data():
    """Per-channel status: done_today, expected_today, 7d views, top video."""
    apps_dir = HOME / "apps"
    cutoff7 = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d")
    channels = {}
    sf = apps_dir / "social-factory" / "channels"
    if not sf.exists():
        return {}
    for ch in sorted(sf.iterdir()):
        if not ch.is_dir():
            continue
        info = {"name": ch.name, "done_today": 0, "expected_today": 0,
                "views_7d": 0, "errors_today": 0, "healthy": True,
                "top_video": None, "top_views": 0}
        # status.json
        status_f = ch / "state" / "status.json"
        if status_f.exists():
            try:
                s = json.loads(status_f.read_text())
                info["done_today"]     = s.get("done_today", 0)
                info["expected_today"] = s.get("expected_today", 0)
                info["errors_today"]   = s.get("errors_today", 0)
                info["healthy"]        = s.get("healthy", True)
            except: pass
        # metrics.jsonl for 7d views + top video
        mf = ch / "state" / "metrics.jsonl"
        if mf.exists():
            try:
                entries = [json.loads(l) for l in mf.read_text().splitlines() if l.strip()]
                recent = [e for e in entries if e.get("date", "") >= cutoff7]
                for e in recent:
                    for v in e.get("videos", []):
                        vw = v.get("views", 0) or 0
                        info["views_7d"] += vw
                        if vw > info["top_views"]:
                            info["top_views"] = vw
                            info["top_video"] = v.get("title", "")
            except: pass
        channels[ch.name] = info
    return dict(sorted(channels.items(), key=lambda x: -x[1]["views_7d"]))

def metrics_data():
    """Non-social-factory app metrics."""
    apps_dir = HOME / "apps"
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d")
    result = {}
    if not apps_dir.exists():
        return result
    for app in sorted(apps_dir.iterdir()):
        if not app.is_dir() or app.name in ("envs", "social-factory"):
            continue
        for mf in app.rglob("metrics.jsonl"):
            parent = mf.parent.parent
            label = f"{app.name}/{parent.name}" if parent.name != app.name else app.name
            try:
                entries = [json.loads(l) for l in mf.read_text().splitlines() if l.strip()]
                recent = [e for e in entries if e.get("date", "") >= cutoff]
                views = sum(e.get("views", 0) or 0 for e in recent)
                if recent:
                    result[label] = {"views_7d": views, "days": len(recent)}
            except: pass
    return dict(sorted(result.items(), key=lambda x: -x[1]["views_7d"]))

def agents_data():
    try:
        d = json.loads((HOME / "system/agents.json").read_text())
        agents = d.get("agents", {})
        result = {}
        for name, info in agents.items():
            chk = info.get("check", "")
            alive = None
            if chk:
                try:
                    r = subprocess.run(chk, shell=True, capture_output=True, timeout=4)
                    alive = r.returncode == 0
                except: alive = False
            result[name] = {"alive": alive, "url": info.get("url", ""), "check": chk}
        return result
    except:
        return {}

def inbox_data():
    inbox = HOME / "inbox"
    notes = []
    if inbox.exists():
        files = sorted([f for f in inbox.iterdir()
                        if f.is_file() and "brief" not in f.name], reverse=True)
        for f in files[:6]:
            try:
                text = f.read_text().strip()
                # Extract first timestamp line if JSONL-style
                first = text.splitlines()[0] if text else ""
                notes.append({"file": f.name, "text": first[:200], "full": text[:500]})
            except: pass
    return notes

def alerts_data():
    apps_dir = HOME / "apps"
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).strftime("%Y-%m-%dT%H:%M")
    alerts = []
    if not apps_dir.exists():
        return []
    for alert_log in apps_dir.rglob("alerts.log"):
        app = alert_log.relative_to(apps_dir).parts[0]
        try:
            lines = alert_log.read_text().strip().splitlines()[-100:]
            for line in lines:
                if any(w in line.upper() for w in ("ERROR", "FAIL", "CRITICAL")):
                    ts = line[:16] if len(line) >= 16 else ""
                    if ts >= cutoff[:16]:
                        alerts.append({"app": app, "line": line.strip()[:160]})
        except: pass
    return alerts[-20:]

def env_data():
    try:
        return json.loads((HOME / "system/env.json").read_text())
    except:
        return {}

def cron_data():
    try:
        out = subprocess.check_output(["crontab", "-l"], text=True, stderr=subprocess.DEVNULL)
        return [l.strip() for l in out.splitlines() if l.strip() and not l.startswith("#")]
    except:
        return []

def sched_data():
    try:
        d = json.loads((HOME / "system/sched.json").read_text())
        return d.get("jobs", [])
    except:
        return []

def build_state():
    return {
        "ts":       datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "system":   {**version_info(), **disk_info(), "sessions": sessions_data()},
        "env":      env_data(),
        "tasks":    tasks_data(),
        "budget":   budget_data(),
        "trace":    trace_data(),
        "channels": channels_data(),
        "metrics":  metrics_data(),
        "agents":   agents_data(),
        "inbox":    inbox_data(),
        "alerts":   alerts_data(),
        "cron":     cron_data(),
        "sched":    sched_data(),
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
body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:14px;line-height:1.5;min-height:100vh}
button{font-family:inherit;cursor:pointer;border:none;outline:none}

/* ── Header ── */
#hdr{
  position:sticky;top:0;z-index:100;
  background:rgba(9,9,11,.92);backdrop-filter:blur(12px);
  border-bottom:1px solid var(--border);
  padding:0 16px;height:54px;
  display:flex;align-items:center;justify-content:space-between;
  gap:12px;
}
#hdr-left{display:flex;align-items:center;gap:10px}
#hdr h1{font-size:15px;font-weight:700;color:var(--text);letter-spacing:-.3px}
#hdr-right{display:flex;align-items:center;gap:8px}
#ts{font-size:11px;color:var(--muted);white-space:nowrap}
#disk-badge{font-size:11px;font-weight:600;padding:3px 8px;border-radius:20px}
.pulse-dot{width:8px;height:8px;border-radius:50%;background:var(--green);
  box-shadow:0 0 0 2px rgba(34,197,94,.25);flex-shrink:0;
  animation:pulse 2.5s ease-in-out infinite}
@keyframes pulse{0%,100%{box-shadow:0 0 0 2px rgba(34,197,94,.25)}
  50%{box-shadow:0 0 0 5px rgba(34,197,94,.08)}}

/* ── Mission banner ── */
#mission-bar{
  background:linear-gradient(135deg,#1e1b4b,#162032);
  border-bottom:1px solid #3730a3;
  padding:10px 16px;font-size:13px;color:#a5b4fc;
  display:none;align-items:center;gap:8px;
}

/* ── Layout ── */
#main{padding:14px;display:flex;flex-direction:column;gap:12px;max-width:900px;margin:0 auto}

/* ── Cards ── */
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);overflow:hidden}
.card-hdr{
  padding:12px 14px 10px;
  display:flex;align-items:center;justify-content:space-between;
  border-bottom:1px solid var(--border);
}
.card-title{font-size:11px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}
.card-body{padding:12px 14px}
.card-body.no-pad{padding:0}

/* ── Stat grid (system pulse) ── */
.stat-grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--border)}
.stat-cell{background:var(--surface);padding:12px 14px}
.stat-label{font-size:11px;color:var(--muted);margin-bottom:3px}
.stat-value{font-size:18px;font-weight:700;color:var(--text);line-height:1.2}
.stat-sub{font-size:11px;color:var(--muted);margin-top:2px}

/* ── Disk arc ── */
.disk-wrap{display:flex;align-items:center;gap:14px;padding:12px 14px}
.disk-arc{position:relative;width:64px;height:64px;flex-shrink:0}
.disk-arc svg{transform:rotate(-90deg)}
.disk-arc-text{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700}
.disk-detail{flex:1;min-width:0}
.disk-bar-wrap{background:var(--faint);border-radius:4px;height:6px;margin:6px 0 4px;overflow:hidden}
.disk-bar{height:6px;border-radius:4px;transition:width .6s cubic-bezier(.4,0,.2,1)}
.sessions-row{display:flex;flex-wrap:wrap;gap:5px;margin-top:6px}
.session-chip{background:var(--surface2);border:1px solid var(--border);border-radius:4px;
  padding:2px 7px;font-size:11px;color:var(--muted)}

/* ── Channel cards ── */
.ch-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:1px;background:var(--border)}
.ch-card{background:var(--surface);padding:12px 14px}
.ch-name{font-size:12px;font-weight:600;color:var(--text);margin-bottom:8px;display:flex;align-items:center;gap:6px}
.ch-dot{width:6px;height:6px;border-radius:50%;flex-shrink:0}
.ch-progress{display:flex;align-items:center;gap:8px;margin-bottom:8px}
.ch-prog-bar{flex:1;background:var(--faint);border-radius:3px;height:5px;overflow:hidden}
.ch-prog-fill{height:5px;border-radius:3px;background:var(--blue);transition:width .5s}
.ch-prog-text{font-size:11px;color:var(--muted);white-space:nowrap;min-width:36px;text-align:right}
.ch-views{font-size:13px;font-weight:700;color:var(--text)}
.ch-top{font-size:10px;color:var(--muted);margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

/* ── Tasks ── */
.task-item{
  display:flex;align-items:center;gap:10px;
  padding:10px 14px;border-bottom:1px solid var(--border);
}
.task-item:last-child{border:none}
.task-pri{font-size:10px;font-weight:700;padding:2px 7px;border-radius:20px;flex-shrink:0;text-transform:uppercase}
.pri-high{background:rgba(239,68,68,.15);color:#fca5a5}
.pri-medium{background:rgba(59,130,246,.15);color:#93c5fd}
.pri-low{background:var(--faint);color:var(--muted)}
.task-desc{flex:1;font-size:13px;color:var(--text);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.task-id{font-size:11px;color:var(--faint);flex-shrink:0}
.task-done-btn{
  flex-shrink:0;background:transparent;border:1px solid var(--faint);
  color:var(--muted);font-size:11px;padding:3px 8px;border-radius:5px;
  transition:all .15s;
}
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
.trace-item{
  display:flex;align-items:flex-start;gap:10px;
  padding:10px 14px;border-bottom:1px solid var(--border);
}
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
.agent-item{
  display:flex;align-items:center;gap:10px;
  padding:10px 14px;border-bottom:1px solid var(--border);
}
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
.inbox-expand{font-size:11px;color:var(--blue);margin-top:4px;cursor:pointer;display:inline-block}

/* ── Alerts ── */
.alert-item{display:flex;gap:8px;padding:9px 14px;border-bottom:1px solid var(--border)}
.alert-item:last-child{border:none}
.alert-app{font-size:11px;font-weight:600;color:var(--yellow);flex-shrink:0;min-width:80px}
.alert-line{font-size:11px;color:#fca5a5;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.no-alerts{padding:14px;text-align:center;font-size:13px;color:var(--green)}

/* ── Section rows (2-col on wide) ── */
.row-2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
@media(max-width:560px){.row-2{grid-template-columns:1fr}.stat-grid{grid-template-columns:1fr 1fr}}

/* ── Note form ── */
.note-form{display:flex;gap:8px;padding:10px 14px;border-top:1px solid var(--border)}
.note-input{
  flex:1;background:var(--surface2);border:1px solid var(--border);
  border-radius:var(--r-sm);padding:7px 10px;font-size:13px;color:var(--text);
  font-family:inherit;resize:none;outline:none;
  transition:border-color .15s;
}
.note-input:focus{border-color:var(--blue)}
.note-send{
  background:var(--blue);color:#fff;border-radius:var(--r-sm);
  padding:7px 14px;font-size:13px;font-weight:600;
  transition:opacity .15s;flex-shrink:0;
}
.note-send:hover{opacity:.85}

/* ── Empty / util ── */
.empty{padding:14px;text-align:center;color:var(--muted);font-size:13px}
.badge{display:inline-flex;align-items:center;justify-content:center;
  font-size:11px;font-weight:700;min-width:20px;height:20px;padding:0 5px;
  border-radius:10px;background:var(--blue-dim);color:var(--blue)}
.badge.green{background:var(--green-dim);color:var(--green)}
.badge.red{background:var(--red-dim);color:var(--red)}
.badge.yellow{background:var(--yellow-dim);color:var(--yellow)}

/* ── Refresh indicator ── */
#refresh-bar{height:2px;background:var(--blue);width:100%;position:fixed;bottom:0;left:0;transform-origin:left;animation:refill 10s linear infinite;opacity:.5}
@keyframes refill{0%{transform:scaleX(1)}100%{transform:scaleX(0)}}

/* ── Fade-in ── */
.card{animation:fadein .2s ease}
@keyframes fadein{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
</style>
</head>
<body>

<div id="hdr">
  <div id="hdr-left">
    <div class="pulse-dot"></div>
    <h1>Agent Computer</h1>
  </div>
  <div id="hdr-right">
    <span id="ts">loading…</span>
    <span id="disk-badge"></span>
  </div>
</div>

<div id="mission-bar" id="mb">
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
  <span id="mission-text"></span>
</div>

<div id="main"></div>
<div id="refresh-bar"></div>

<script>
const $ = id => document.getElementById(id)
const esc = s => String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
const fmt = n => Number(n).toLocaleString()

// ── Disk arc SVG ─────────────────────────────────────────────────────────────
function diskArc(pct, color) {
  const r = 26, cx = 32, cy = 32, circ = 2 * Math.PI * r
  const dash = (pct / 100) * circ
  return `<svg width="64" height="64" viewBox="0 0 64 64">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#27272a" stroke-width="8"/>
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="8"
      stroke-dasharray="${dash} ${circ}" stroke-linecap="round"/>
  </svg>`
}

// ── Bar helpers ───────────────────────────────────────────────────────────────
function barColor(pct) {
  if (pct >= 90) return '#ef4444'
  if (pct >= 70) return '#eab308'
  return '#3b82f6'
}
function diskColor(pct) {
  if (pct >= 90) return '#ef4444'
  if (pct >= 75) return '#eab308'
  return '#22c55e'
}

// ── Render ────────────────────────────────────────────────────────────────────
async function load() {
  try {
    const r = await fetch('/api/state')
    if (!r.ok) throw new Error(r.status)
    render(await r.json())
  } catch(e) {
    $('ts').textContent = 'error — retrying'
  }
}

function render(s) {
  const sys = s.system || {}, env = s.env || {}
  const tasks = s.tasks || [], budget = s.budget || {}
  const trace = s.trace || [], channels = s.channels || {}
  const agents = s.agents || {}, inbox = s.inbox || []
  const alerts = s.alerts || [], sched = s.sched || []
  const metrics = s.metrics || {}

  // Header
  const pct = sys.used_pct || 0
  const dc = diskColor(pct)
  $('ts').textContent = 'updated ' + (s.ts || '').slice(11, 16) + ' UTC'
  const db = $('disk-badge')
  db.textContent = sys.free_gb + 'GB free'
  db.style.cssText = `background:${dc}22;color:${dc};padding:3px 8px;border-radius:20px;font-size:11px;font-weight:700`

  // Mission bar
  if (env.mission) {
    $('mission-bar').style.display = 'flex'
    $('mission-text').textContent = env.mission
  }

  const html = []

  // ── Row 1: System + Disk ──────────────────────────────────────────────────
  const sessions = (sys.sessions || []).map(s => `<span class="session-chip">● ${esc(s)}</span>`).join('')
  const color = diskColor(pct)
  const arc = diskArc(pct, color)
  html.push(`
  <div class="card">
    <div class="card-hdr"><span class="card-title">System Pulse</span>
      <span style="font-size:11px;color:var(--muted)">v${esc(sys.version||'?')}</span>
    </div>
    <div class="stat-grid">
      <div class="stat-cell">
        <div class="stat-label">Host</div>
        <div class="stat-value" style="font-size:13px;font-family:monospace">${esc(sys.hostname||'?')}</div>
      </div>
      <div class="stat-cell">
        <div class="stat-label">Cron Jobs</div>
        <div class="stat-value">${esc(s.cron?.length||0)}</div>
      </div>
    </div>
    <div class="disk-wrap">
      <div class="disk-arc">${arc}<div class="disk-arc-text" style="color:${color}">${pct}%</div></div>
      <div class="disk-detail">
        <div style="font-size:13px;font-weight:600;color:${color}">${sys.free_gb} GB free</div>
        <div style="font-size:11px;color:var(--muted)">of ${sys.total_gb} GB total</div>
        <div class="disk-bar-wrap"><div class="disk-bar" style="width:${pct}%;background:${color}"></div></div>
        <div class="sessions-row">${sessions || '<span style="font-size:11px;color:var(--muted)">no sessions</span>'}</div>
      </div>
    </div>
  </div>`)

  // ── Social Factory Channels ───────────────────────────────────────────────
  const chKeys = Object.keys(channels)
  if (chKeys.length) {
    const maxV = Math.max(...chKeys.map(k => channels[k].views_7d), 1)
    const chCards = chKeys.map(k => {
      const ch = channels[k]
      const done = ch.done_today || 0
      const exp  = ch.expected_today || 4
      const prog = exp ? Math.round(done / exp * 100) : 0
      const hc   = ch.healthy ? 'var(--green)' : 'var(--red)'
      const vrel = Math.round(ch.views_7d / maxV * 100)
      const topV = ch.top_views > 0 ? `<span style="color:var(--text);font-weight:600">${fmt(ch.top_views)}</span> views` : ''
      const topT = ch.top_video ? `"${esc(ch.top_video.slice(0,45))}"` : ''
      return `<div class="ch-card">
        <div class="ch-name">
          <div class="ch-dot" style="background:${hc}"></div>
          ${esc(k)}
          ${ch.errors_today > 0 ? `<span class="badge red">${ch.errors_today} err</span>` : ''}
        </div>
        <div class="ch-progress">
          <div class="ch-prog-bar"><div class="ch-prog-fill" style="width:${prog}%;background:${hc}"></div></div>
          <div class="ch-prog-text">${done}/${exp} today</div>
        </div>
        <div style="display:flex;align-items:baseline;gap:8px">
          <div class="ch-views">${fmt(ch.views_7d)}<span style="font-size:11px;color:var(--muted);font-weight:400"> views 7d</span></div>
        </div>
        ${topT ? `<div class="ch-top">${topT} · ${topV}</div>` : ''}
      </div>`
    }).join('')
    html.push(`<div class="card">
      <div class="card-hdr"><span class="card-title">Social Factory</span>
        <span class="badge green">${chKeys.length} channels</span>
      </div>
      <div class="card-body no-pad"><div class="ch-grid">${chCards}</div></div>
    </div>`)
  }

  // ── Row: Tasks + Agents ───────────────────────────────────────────────────
  const open = tasks.filter(t => t.status === 'open')
  const taskItems = open.length ? open.map(t => {
    const pc = {high:'pri-high',medium:'pri-medium',low:'pri-low'}[t.priority||'medium']||'pri-medium'
    const ag = t.agent ? `<span style="font-size:11px;color:var(--muted)"> @${esc(t.agent)}</span>` : ''
    return `<div class="task-item">
      <span class="task-pri ${pc}">${esc(t.priority||'med')}</span>
      <span class="task-desc" title="${esc(t.desc)}">${esc(t.desc)}${ag}</span>
      <span class="task-id">#${t.id}</span>
      <button class="task-done-btn" onclick="markDone(${t.id},this)">done</button>
    </div>`
  }).join('') : `<div class="task-empty">✓ No open tasks</div>`

  const agentItems = Object.keys(agents).length ? Object.entries(agents).map(([name, info]) => {
    const alive = info.alive
    const dc2 = alive === true ? 'dot-green' : alive === false ? 'dot-red' : 'dot-grey'
    const sc = alive === true ? 'alive' : alive === false ? 'dead' : 'unknown'
    const sl = alive === true ? 'alive' : alive === false ? 'unreachable' : 'no check'
    return `<div class="agent-item">
      <div class="agent-dot ${dc2}"></div>
      <div class="agent-name">${esc(name)}</div>
      <div class="agent-status ${sc}">${sl}</div>
    </div>`
  }).join('') : `<div class="empty">no agents registered</div>`

  html.push(`<div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Tasks</span>
        ${open.length ? `<span class="badge">${open.length}</span>` : '<span class="badge green">0</span>'}
      </div>
      <div class="card-body no-pad">${taskItems}</div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Agents</span></div>
      <div class="card-body no-pad">${agentItems}</div>
    </div>
  </div>`)

  // ── Budget ────────────────────────────────────────────────────────────────
  const bycat = budget.by_category || {}, thresh = budget.thresholds || {}
  const total = budget.total || 0, tt = parseFloat(thresh.total || 0)
  const tp = tt ? Math.min(100, total / tt * 100) : 0
  let budHTML = `<div class="budget-total">
    <span class="budget-amount">$${total.toFixed(4)}</span>
    ${tt ? `<span class="budget-limit">/ $${tt.toFixed(2)}</span>` : ''}
    <span class="budget-month">${esc(budget.month||'')}</span>
  </div>`
  if (tt) budHTML += `<div class="bbar" style="margin-bottom:12px">
    <div class="bbar-fill" style="width:${tp.toFixed(1)}%;background:${barColor(tp)}"></div>
  </div>`
  for (const [cat, val] of Object.entries(bycat)) {
    const ct = parseFloat(thresh[cat] || 0), cp = ct ? Math.min(100, val / ct * 100) : 0
    budHTML += `<div class="budget-item">
      <div class="budget-row">
        <span class="budget-cat">${esc(cat)}</span>
        <span class="budget-val">$${val.toFixed(4)}${ct ? ' / $'+ct.toFixed(2) : ''}</span>
      </div>
      ${ct ? `<div class="bbar"><div class="bbar-fill" style="width:${cp.toFixed(1)}%;background:${barColor(cp)}"></div></div>` : ''}
    </div>`
  }
  if (!Object.keys(bycat).length) budHTML += `<div style="color:var(--muted);font-size:13px">no spend logged this month</div>`

  // ── Trace ─────────────────────────────────────────────────────────────────
  const recent = [...trace].reverse().slice(0, 12)
  const trHTML = recent.length ? recent.map(e => {
    const ok = e.outcome === 'success'
    const tags = (e.tags || []).map(t => `<span class="trace-tag">${esc(t)}</span>`).join('')
    const dt = (e.ts || '').slice(5, 10)
    return `<div class="trace-item">
      <div class="trace-icon ${ok ? 'ti-success' : 'ti-fail'}">${ok ? '✓' : '✗'}</div>
      <div class="trace-body">
        <div class="trace-action" title="${esc(e.action)}">${esc(e.action)}</div>
        ${e.detail ? `<div class="trace-detail">${esc(e.detail)}</div>` : ''}
        <div class="trace-meta">${tags}<span class="trace-ts">${dt}</span></div>
      </div>
    </div>`
  }).join('') : `<div class="empty">no outcomes logged yet — run: axis trace log</div>`

  html.push(`<div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Budget</span></div>
      <div class="card-body">${budHTML}</div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Trace</span>
        <span style="font-size:11px;color:var(--muted)">${recent.length} outcomes</span>
      </div>
      <div class="card-body no-pad">${trHTML}</div>
    </div>
  </div>`)

  // ── Inbox + Alerts ────────────────────────────────────────────────────────
  const inboxHTML = inbox.length ? inbox.map(n => `<div class="inbox-item">
    <div class="inbox-file">${esc(n.file)}</div>
    <div class="inbox-text">${esc(n.text)}</div>
  </div>`).join('') : `<div class="empty">inbox empty</div>`

  const alertHTML = alerts.length ? alerts.map(a =>
    `<div class="alert-item"><span class="alert-app">${esc(a.app)}</span><span class="alert-line">${esc(a.line)}</span></div>`
  ).join('') : `<div class="no-alerts">✓ No errors in last 24h</div>`

  html.push(`<div class="row-2">
    <div class="card">
      <div class="card-hdr"><span class="card-title">Inbox</span>
        ${inbox.length ? `<span class="badge yellow">${inbox.length}</span>` : ''}
      </div>
      <div class="card-body no-pad">${inboxHTML}</div>
      <div class="note-form">
        <textarea class="note-input" id="note-input" rows="1" placeholder="Leave a note…"></textarea>
        <button class="note-send" onclick="sendNote()">Send</button>
      </div>
    </div>
    <div class="card">
      <div class="card-hdr"><span class="card-title">Alerts</span>
        ${alerts.length ? `<span class="badge red">${alerts.length}</span>` : ''}
      </div>
      <div class="card-body no-pad">${alertHTML}</div>
    </div>
  </div>`)

  // ── Sched jobs ────────────────────────────────────────────────────────────
  if (sched.length) {
    const schedHTML = sched.map(j => {
      const paused = j.paused
      const lastRun = j.last_run ? j.last_run.slice(0,10) : 'never'
      const lastExit = j.last_exit !== null ? (j.last_exit === 0 ? '<span style="color:var(--green)">✓</span>' : '<span style="color:var(--red)">✗</span>') : ''
      return `<div class="task-item">
        <span class="task-pri ${paused ? 'pri-low' : 'pri-medium'}">${paused ? 'paused' : j.schedule_human||j.cron}</span>
        <span class="task-desc">${esc(j.name)}</span>
        <span class="task-id">${lastRun} ${lastExit}</span>
      </div>`
    }).join('')
    html.push(`<div class="card">
      <div class="card-hdr"><span class="card-title">Scheduled Jobs</span>
        <span class="badge">${sched.length}</span>
      </div>
      <div class="card-body no-pad">${schedHTML}</div>
    </div>`)
  }

  $('main').innerHTML = html.join('')
}

async function markDone(id, btn) {
  btn.textContent = '…'
  btn.disabled = true
  try {
    const r = await fetch('/api/task/done', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})})
    if (r.ok) { btn.textContent = '✓'; btn.style.color = 'var(--green)'; setTimeout(load, 800) }
    else { btn.textContent = 'err'; btn.disabled = false }
  } catch { btn.textContent = 'err'; btn.disabled = false }
}

async function sendNote() {
  const inp = $('note-input')
  const text = inp.value.trim()
  if (!text) return
  inp.disabled = true
  try {
    const r = await fetch('/api/note', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})})
    if (r.ok) { inp.value = ''; setTimeout(load, 400) }
  } finally { inp.disabled = false }
}

load()
setInterval(load, 10000)
</script>
</body>
</html>"""

# ── HTTP handler ──────────────────────────────────────────────────────────────

class DashHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def check_auth(self):
        token = getattr(self.server, "token", "")
        if not token: return True
        return self.headers.get("Authorization", "") == f"Bearer {token}"

    def send_json(self, data, status=200):
        body = json.dumps(data, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html):
        b = html.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", len(b))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if not self.check_auth():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Bearer realm="dash"')
            self.end_headers(); return
        path = urlparse(self.path).path
        if path == "/":                        self.send_html(HTML)
        elif path == "/api/state":             self.send_json(build_state())
        elif path.startswith("/api/logs/"):    self._serve_log(path[len("/api/logs/"):])
        else:                                  self.send_response(404); self.end_headers()

    def do_POST(self):
        if not self.check_auth():
            self.send_response(401); self.end_headers(); return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"
        try: data = json.loads(body)
        except: data = {}

        if path == "/api/task/done":
            tid = data.get("id")
            if tid is None: return self.send_json({"ok": False, "error": "missing id"}, 400)
            store = HOME / "system/tasks.json"
            try:
                d = json.loads(store.read_text())
                for t in d["tasks"]:
                    if t["id"] == int(tid): t["status"] = "done"
                store.write_text(json.dumps(d, indent=2))
                self.send_json({"ok": True})
            except Exception as e: self.send_json({"ok": False, "error": str(e)}, 500)

        elif path == "/api/note":
            text = data.get("text", "").strip()
            if not text: return self.send_json({"ok": False, "error": "empty"}, 400)
            inbox = HOME / "inbox"
            inbox.mkdir(exist_ok=True)
            ts = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H%M%S")
            (inbox / f"{ts}-dash.md").write_text(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}] (dashboard): {text}\n")
            self.send_json({"ok": True})
        else:
            self.send_response(404); self.end_headers()

    def _serve_log(self, app):
        apps_dir = HOME / "apps"
        candidates = list(apps_dir.glob(f"{app}/**/logs/*.log")) + list(apps_dir.glob(f"{app}/**/*.log"))
        if not candidates: return self.send_json({"lines": [], "error": f"no logs for {app}"})
        mf = max(candidates, key=lambda p: p.stat().st_mtime)
        try:
            lines = mf.read_text().strip().splitlines()[-100:]
            self.send_json({"file": str(mf), "lines": lines})
        except Exception as e: self.send_json({"error": str(e)})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    server = HTTPServer((args.bind, args.port), DashHandler)
    server.token = args.token
    print(f"dash listening on http://{args.bind}:{args.port}", flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__": main()
