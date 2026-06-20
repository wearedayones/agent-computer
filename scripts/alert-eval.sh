#!/bin/bash
# alert-eval.sh — evaluate alert rules and write inbox notes on breach
# Cron: */5 * * * * bash ~/scripts/alert-eval.sh >> ~/system/alert-eval.log 2>&1
# Rules file: ~/system/alert-rules.json
# Rule format: {"id":1,"expr":"disk_used_pct > 90","action":"inbox","cooldown_h":24,"label":"Disk critical"}

RULES_FILE="$HOME/system/alert-rules.json"
COOLDOWN_FILE="$HOME/system/alert-cooldowns.json"
INBOX="$HOME/inbox"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

[ -f "$RULES_FILE" ] || exit 0

mkdir -p "$INBOX"

python3 - "$RULES_FILE" "$COOLDOWN_FILE" "$INBOX" "$HOME" "$NOW" <<'EOF'
import json, os, sys, re
from datetime import datetime, timezone, timedelta
from pathlib import Path

rules_file, cooldown_file, inbox_dir, home_s, now_s = sys.argv[1:6]
HOME = Path(home_s)
now = datetime.fromisoformat(now_s.replace("Z", "+00:00"))

# Load rules
try:
    rules = json.loads(Path(rules_file).read_text())
except:
    sys.exit(0)

# Load cooldowns
try:
    cooldowns = json.loads(Path(cooldown_file).read_text())
except:
    cooldowns = {}

# ── Collect live metrics for rule evaluation ──────────────────────────────────

def disk_used_pct():
    st = os.statvfs(HOME)
    return int(100 * (1 - st.f_bavail / st.f_blocks))

def disk_free_gb():
    st = os.statvfs(HOME)
    return round(st.f_bavail * st.f_frsize / 1e9, 1)

def budget_total():
    try:
        d = json.loads((HOME / "system/budget.json").read_text())
        month = now.strftime("%Y-%m")
        return sum(e.get("amount", 0) for e in d.get("entries", []) if e.get("month") == month)
    except:
        return 0

def errors_today(app_name):
    apps_dir = HOME / "apps"
    today = now.strftime("%Y-%m-%d")
    count = 0
    app_dir = apps_dir / app_name
    if not app_dir.exists():
        return 0
    for lf in app_dir.rglob("*.log"):
        try:
            for line in lf.read_text(errors="replace").splitlines():
                if today in line and re.search(r"\b(error|fail|exception)\b", line, re.I):
                    count += 1
        except:
            pass
    return count

def open_tasks():
    try:
        d = json.loads((HOME / "system/tasks.json").read_text())
        return len([t for t in d.get("tasks", []) if t.get("status") == "open"])
    except:
        return 0

# Safe evaluation context — only expose safe scalar functions
EVAL_CTX = {
    "disk_used_pct": disk_used_pct(),
    "disk_free_gb": disk_free_gb(),
    "budget_total": budget_total(),
    "open_tasks": open_tasks(),
}

# ── Evaluate each rule ────────────────────────────────────────────────────────

for rule in rules:
    rid = str(rule.get("id", ""))
    expr = rule.get("expr", "")
    label = rule.get("label", expr)
    cooldown_h = int(rule.get("cooldown_h", 4))
    action = rule.get("action", "inbox")

    # Substitute app-specific functions like errors_today(social-factory)
    def sub_func(m):
        fn, arg = m.group(1), m.group(2)
        if fn == "errors_today":
            return str(errors_today(arg))
        return "0"
    expr_eval = re.sub(r'(\w+)\("([^"]+)"\)', sub_func, expr)
    expr_eval = re.sub(r"(\w+)\('([^']+)'\)", sub_func, expr_eval)

    # Evaluate expression safely
    try:
        result = bool(eval(expr_eval, {"__builtins__": {}}, EVAL_CTX))
    except Exception as e:
        print(f"[alert-eval] rule {rid} eval error: {e}")
        continue

    if not result:
        continue  # condition not met

    # Check cooldown
    last_s = cooldowns.get(rid)
    if last_s:
        try:
            last = datetime.fromisoformat(last_s.replace("Z", "+00:00"))
            if (now - last) < timedelta(hours=cooldown_h):
                continue  # still in cooldown
        except:
            pass

    # Fire action
    if action == "inbox":
        ts = now.strftime("%Y%m%d-%H%M%S")
        msg = f"[ALERT] {label}\nExpr: {rule.get('expr','')}\nFired: {now_s}\n"
        Path(inbox_dir, f"{ts}-alert-{rid}.txt").write_text(msg)
        print(f"[alert-eval] FIRED rule {rid}: {label}")
    else:
        print(f"[alert-eval] unknown action '{action}' for rule {rid}")

    # Record firing time
    cooldowns[rid] = now_s

# Save updated cooldowns
Path(cooldown_file).write_text(json.dumps(cooldowns, indent=2))
EOF
