#!/bin/bash
# boot.sh — agent session startup
# Run 'boot' on arrival to orient yourself quickly

BOLD='\033[1m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

VERSION=$(cat "$HOME/system/.version" 2>/dev/null || echo "?")

echo -e "\n${BOLD}Agent Computer v${VERSION} — Session Start${NC}  $(date -u '+%Y-%m-%d %H:%M UTC')\n"

# ── Stamp session start for auto-brief ───────────────────────────────────────
CRON_AT_START=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l | tr -d ' ')
printf "ts=%s\ncron=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CRON_AT_START" > "$HOME/.session_start"

# ── Quick health pulse ────────────────────────────────────────────────────────
DISK_FREE=$(df -h "$HOME" | awk 'NR==2{print $4}')
DISK_PCT=$(df "$HOME" | awk 'NR==2{print $5}')
DISK_FREE_GB=$(df -BG "$HOME" | awk 'NR==2{gsub("G","",$4); print $4}')
TMUX_LIST=$(tmux ls 2>/dev/null | awk -F: '{print $1}' | tr '\n' ' ' | sed 's/ $//')
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
INBOX=$(ls "$HOME/inbox/"*.md 2>/dev/null | wc -l)
LAST_SYNC_TS=$(grep -o '\[.*\]' "$HOME/documents/sync.log" 2>/dev/null | tail -1 | tr -d '[]' || echo "never")

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
    # One-line summary: first non-empty, non-header line
    summary=$(grep -m1 "^[^#|*\-]" "$f" 2>/dev/null | head -c 120 || true)
    [ -z "$summary" ] && summary=$(grep -m1 "^\-" "$f" 2>/dev/null | sed 's/^- //' | head -c 120 || true)
    [ -z "$summary" ] && summary="(no summary)"
    echo "  ${name}: ${summary}"
  done
else
  echo "  Inbox:     empty"
fi

# ── Last changelog ────────────────────────────────────────────────────────────
echo -e "\n${BLUE}── Last 3 Changes${NC}"
if [ -f "$HOME/documents/changelog.md" ]; then
  grep "^-" "$HOME/documents/changelog.md" | tail -3 | sed 's/^/  /'
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
with open(sys.argv[1]) as f: d = json.load(f)
for t in d.get("tasks",[]):
    if t.get("status") == "open":
        print(f"  ○  #{t['id']}  {t['desc']}")
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

# ── Quick commands ────────────────────────────────────────────────────────────
echo -e "\n${BLUE}── Quick Commands${NC}"
echo "  check                  full health report"
echo "  task list              open work queue"
echo "  plan show              active session plan"
echo "  map                    refresh README.md"
echo "  note \"msg\"             leave a message for next agent"
echo "  cat ~/AGENT.md         full operating guide"
echo ""
