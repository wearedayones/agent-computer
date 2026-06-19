#!/bin/bash
# boot.sh — agent session startup
# Run 'boot' on arrival to orient yourself quickly

BOLD='\033[1m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

VERSION=$(cat /home/ubuntu/system/.version 2>/dev/null || echo "?")

echo -e "\n${BOLD}Agent Computer v${VERSION} — Session Start${NC}  $(date -u '+%Y-%m-%d %H:%M UTC')\n"

# ── Quick health pulse ────────────────────────────────────────────────────────
DISK_FREE=$(df -h /home/ubuntu | awk 'NR==2{print $4}')
DISK_PCT=$(df /home/ubuntu | awk 'NR==2{print $5}')
DISK_FREE_GB=$(df -BG /home/ubuntu | awk 'NR==2{gsub("G","",$4); print $4}')
TMUX_LIST=$(tmux ls 2>/dev/null | awk -F: '{print $1}' | tr '\n' ' ' | sed 's/ $//')
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
INBOX=$(ls /home/ubuntu/inbox/*.md 2>/dev/null | wc -l)
LAST_SYNC_TS=$(grep -o '\[.*\]' /home/ubuntu/documents/sync.log 2>/dev/null | tail -1 | tr -d '[]' || echo "never")

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
  echo -e "\n${YELLOW}── Inbox ($INBOX message(s))${NC}"
  for f in /home/ubuntu/inbox/*.md; do
    [ -f "$f" ] || continue
    echo "  $(basename $f):"
    cat "$f" | sed 's/^/    /'
  done
else
  echo "  Inbox:     empty"
fi

# ── Last changelog ────────────────────────────────────────────────────────────
echo -e "\n${BLUE}── Last 3 Changes${NC}"
if [ -f /home/ubuntu/documents/changelog.md ]; then
  grep "^-" /home/ubuntu/documents/changelog.md | tail -3 | sed 's/^/  /'
else
  echo "  (no changelog yet)"
fi

# ── Quick commands ────────────────────────────────────────────────────────────
echo -e "\n${BLUE}── Quick Commands${NC}"
echo "  check                  full health report"
echo "  map                    refresh README.md"
echo "  update                 pull latest from GitHub"
echo "  note \"msg\"             leave a message for next agent"
echo "  export --include-secrets  package VPS for migration"
echo "  cat ~/AGENT.md         full operating guide"
echo ""
