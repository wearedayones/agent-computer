#!/usr/bin/env python3
"""dash-server.py — Agent Computer v4 lightweight web dashboard
Bind: 127.0.0.1:2222 by default (safe — forward via SSH tunnel for remote access)
Usage: python3 ~/scripts/dash-server.py [--port 2222] [--bind 127.0.0.1] [--token <secret>]
"""
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
        free_gb = round(st.f_bavail * st.f_frsize / 1e9, 1)
        used_pct = int(100 * (1 - st.f_bavail / st.f_blocks))
        return {"free_gb": free_gb, "used_pct": used_pct}
    except:
        return {}

def version_info():
    v, h = "unknown", "unknown"
    try: v = (HOME / "system/.version").read_text().strip()
    except: pass
    try: h = subprocess.check_output(["hostname"], text=True, stderr=subprocess.DEVNULL).strip()
    except: pass
    return {"version": v, "hostname": h}

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

def trace_data(limit=15):
    try:
        lines = (HOME / "system/trace.jsonl").read_text().strip().splitlines()
        return [json.loads(l) for l in lines if l.strip()][-limit:]
    except:
        return []

def metrics_data():
    apps_dir = HOME / "apps"
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d")
    channels = {}
    if not apps_dir.exists():
        return {}
    for app in sorted(apps_dir.iterdir()):
        if not app.is_dir() or app.name == "envs":
            continue
        for mf in app.rglob("metrics.jsonl"):
            parent = mf.parent.parent
            label = f"{app.name}/{parent.name}" if parent.name != app.name else app.name
            try:
                entries = [json.loads(l) for l in mf.read_text().splitlines() if l.strip()]
                recent = [e for e in entries if e.get("date", "") >= cutoff]
                views = 0
                for e in recent:
                    if "videos" in e:
                        views += sum(v.get("views", 0) or 0 for v in e["videos"])
                    elif "views" in e:
                        views += e.get("views", 0) or 0
                if recent:
                    channels[label] = {"views_7d": views, "days": len(recent)}
            except:
                pass
    return dict(sorted(channels.items(), key=lambda x: -x[1]["views_7d"]))

def inbox_data():
    inbox = HOME / "inbox"
    notes = []
    if inbox.exists():
        for f in sorted(inbox.iterdir(), reverse=True)[:5]:
            if f.is_file():
                try:
                    notes.append({"file": f.name, "text": f.read_text().strip()[:300]})
                except:
                    pass
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
                        alerts.append({"app": app, "line": line.strip()[:140]})
        except:
            pass
    return alerts[-30:]

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

def build_state():
    return {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "system": {**version_info(), **disk_info()},
        "env": env_data(),
        "tasks": tasks_data(),
        "budget": budget_data(),
        "trace": trace_data(),
        "metrics": metrics_data(),
        "inbox": inbox_data(),
        "alerts": alerts_data(),
        "cron": cron_data(),
    }

# ── Embedded dashboard HTML ───────────────────────────────────────────────────

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Agent Computer</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'SF Mono',Monaco,'Cascadia Code',monospace;background:#0d1117;color:#c9d1d9;font-size:13px;line-height:1.55}
h2{font-size:11px;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.09em;margin-bottom:10px}
#header{padding:13px 18px;border-bottom:1px solid #21262d;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;background:#0d1117;z-index:9}
#header h1{font-size:14px;color:#e6edf3;font-weight:600;display:flex;align-items:center;gap:8px}
#status{font-size:11px;color:#484f58}
#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:12px;padding:14px}
.card{background:#161b22;border:1px solid #21262d;border-radius:8px;padding:15px}
.row{display:flex;justify-content:space-between;align-items:baseline;padding:4px 0;border-bottom:1px solid #21262d20}
.row:last-child{border:none}
.key{color:#8b949e;flex-shrink:0;min-width:100px}
.val{color:#e6edf3;text-align:right;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:220px}
.tag{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px;font-weight:600}
.success{background:#1a3a1a;color:#56d364}
.fail{background:#3a1a1a;color:#f85149}
.high{background:#3a2a1a;color:#f0883e}
.medium{background:#1a2a3a;color:#58a6ff}
.low{background:#1e2129;color:#6e7681}
.bar-wrap{background:#21262d;border-radius:4px;height:5px;margin-top:5px;margin-bottom:2px}
.bar{height:5px;border-radius:4px;background:#238636;transition:width .4s}
.bar.warn{background:#d29922}
.bar.over{background:#f85149}
.metric-row{display:flex;align-items:center;gap:10px;padding:4px 0}
.mlabel{color:#c9d1d9;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
.mbar{flex:0 0 80px;background:#21262d;border-radius:3px;height:4px}
.mfill{height:4px;border-radius:3px;background:#58a6ff;transition:width .4s}
.mval{color:#e6edf3;min-width:75px;text-align:right;flex-shrink:0}
.alert-line{padding:3px 0;color:#f85149;font-size:11px;word-break:break-all;border-bottom:1px solid #21262d15}
.alert-line:last-child{border:none}
.alert-app{color:#d29922;font-size:10px}
.note{padding:5px 0;border-bottom:1px solid #21262d20}
.note:last-child{border:none}
.note-text{color:#e6edf3;font-size:12px;white-space:pre-wrap}
.note-ts{color:#484f58;font-size:10px;margin-top:2px}
.trace-row{display:flex;align-items:baseline;gap:6px;padding:4px 0;border-bottom:1px solid #21262d15}
.trace-row:last-child{border:none}
.trace-action{color:#e6edf3;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.trace-ts{color:#484f58;font-size:10px;flex-shrink:0}
.task-row{display:flex;align-items:baseline;gap:7px;padding:4px 0}
.task-desc{color:#e6edf3;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.task-id{color:#484f58;font-size:11px;flex-shrink:0}
.cron-line{color:#6e7681;font-size:11px;padding:2px 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.empty{color:#484f58;font-style:italic;font-size:12px;padding:5px 0}
.pulse{width:8px;height:8px;border-radius:50%;background:#238636;animation:blink 2s infinite;flex-shrink:0}
@keyframes blink{0%,100%{opacity:1}50%{opacity:.35}}
.disk-ok{color:#56d364}.disk-warn{color:#d29922}.disk-crit{color:#f85149}
.mission{color:#58a6ff;font-size:12px;margin-bottom:10px;padding-bottom:8px;border-bottom:1px solid #21262d}
</style>
</head>
<body>
<div id="header">
  <h1><div class="pulse"></div>Agent Computer</h1>
  <span id="status">loading…</span>
</div>
<div id="grid"></div>
<script>
const esc=s=>String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
const row=(k,v)=>`<div class="row"><span class="key">${esc(k)}</span><span class="val">${v}</span></div>`

async function load(){
  try{
    const r=await fetch('/api/state')
    if(!r.ok)throw new Error(r.status)
    render(await r.json())
  }catch(e){
    document.getElementById('status').textContent='fetch error — retrying'
  }
}

function barClass(pct){return pct>=90?'over':pct>=70?'warn':''}

function render(s){
  const sys=s.system||{},env=s.env||{},tasks=s.tasks||[]
  const budget=s.budget||{},trace=s.trace||[],metrics=s.metrics||{}
  const inbox=s.inbox||[],alerts=s.alerts||[],cron=s.cron||[]
  const cards=[]

  // System Pulse
  const pct=sys.used_pct||0
  const dc=pct>=90?'disk-crit':pct>=75?'disk-warn':'disk-ok'
  const mission=env.mission?`<div class="mission">${esc(env.mission)}</div>`:''
  cards.push(`<div class="card"><h2>System Pulse</h2>${mission}
    ${row('version','v'+esc(sys.version||'?'))}
    ${row('host',esc(sys.hostname||'?'))}
    ${row('disk free',`<span class="${dc}">${sys.free_gb||'?'} GB (${pct}% used)</span>`)}
    ${row('cron jobs',cron.length)}
    ${row('updated',esc((s.ts||'').slice(11,16))+' UTC')}
  </div>`)

  // Tasks
  const open=tasks.filter(t=>t.status==='open')
  const tHTML=open.length?open.map(t=>{
    const p=t.priority||'medium'
    const ag=t.agent?` <span style="color:#484f58;font-size:11px">@${esc(t.agent)}</span>`:''
    return `<div class="task-row"><span class="tag ${p}">${p}</span><span class="task-desc">${esc(t.desc)}${ag}</span><span class="task-id">#${t.id}</span></div>`
  }).join(''):'<div class="empty">no open tasks</div>'
  cards.push(`<div class="card"><h2>Tasks — ${open.length} open</h2>${tHTML}</div>`)

  // Budget
  const bycat=budget.by_category||{},thresh=budget.thresholds||{}
  const total=budget.total||0,tt=parseFloat(thresh.total||0)
  const tp=tt?Math.min(100,total/tt*100):0
  let bHTML=`<div class="row"><span class="key">total ${esc(budget.month||'')}</span><span class="val">$${total.toFixed(4)}${tt?' / $'+tt.toFixed(2):''}</span></div>`
  if(tt)bHTML+=`<div class="bar-wrap"><div class="bar ${barClass(tp)}" style="width:${tp.toFixed(1)}%"></div></div>`
  for(const[cat,val]of Object.entries(bycat)){
    const ct=parseFloat(thresh[cat]||0),cp=ct?Math.min(100,val/ct*100):0
    bHTML+=`<div class="row" style="margin-top:6px"><span class="key">${esc(cat)}</span><span class="val">$${val.toFixed(4)}${ct?' / $'+ct.toFixed(2):''}</span></div>`
    if(ct)bHTML+=`<div class="bar-wrap"><div class="bar ${barClass(cp)}" style="width:${cp.toFixed(1)}%"></div></div>`
  }
  if(!Object.keys(bycat).length)bHTML+='<div class="empty">no spend logged this month</div>'
  cards.push(`<div class="card"><h2>Budget</h2>${bHTML}</div>`)

  // Trace
  const recent=[...trace].reverse().slice(0,10)
  const trHTML=recent.length?recent.map(e=>{
    const cls=e.outcome==='success'?'success':'fail'
    const tags=(e.tags||[]).map(t=>`<span class="tag" style="background:#21262d;color:#8b949e;font-size:10px">${esc(t)}</span>`).join(' ')
    return `<div class="trace-row">
      <span class="tag ${cls}">${esc(e.outcome||'?')}</span>
      <span class="trace-action" title="${esc(e.detail||'')}">${esc(e.action||'')}</span>
      <span class="trace-ts">${esc((e.ts||'').slice(5,10))}</span>
      ${tags?`<span>${tags}</span>`:''}
    </div>`
  }).join(''):'<div class="empty">no outcomes logged yet</div>'
  cards.push(`<div class="card"><h2>Trace — last ${recent.length}</h2>${trHTML}</div>`)

  // Metrics
  const maxV=Math.max(...Object.values(metrics).map(m=>m.views_7d),1)
  const mHTML=Object.keys(metrics).length?Object.entries(metrics).map(([label,m])=>{
    const p=Math.round(m.views_7d/maxV*100)
    return `<div class="metric-row">
      <span class="mlabel">${esc(label)}</span>
      <div class="mbar"><div class="mfill" style="width:${p}%"></div></div>
      <span class="mval">${m.views_7d.toLocaleString()} views</span>
    </div>`
  }).join(''):'<div class="empty">no metrics found</div>'
  cards.push(`<div class="card"><h2>Metrics — 7d views</h2>${mHTML}</div>`)

  // Inbox
  const iHTML=inbox.length?inbox.map(n=>`<div class="note"><div class="note-text">${esc(n.text)}</div><div class="note-ts">${esc(n.file)}</div></div>`).join(''):'<div class="empty">inbox empty</div>'
  cards.push(`<div class="card"><h2>Inbox</h2>${iHTML}</div>`)

  // Alerts
  const aHTML=alerts.length?alerts.map(a=>`<div class="alert-line"><span class="alert-app">[${esc(a.app)}]</span> ${esc(a.line)}</div>`).join(''):'<div class="empty" style="color:#56d364">no errors in the last 24h</div>'
  cards.push(`<div class="card"><h2>Alerts — 24h</h2>${aHTML}</div>`)

  // Cron
  const cronHTML=cron.length?cron.slice(0,8).map(l=>`<div class="cron-line">${esc(l)}</div>`).join(''):'<div class="empty">no cron jobs</div>'
  cards.push(`<div class="card"><h2>Cron — ${cron.length} jobs</h2>${cronHTML}</div>`)

  document.getElementById('grid').innerHTML=cards.join('')
  document.getElementById('status').textContent='updated '+(s.ts||'').slice(11,16)+' UTC · auto-refresh 10s'
}

load()
setInterval(load,10000)
</script>
</body>
</html>"""

# ── HTTP handler ──────────────────────────────────────────────────────────────

class DashHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def check_auth(self):
        token = getattr(self.server, "token", "")
        if not token:
            return True
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
            self.end_headers()
            return
        path = urlparse(self.path).path
        if path == "/":
            self.send_html(HTML)
        elif path == "/api/state":
            self.send_json(build_state())
        elif path.startswith("/api/logs/"):
            self._serve_log(path[len("/api/logs/"):])
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if not self.check_auth():
            self.send_response(401)
            self.end_headers()
            return
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(body)
        except:
            data = {}

        if path == "/api/task/done":
            tid = data.get("id")
            if tid is None:
                return self.send_json({"ok": False, "error": "missing id"}, 400)
            store = HOME / "system/tasks.json"
            try:
                d = json.loads(store.read_text())
                for t in d["tasks"]:
                    if t["id"] == int(tid):
                        t["status"] = "done"
                store.write_text(json.dumps(d, indent=2))
                self.send_json({"ok": True})
            except Exception as e:
                self.send_json({"ok": False, "error": str(e)}, 500)

        elif path == "/api/note":
            text = data.get("text", "").strip()
            if not text:
                return self.send_json({"ok": False, "error": "empty text"}, 400)
            inbox = HOME / "inbox"
            inbox.mkdir(exist_ok=True)
            ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
            (inbox / f"{ts}-dash.txt").write_text(text + "\n")
            self.send_json({"ok": True})
        else:
            self.send_response(404)
            self.end_headers()

    def _serve_log(self, app):
        apps_dir = HOME / "apps"
        candidates = list(apps_dir.glob(f"{app}/**/logs/*.log")) + \
                     list(apps_dir.glob(f"{app}/**/*.log"))
        if not candidates:
            return self.send_json({"lines": [], "error": f"no logs for {app}"})
        mf = max(candidates, key=lambda p: p.stat().st_mtime)
        try:
            lines = mf.read_text().strip().splitlines()[-100:]
            self.send_json({"file": str(mf), "lines": lines})
        except Exception as e:
            self.send_json({"error": str(e)})

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Agent Computer dashboard server")
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    server = HTTPServer((args.bind, args.port), DashHandler)
    server.token = args.token
    print(f"dash listening on http://{args.bind}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
