#!/bin/bash
# ctx — session continuity brief (LLM-ready compressed state)
# Usage: ctx brief                  — print current-state brief for pasting
#        ctx save <name>            — snapshot state to ~/system/contexts/<name>.json
#        ctx load <name>            — print saved context as LLM-ready brief
#        ctx list                   — list saved contexts
#        ctx del <name>             — delete a saved context

CTX_DIR="$HOME/system/contexts"
mkdir -p "$CTX_DIR"

SYSTEM="$HOME/system"
ENV_FILE="$SYSTEM/env.json"
TASKS_FILE="$SYSTEM/tasks.json"
TRACE_FILE="$SYSTEM/trace.jsonl"
BUDGET_FILE="$SYSTEM/budget.json"
PLAN_FILE="$SYSTEM/plan.md"

cmd="${1:-brief}"

_generate_brief() {
  python3 - "$ENV_FILE" "$TASKS_FILE" "$TRACE_FILE" "$BUDGET_FILE" "$PLAN_FILE" <<'EOF'
import json, sys, os
from datetime import datetime, timezone, timedelta

env_f, tasks_f, trace_f, budget_f, plan_f = sys.argv[1:6]

# Load env
env = {}
try:
    with open(env_f) as f: env = json.load(f)
except: pass

# Load tasks
tasks_open = []
try:
    with open(tasks_f) as f: d = json.load(f)
    tasks_open = [t for t in d.get("tasks",[]) if t.get("status") == "open"]
except: pass

# Load trace (last 5 outcomes)
trace_recent = []
try:
    lines = open(trace_f).readlines()
    for line in lines:
        line = line.strip()
        if line:
            try: trace_recent.append(json.loads(line))
            except: pass
    trace_recent = trace_recent[-10:]
except: pass

# Load budget
budget_total = None
budget_month = None
try:
    with open(budget_f) as f: d = json.load(f)
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    entries = [e for e in d.get("entries",[]) if e.get("month","") == month]
    budget_total = sum(e["amount"] for e in entries)
    budget_month = month
except: pass

# Load plan
plan_title = None
plan_done = 0
plan_todo = 0
plan_next = []
try:
    lines = open(plan_f).readlines()
    if lines:
        plan_title = lines[0].strip().lstrip("# ").replace("Plan: ","")
    for l in lines:
        if "[x]" in l: plan_done += 1
        elif "[ ]" in l:
            plan_todo += 1
            if len(plan_next) < 3:
                plan_next.append(l.strip().lstrip("- [ ]").strip())
except: pass

# Disk
disk_free = "?"
disk_pct = "?"
try:
    import subprocess
    r = subprocess.run(["df", "-h", os.path.expanduser("~")], capture_output=True, text=True)
    parts = r.stdout.splitlines()[1].split()
    disk_pct, disk_free = parts[4], parts[3]
except: pass

# tmux sessions
sessions = "none"
try:
    import subprocess
    r = subprocess.run(["tmux", "ls"], capture_output=True, text=True)
    names = [l.split(":")[0] for l in r.stdout.splitlines() if l]
    sessions = ", ".join(names) if names else "none"
except: pass

version = "?"
try:
    v_file = os.path.expanduser("~/system/.version")
    version = open(v_file).read().strip()
except: pass

now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
hostname = os.environ.get("HOSTNAME", os.popen("hostname").read().strip())
user = os.environ.get("USER", "agent")

print("=== AGENT COMPUTER CONTEXT BRIEF ===")
print(f"Machine: {user}@{hostname} · v{version} · {now}")
if env.get("mission"):
    print(f"Mission: {env['mission']}")
print(f"Disk: {disk_free} free ({disk_pct} used) · Sessions: {sessions}")

if tasks_open:
    high = [t for t in tasks_open if t.get("priority") == "high"]
    print(f"\nOpen tasks ({len(tasks_open)} total{', ' + str(len(high)) + ' high priority' if high else ''}):")
    for t in tasks_open[:5]:
        pri = t.get("priority","")
        pri_tag = f" [{pri}]" if pri else ""
        print(f"  #{t['id']}{pri_tag} {t['desc']}")
    if len(tasks_open) > 5:
        print(f"  ... and {len(tasks_open)-5} more")
else:
    print("\nOpen tasks: none")

if plan_title:
    print(f"\nActive plan: {plan_title} ({plan_done} done · {plan_todo} remaining)")
    for step in plan_next:
        print(f"  → {step}")

if trace_recent:
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
    recent = [e for e in trace_recent if e.get("ts","") >= cutoff]
    if recent:
        print(f"\nRecent outcomes (last 7 days):")
        for e in reversed(recent[-5:]):
            outcome = e.get("outcome","?").upper()
            action = e.get("action","?")
            detail = e.get("detail","")
            ts = e.get("ts","")[:10]
            suffix = f" — {detail}" if detail else ""
            print(f"  {outcome}: {action}{suffix} ({ts})")

if budget_total is not None:
    print(f"\nBudget {budget_month}: ${budget_total:.4f} spent")

constraints = {k: v for k, v in env.items() if k.startswith("constraint")}
if env.get("risk") or constraints:
    print("\nConstraints:")
    if env.get("risk"):
        print(f"  - {env['risk']}")
    for v in constraints.values():
        print(f"  - {v}")

print("=== END BRIEF ===")
EOF
}

case "$cmd" in
  brief)
    _generate_brief
    ;;

  save)
    [ -z "$2" ] && { echo "Usage: ctx save <name>"; exit 1; }
    name="$2"
    outfile="$CTX_DIR/${name}.txt"
    _generate_brief > "$outfile"
    echo "  ✓  Context saved: ~/system/contexts/${name}.txt"
    ;;

  load)
    [ -z "$2" ] && { echo "Usage: ctx load <name>"; exit 1; }
    name="$2"
    f="$CTX_DIR/${name}.txt"
    [ ! -f "$f" ] && { echo "  (not found: $name)"; exit 1; }
    cat "$f"
    ;;

  list)
    files=$(ls "$CTX_DIR" 2>/dev/null)
    if [ -z "$files" ]; then
      echo "  (no saved contexts — create one with: ctx save <name>)"
      exit 0
    fi
    echo ""
    echo "  Saved contexts:"
    echo "  ──────────────────────────────────────────"
    while IFS= read -r f; do
      name="${f%.*}"
      ts=$(stat -c %y "$CTX_DIR/$f" 2>/dev/null | cut -d' ' -f1 || echo "?")
      echo "  $name  ($ts)"
    done <<< "$files"
    echo ""
    ;;

  del|delete|rm)
    [ -z "$2" ] && { echo "Usage: ctx del <name>"; exit 1; }
    f="$CTX_DIR/${2}.txt"
    [ ! -f "$f" ] && { echo "  (not found: $2)"; exit 1; }
    rm "$f"
    echo "  ✓  $2 deleted"
    ;;

  *)
    echo "Usage: ctx brief|save|load|list|del [args]"
    exit 1
    ;;
esac
