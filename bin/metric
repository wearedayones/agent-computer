#!/bin/bash
# metric — unified read-only aggregator over app metrics
# Convention: apps write to ~/apps/<name>/**/state/metrics.jsonl and state/status.json
# Usage: metric show [<app>] [<channel>]
#        metric trend <field> --app <app> [--days N]
#        metric top --by <field> [--days N]
#        metric list

APPS_DIR="$HOME/apps"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

cmd="${1:-list}"

case "$cmd" in
  list)
    python3 - "$APPS_DIR" <<'EOF'
import os, json, sys
apps_dir = sys.argv[1]
BOLD, NC = "\033[1m", "\033[0m"
if not os.path.isdir(apps_dir):
    print("  (no apps directory)"); sys.exit(0)
apps = sorted([d for d in os.listdir(apps_dir) if os.path.isdir(os.path.join(apps_dir,d)) and d != "envs"])
if not apps:
    print("  (no apps found in ~/apps/)"); sys.exit(0)
print(f"\n  {BOLD}Apps with metrics{NC}\n")
for app in apps:
    metrics_files = []
    app_dir = os.path.join(apps_dir, app)
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in ('envs', '__pycache__', '.git', 'node_modules')]
        for f in files:
            if f == "metrics.jsonl":
                metrics_files.append(os.path.relpath(os.path.join(root, f), apps_dir))
    if metrics_files:
        print(f"  {app}:")
        for mf in metrics_files:
            print(f"    ~/apps/{mf}")
    else:
        print(f"  {app}:  (no metrics.jsonl found)")
print("")
print(f"  Convention: apps write metrics to ~/apps/<name>/**/state/metrics.jsonl")
print(f"  Each line: {{\"ts\":\"...\",\"channel\":\"...\", <metric-fields>}}\n")
EOF
    ;;

  show)
    app="${2:-}"
    channel="${3:-}"
    python3 - "$APPS_DIR" "$app" "$channel" <<'EOF'
import os, json, sys
from datetime import datetime, timezone, timedelta
apps_dir, filter_app, filter_channel = sys.argv[1:4]
BOLD, YELLOW, GREEN, NC = "\033[1m", "\033[1;33m", "\033[0;32m", "\033[0m"

def find_metrics(apps_dir, filter_app, filter_channel):
    results = []
    if filter_app:
        roots = [os.path.join(apps_dir, filter_app)]
    else:
        roots = [os.path.join(apps_dir, d) for d in os.listdir(apps_dir)
                 if os.path.isdir(os.path.join(apps_dir, d)) and d != "envs"]
    for root in roots:
        if not os.path.isdir(root): continue
        app_name = os.path.basename(root)
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ('__pycache__', '.git', 'node_modules')]
            if "metrics.jsonl" in files:
                mf = os.path.join(dirpath, "metrics.jsonl")
                chan = os.path.basename(os.path.dirname(dirpath)) if "state" in dirpath else app_name
                if filter_channel and chan != filter_channel: continue
                results.append((app_name, chan, mf))
    return results

sources = find_metrics(apps_dir, filter_app, filter_channel)
if not sources:
    label = f" for {filter_app}" if filter_app else ""
    print(f"  (no metrics found{label})")
    sys.exit(0)

cutoff = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ")

for app_name, chan, mf in sources:
    try:
        lines = open(mf).readlines()
        entries = [json.loads(l) for l in lines if l.strip()]
        recent = [e for e in entries if e.get("ts","") >= cutoff]
        if not recent: recent = entries[-5:] if entries else []
    except: continue
    label = f"{app_name}/{chan}" if chan != app_name else app_name
    print(f"\n  {BOLD}{label}{NC}")
    print(f"  {'─'*45}")
    if recent:
        last = recent[-1]
        for k, v in last.items():
            if k in ("ts","channel","app"): continue
            print(f"  {YELLOW}{k:<20}{NC} {v}")
        print(f"  (from {last.get('ts','?')[:16]})")
    else:
        print("  (no data)")
print("")
EOF
    ;;

  trend)
    shift
    field="${1:-}"; shift
    app=""
    days=7
    while [ $# -gt 0 ]; do
      case "$1" in
        --app)  app="$2";  shift 2 ;;
        --days) days="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "$field" ] && { echo "Usage: metric trend <field> --app <app> [--days N]"; exit 1; }
    python3 - "$APPS_DIR" "$field" "$app" "$days" <<'EOF'
import os, json, sys
from datetime import datetime, timezone, timedelta
apps_dir, field, filter_app, days_str = sys.argv[1:5]
days = int(days_str)
BOLD, YELLOW, NC = "\033[1m", "\033[1;33m", "\033[0m"
cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")

def find_all_metrics(apps_dir, filter_app):
    results = []
    if filter_app:
        roots = [os.path.join(apps_dir, filter_app)]
    else:
        roots = [os.path.join(apps_dir, d) for d in os.listdir(apps_dir)
                 if os.path.isdir(os.path.join(apps_dir,d)) and d != "envs"]
    for root in roots:
        if not os.path.isdir(root): continue
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ('__pycache__', '.git', 'node_modules')]
            if "metrics.jsonl" in files:
                results.append(os.path.join(dirpath, "metrics.jsonl"))
    return results

entries = []
for mf in find_all_metrics(apps_dir, filter_app):
    try:
        for line in open(mf):
            line = line.strip()
            if not line: continue
            e = json.loads(line)
            if e.get("ts","") >= cutoff and field in e:
                entries.append(e)
    except: pass

entries.sort(key=lambda e: e.get("ts",""))
if not entries:
    print(f"  No data for field '{field}' in the last {days} days"); sys.exit(0)

print(f"\n  {BOLD}Trend: {field} (last {days} days){NC}\n")
print(f"  {'Date':<12}  {'Value'}")
print(f"  {'─'*40}")
for e in entries[-20:]:
    ts = e.get("ts","")[:10]
    val = e.get(field,"?")
    print(f"  {ts}  {YELLOW}{val}{NC}")
print("")
EOF
    ;;

  top)
    shift
    field=""
    days=7
    while [ $# -gt 0 ]; do
      case "$1" in
        --by)   field="$2"; shift 2 ;;
        --days) days="$2";  shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "$field" ] && { echo "Usage: metric top --by <field> [--days N]"; exit 1; }
    python3 - "$APPS_DIR" "$field" "$days" <<'EOF'
import os, json, sys
from datetime import datetime, timezone, timedelta
apps_dir, field, days_str = sys.argv[1:4]
days = int(days_str)
BOLD, YELLOW, NC = "\033[1m", "\033[1;33m", "\033[0m"
cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
app_totals = {}
for app in os.listdir(apps_dir):
    app_dir = os.path.join(apps_dir, app)
    if not os.path.isdir(app_dir) or app == "envs": continue
    for dirpath, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in ('__pycache__', '.git', 'node_modules')]
        if "metrics.jsonl" not in files: continue
        mf = os.path.join(dirpath, "metrics.jsonl")
        try:
            for line in open(mf):
                line = line.strip()
                if not line: continue
                e = json.loads(line)
                if e.get("ts","") >= cutoff and field in e:
                    key = f"{app}"
                    try: app_totals[key] = app_totals.get(key, 0) + float(e[field])
                    except: pass
        except: pass
if not app_totals:
    print(f"  No data for field '{field}' in the last {days} days"); sys.exit(0)
ranked = sorted(app_totals.items(), key=lambda x: -x[1])
print(f"\n  {BOLD}Top by {field} (last {days} days){NC}\n")
for i, (app, val) in enumerate(ranked[:10], 1):
    print(f"  {i:>2}. {app:<30}  {YELLOW}{val:.1f}{NC}")
print("")
EOF
    ;;

  *)
    echo "Usage: metric list|show|trend|top [args]"
    exit 1
    ;;
esac
