#!/bin/bash
# boot.sh — agent session startup
# Run 'boot' on arrival to orient yourself quickly

BOLD='\033[1m'; BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${BOLD}Agent Computer — Session Start${NC}  $(date -u '+%Y-%m-%d %H:%M UTC')\n"

# Quick health pulse
DISK_FREE=$(df -h /home/ubuntu | awk 'NR==2{print $4}')
DISK_PCT=$(df /home/ubuntu | awk 'NR==2{print $5}')
BYBIT=$(tmux has-session -t persistent-agent 2>/dev/null && echo "running" || echo "STOPPED")
INBOX=$(ls /home/ubuntu/inbox/*.md 2>/dev/null | wc -l)

echo -e "${BLUE}── Pulse${NC}"
echo "  Disk:      $DISK_FREE free ($DISK_PCT used)"
echo "  bybit-bot: $BYBIT"

# Inbox
if [ "$INBOX" -gt 0 ]; then
  echo -e "\n${YELLOW}── Inbox ($INBOX message(s))${NC}"
  for f in /home/ubuntu/inbox/*.md; do
    echo "  $(basename $f):"
    cat "$f" | sed 's/^/    /'
  done
else
  echo "  Inbox:     empty"
fi

# Last changelog
echo -e "\n${BLUE}── Last 3 Changes${NC}"
if [ -f /home/ubuntu/documents/changelog.md ]; then
  grep "^-" /home/ubuntu/documents/changelog.md | tail -3 | sed 's/^/  /'
else
  echo "  (no changelog yet)"
fi

# Quick command reference
echo -e "\n${BLUE}── Quick Commands${NC}"
echo "  check              full health report"
echo "  map                refresh README.md"
echo "  run <ch> short     upload a Short now"
echo "  run <ch> long 1900 schedule long video at 19:00 UTC"
echo "  note \"msg\"         leave a message for next agent"
echo "  cat ~/AGENT.md     full operating guide"
echo ""
