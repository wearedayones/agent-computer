#!/bin/bash
# trace — outcome memory ledger (survives context resets)
# Usage: trace log "action" --outcome success|fail [--detail "..."] [--tags tag1,tag2]
#        trace last [N]
#        trace search <query> [--outcome success|fail]
#        trace stats
#        trace show <id>

STORE="$HOME/system/trace.jsonl"
ARCHIVE_DIR="$HOME/system"
MAX_ENTRIES=10000

mkdir -p "$HOME/system"
touch "$STORE"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

_rotate_if_needed() {
  local count
  count=$(wc -l < "$STORE" | tr -d ' ')
  if [ "${count:-0}" -ge "$MAX_ENTRIES" ]; then
    year=$(date -u +%Y)
    archive="$ARCHIVE_DIR/trace-archive-${year}.jsonl"
    cat "$STORE" >> "$archive"
    : > "$STORE"
    echo "  (rotated $count entries to $(basename "$archive"))"
  fi
}

cmd="${1:-last}"

case "$cmd" in
  log)
    shift
    action=""
    outcome="success"
    detail=""
    tags=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --outcome) outcome="$2"; shift 2 ;;
        --detail)  detail="$2";  shift 2 ;;
        --tags)    tags="$2";    shift 2 ;;
        *) action="${action:+$action }$1"; shift ;;
      esac
    done
    [ -z "$action" ] && { echo "Usage: trace log \"action\" [--outcome success|fail] [--detail \"...\"] [--tags tag1,tag2]"; exit 1; }
    [[ "$outcome" != "success" && "$outcome" != "fail" ]] && { echo "  --outcome must be 'success' or 'fail'"; exit 1; }
    _rotate_if_needed
    python3 - "$STORE" "$action" "$outcome" "$detail" "$tags" <<'EOF'
import json, sys, os
from datetime import datetime, timezone
store, action, outcome, detail, tags_raw = sys.argv[1:6]
tags = [t.strip() for t in tags_raw.split(",") if t.strip()] if tags_raw else []
session_ts = ""
try:
    with open(os.path.expanduser("~/.session_start")) as f:
        for line in f:
            if line.startswith("ts="):
                session_ts = line.strip()[3:]
except: pass
entry = {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "agent": os.environ.get("AGENT_NAME", "claude"),
    "action": action,
    "outcome": outcome,
    "detail": detail,
    "tags": tags,
    "session": session_ts,
}
with open(store, "a") as f:
    f.write(json.dumps(entry) + "\n")
icon = "\033[32m✓\033[0m" if outcome == "success" else "\033[31m✗\033[0m"
print(f"  {icon}  Traced: [{outcome.upper()}] {action}")
EOF
    ;;

  last)
    n="${2:-10}"
    python3 - "$STORE" "$n" <<'EOF'
import json, sys
from datetime import datetime, timezone
store, n = sys.argv[1], int(sys.argv[2])
try:
    lines = open(store).readlines()
except: lines = []
entries = []
for line in lines:
    line = line.strip()
    if line:
        try: entries.append(json.loads(line))
        except: pass
entries = entries[-n:]
if not entries:
    print("  (no outcomes recorded yet)")
    print("  Add one: trace log \"action\" --outcome success")
    sys.exit(0)
GREEN, RED, YELLOW, BOLD, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[1m", "\033[0m"
print(f"\n  {BOLD}Last {len(entries)} outcomes{NC}\n")
print(f"  {'─'*60}")
for e in reversed(entries):
    ts = e.get("ts","")[:10]
    outcome = e.get("outcome","?")
    icon = f"{GREEN}✓{NC}" if outcome == "success" else f"{RED}✗{NC}"
    action = e.get("action","?")
    detail = e.get("detail","")
    tags = e.get("tags",[])
    tag_str = f"  [{','.join(tags)}]" if tags else ""
    print(f"  {icon}  {ts}  {action}")
    if detail:
        print(f"         {YELLOW}→{NC} {detail}")
    if tag_str:
        print(f"         {tag_str}")
print("")
EOF
    ;;

  search)
    shift
    query=""
    outcome_filter=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --outcome) outcome_filter="$2"; shift 2 ;;
        *) query="${query:+$query }$1"; shift ;;
      esac
    done
    python3 - "$STORE" "$query" "$outcome_filter" <<'EOF'
import json, sys, re
store, query, outcome_filter = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
try:
    lines = open(store).readlines()
except: lines = []
entries = []
for line in lines:
    line = line.strip()
    if not line: continue
    try: e = json.loads(line)
    except: continue
    if outcome_filter and e.get("outcome","") != outcome_filter:
        continue
    searchable = " ".join([e.get("action",""), e.get("detail",""), ",".join(e.get("tags",[]))]).lower()
    if not query or query in searchable:
        entries.append(e)
GREEN, RED, YELLOW, BOLD, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[1m", "\033[0m"
if not entries:
    label = f" matching '{query}'" if query else ""
    filt = f" (outcome={outcome_filter})" if outcome_filter else ""
    print(f"  (no outcomes{label}{filt})")
    sys.exit(0)
label = f" matching '{query}'" if query else ""
filt = f" [{outcome_filter}]" if outcome_filter else ""
print(f"\n  {BOLD}{len(entries)} outcome(s){label}{filt}{NC}\n")
print(f"  {'─'*60}")
for e in reversed(entries[-50:]):
    ts = e.get("ts","")[:10]
    outcome = e.get("outcome","?")
    icon = f"{GREEN}✓{NC}" if outcome == "success" else f"{RED}✗{NC}"
    action = e.get("action","?")
    detail = e.get("detail","")
    tags = e.get("tags",[])
    tag_str = f"  [{','.join(tags)}]" if tags else ""
    print(f"  {icon}  {ts}  {action}")
    if detail:
        print(f"         {YELLOW}→{NC} {detail}")
    if tag_str:
        print(f"         {tag_str}")
print("")
EOF
    ;;

  stats)
    python3 - "$STORE" <<'EOF'
import json, sys
from datetime import datetime, timezone, timedelta
store = sys.argv[1]
try:
    lines = open(store).readlines()
except: lines = []
entries = []
for line in lines:
    line = line.strip()
    if line:
        try: entries.append(json.loads(line))
        except: pass
GREEN, RED, YELLOW, BOLD, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[1m", "\033[0m"
if not entries:
    print("  (no outcomes recorded yet)")
    sys.exit(0)
total = len(entries)
successes = sum(1 for e in entries if e.get("outcome") == "success")
fails = total - successes
rate = (successes / total * 100) if total else 0
cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
recent = [e for e in entries if e.get("ts","") >= cutoff]
recent_fail = [e for e in recent if e.get("outcome") == "fail"]
# Tag frequency
tags = {}
for e in entries:
    for t in e.get("tags", []):
        tags[t] = tags.get(t, 0) + 1
print(f"\n  {BOLD}Trace Stats{NC}")
print(f"  {'─'*40}")
print(f"  Total outcomes : {total}")
print(f"  Success        : {GREEN}{successes}{NC}")
print(f"  Fail           : {RED}{fails}{NC}")
print(f"  Success rate   : {rate:.1f}%")
print(f"  Last 7 days    : {len(recent)} ({len(recent_fail)} fail)")
if tags:
    top = sorted(tags.items(), key=lambda x: -x[1])[:5]
    print(f"\n  Top tags:")
    for t, c in top:
        print(f"    {t}: {c}")
print("")
EOF
    ;;

  show)
    [ -z "$2" ] && { echo "Usage: trace show <index>"; exit 1; }
    python3 - "$STORE" "$2" <<'EOF'
import json, sys
store, idx = sys.argv[1], int(sys.argv[2])
try:
    lines = [l.strip() for l in open(store).readlines() if l.strip()]
except: lines = []
if idx < 1 or idx > len(lines):
    print(f"  (out of range — {len(lines)} entries total)"); sys.exit(1)
e = json.loads(lines[idx-1])
BOLD, NC = "\033[1m", "\033[0m"
print(f"\n  {BOLD}Outcome #{idx}{NC}")
for k, v in e.items():
    print(f"  {k:<10} {v}")
print("")
EOF
    ;;

  *)
    echo "Usage: trace log|last|search|stats|show [args]"
    exit 1
    ;;
esac
