#!/bin/bash
# boot.sh — agent session startup
# Run 'boot' on arrival to orient yourself quickly

BOLD='\033[1m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

VERSION=$(cat "$HOME/system/.version" 2>/dev/null || echo "?")

echo -e "\n${BOLD}Agent Computer v${VERSION} — Session Start${NC}  $(date -u '+%Y-%m-%d %H:%M UTC')\n"

# ── Stamp session start for auto-brief ───────────────────────────────────────
CRON_AT_START=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l | tr -d ' ')
printf "ts=%s\ncron=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CRON_AT_START" > "$HOME/.session_start"

# ── Machine mission (env) ─────────────────────────────────────────────────────
ENV_FILE="$HOME/system/env.json"
if [ -f "$ENV_FILE" ]; then
  MISSION=$(python3 -c "
import json
with open('$ENV_FILE') as f: d=json.load(f)
m=d.get('mission','')
if m: print(m)
" 2>/dev/null)
  if [ -n "$MISSION" ]; then
    echo -e "${BLUE}Mission:${NC} $MISSION\n"
  fi
fi

# ── Quick health pulse ────────────────────────────────────────────────────────
DISK_FREE=$(df -h "$HOME" | awk 'NR==2{print $4}')
DISK_PCT=$(df "$HOME" | awk 'NR==2{print $5}')
DISK_FREE_GB=$(df -BG "$HOME" | awk 'NR==2{gsub("G","",$4); print $4}')
TMUX_LIST=$(tmux ls 2>/dev/null | awk -F: '{print $1}' | tr '\n' ' ' | sed 's/ $//')
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
INBOX=$(ls "$HOME/inbox/"*.md 2>/dev/null | wc -l)
LAST_SYNC_TS=$(grep -o '\[.*\]' "$HOME/documents/sync.log" 2>/dev/null | tail -1 | tr -d '[]')
[ -z "$LAST_SYNC_TS" ] && LAST_SYNC_TS="not configured"

echo -e "${BLUE}── Pulse${NC}"

# Disk with color
if [ "${DISK_FREE_GB:-99}" -lt 2 ] 2>/dev/null; then
  echo -e "  Disk:      ${RED}${DISK_FREE} free (${DISK_PCT} used) — CRITICAL${NC}"
elif [ "${DISK_FREE_GB:-99}" -lt 4 ] 2>/dev/null; then
  echo -e "  Disk:      ${YELLOW}${DISK_FREE} free (${DISK_PCT} used) — low${NC}"
else
  echo "  Disk:      $DISK_FREE free ($DISK_PCT used)"
fi

# Tmux sessions
if [ -n "$TMUX_LIST" ]; then
  echo -e "  Sessions:  ${GREEN}$TMUX_LIST${NC}"
else
  echo "  Sessions:  none"
fi

echo "  Cron:      $CRON_COUNT active jobs"
echo "  Last sync: $LAST_SYNC_TS"

# ── Inbox ─────────────────────────────────────────────────────────────────────
if [ "$INBOX" -gt 0 ]; then
  echo -e "\n${YELLOW}── Inbox ($INBOX message(s)) — read with: cat ~/inbox/<file>${NC}"
  for f in "$HOME/inbox/"*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    summary=$(grep -m1 "^[^#|*\-]" "$f" 2>/dev/null | head -c 120 || true)
    [ -z "$summary" ] && summary=$(grep -m1 "^\-" "$f" 2>/dev/null | sed 's/^- //' | head -c 120 || true)
    [ -z "$summary" ] && summary="(no summary)"
    echo "  ${name}: ${summary}"
  done
else
  echo "  Inbox:     empty"
fi

# ── Recent failures from trace (last 7 days) ──────────────────────────────────
TRACE_FILE="$HOME/system/trace.jsonl"
if [ -f "$TRACE_FILE" ]; then
  python3 - "$TRACE_FILE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
YELLOW, RED, NC = "\033[1;33m", "\033[0;31m", "\033[0m"
cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
try:
    lines = open(sys.argv[1]).readlines()
    entries = []
    for l in lines:
        l = l.strip()
        if l:
            try: entries.append(json.loads(l))
            except: pass
    failures = [e for e in entries if e.get("outcome") == "fail" and e.get("ts","") >= cutoff]
    if failures:
        print(f"\n{RED}── Recent Failures (last 7 days){NC}")
        for e in failures[-3:]:
            ts = e.get("ts","")[:10]
            detail = e.get("detail","")
            suffix = f" — {detail}" if detail else ""
            print(f"  ✗  {ts}  {e.get('action','?')}{suffix}")
        if len(failures) > 3:
            print(f"  ... and {len(failures)-3} more — run: trace search --outcome fail")
except: pass
PYEOF
fi

# ── Secret expiry warnings ────────────────────────────────────────────────────
META_FILE="$HOME/keys/.meta.json"
if [ -f "$META_FILE" ]; then
  python3 - "$META_FILE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta
YELLOW, NC = "\033[1;33m", "\033[0m"
try:
    with open(sys.argv[1]) as f: meta = json.load(f)
    now = datetime.now(timezone.utc)
    warn_dt = now + timedelta(days=14)
    expiring = []
    for name, m in meta.items():
        expires = m.get("expires","")
        if not expires: continue
        try:
            exp_dt = datetime.fromisoformat(expires)
            if exp_dt.tzinfo is None: exp_dt = exp_dt.replace(tzinfo=timezone.utc)
            if exp_dt < warn_dt:
                expiring.append((name, expires, exp_dt < now))
        except: pass
    if expiring:
        print(f"\n{YELLOW}── Secret Warnings{YELLOW}")
        for name, exp, is_expired in expiring:
            label = "EXPIRED" if is_expired else f"expires {exp}"
            print(f"  ⚠  {name}: {label}")
        print(f"\033[0m", end="")
except: pass
PYEOF
fi

# ── Budget threshold warnings ─────────────────────────────────────────────────
BUDGET_FILE="$HOME/system/budget.json"
if [ -f "$BUDGET_FILE" ]; then
  python3 - "$BUDGET_FILE" <<'PYEOF'
import json, sys
from datetime import datetime, timezone
YELLOW, NC = "\033[1;33m", "\033[0m"
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    thresholds = d.get("thresholds", {})
    if not thresholds: sys.exit(0)
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    entries = [e for e in d.get("entries",[]) if e.get("month","") == month]
    total = sum(e["amount"] for e in entries)
    warnings = []
    if "total" in thresholds and total > float(thresholds["total"]):
        warnings.append(f"total ${total:.2f} exceeds threshold ${thresholds['total']:.2f}")
    for cat, thresh in thresholds.items():
        if cat == "total": continue
        cat_total = sum(e["amount"] for e in entries if e.get("category","") == cat)
        if cat_total > float(thresh):
            warnings.append(f"{cat} ${cat_total:.2f} exceeds ${thresh:.2f}")
    if warnings:
        print(f"\n{YELLOW}── Budget Warnings{NC}")
        for w in warnings:
            print(f"  ⚠  {w}")
except: pass
PYEOF
fi

# ── Last changelog (skip relocator noise) ────────────────────────────────────
echo -e "\n${BLUE}── Last 3 Changes${NC}"
if [ -f "$HOME/documents/changelog.md" ]; then
  CHANGES=$(grep "^-" "$HOME/documents/changelog.md" 2>/dev/null | grep -v "Auto-relocated" | tail -3)
  [ -n "$CHANGES" ] && echo "$CHANGES" | sed 's/^/  /' || echo "  (no meaningful changes yet)"
else
  echo "  (no changelog yet)"
fi

# ── Open Tasks ────────────────────────────────────────────────────────────────
TASKS_FILE="$HOME/system/tasks.json"
if [ -f "$TASKS_FILE" ]; then
  OPEN_COUNT=$(python3 -c "
import json
with open('$TASKS_FILE') as f: d=json.load(f)
print(len([t for t in d.get('tasks',[]) if t.get('status')=='open']))
" 2>/dev/null || echo 0)
  if [ "$OPEN_COUNT" -gt 0 ]; then
    echo -e "\n${YELLOW}── Open Tasks ($OPEN_COUNT)${NC}"
    python3 - "$TASKS_FILE" <<'PYEOF'
import json, sys
RED, YELLOW, GREY, NC = "\033[0;31m", "\033[1;33m", "\033[90m", "\033[0m"
pri_colors = {"high": RED, "medium": YELLOW, "low": GREY}
with open(sys.argv[1]) as f: d = json.load(f)
for t in d.get("tasks",[]):
    if t.get("status") == "open":
        pri = t.get("priority","medium")
        pc = pri_colors.get(pri, YELLOW)
        agent_str = f" [{t['agent']}]" if t.get("agent") else ""
        print(f"  ○  {pc}[{pri}]{NC}  #{t['id']}  {t['desc']}{agent_str}")
PYEOF
  fi
fi

# ── Active Plan ───────────────────────────────────────────────────────────────
PLAN_FILE="$HOME/system/plan.md"
if [ -f "$PLAN_FILE" ]; then
  PLAN_TITLE=$(head -1 "$PLAN_FILE" | sed 's/^# Plan: //')
  DONE_COUNT=$(grep "\[x\]" "$PLAN_FILE" 2>/dev/null | wc -l | tr -d ' ')
  TODO_COUNT=$(grep "\[ \]" "$PLAN_FILE" 2>/dev/null | wc -l | tr -d ' ')
  echo -e "\n${BLUE}── Active Plan${NC}"
  echo "  $PLAN_TITLE  ($DONE_COUNT done · $TODO_COUNT remaining)"
  grep "^\- \[ \]" "$PLAN_FILE" | head -3 | sed 's/^- \[ \] /  ○  /'
fi

# ── Skills available ──────────────────────────────────────────────────────────
SKILLS_DIR="$HOME/skills"
if [ -d "$SKILLS_DIR" ]; then
  SKILL_COUNT=$(ls "$SKILLS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "${SKILL_COUNT:-0}" -gt 0 ]; then
    echo -e "\n${BLUE}── Skills${NC}"
    echo "  $SKILL_COUNT skill(s) available — run: skill list"
  fi
fi

# ── Quick commands ────────────────────────────────────────────────────────────
echo -e "\n${BLUE}── Quick Commands${NC}"
echo "  ctx brief              paste-ready session brief for any LLM"
echo "  trace last             recent outcomes (what worked / what failed)"
echo "  env show               machine mission + constraints"
echo "  task list              open work queue"
echo "  plan show              active session plan"
echo "  check                  full health report"
echo "  map                    refresh README.md"
echo "  note \"msg\"             leave a message for next agent"
echo ""
