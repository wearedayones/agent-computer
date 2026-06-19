#!/bin/bash
# health.sh — full agent computer status report
# Usage: check   (via ~/bin/check shortcut)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
section() { echo -e "\n${BOLD}${BLUE}── $1${NC}"; }

echo -e "${BOLD}Agent Computer — Health Report${NC}"
echo "$(date -u '+%Y-%m-%d %H:%M UTC')"

# ── Disk ──────────────────────────────────────────────────────────────────────
section "Disk"
DISK_FREE_GB=$(df -BG /home/ubuntu | awk 'NR==2{gsub("G","",$4); print $4}')
DISK_PCT=$(df /home/ubuntu | awk 'NR==2{print $5}')
DISK_FREE=$(df -h /home/ubuntu | awk 'NR==2{print $4}')
if [ "$DISK_FREE_GB" -lt 2 ]; then
  fail "Only ${DISK_FREE} free (${DISK_PCT} used) — CRITICAL"
elif [ "$DISK_FREE_GB" -lt 4 ]; then
  warn "${DISK_FREE} free (${DISK_PCT} used) — getting low"
else
  ok "${DISK_FREE} free (${DISK_PCT} used)"
fi

# ── Apps ──────────────────────────────────────────────────────────────────────
section "Apps"

# bybit-bot
if tmux has-session -t persistent-agent 2>/dev/null; then
  ok "bybit-bot — running (tmux: persistent-agent)"
else
  fail "bybit-bot — NOT running (restart: tmux new-session -d -s persistent-agent '~/.bybit/persistent_agent.sh')"
fi

# social-factory crons
CRON_COUNT=$(crontab -l 2>/dev/null | grep "social-factory" | grep -v "^#" | wc -l)
if [ "$CRON_COUNT" -gt 0 ]; then
  ok "social-factory — $CRON_COUNT cron jobs active"
else
  fail "social-factory — no cron jobs found"
fi

# telegram
if pgrep -f "alex.py\|antigravity_bot" &>/dev/null; then
  ok "telegram — running"
else
  warn "telegram — not running (manual start if needed)"
fi

# ── YouTube Channels ──────────────────────────────────────────────────────────
section "YouTube Channels"
SF="/home/ubuntu/apps/social-factory"
for slug in aura-clips crvgrowth curiosity-files; do
  LOG="$SF/channels/$slug/state/pipeline.log"
  TOKEN="$SF/tokens/$slug-youtube.json"
  LAST_STATUS=$(grep "=== .* end " "$LOG" 2>/dev/null | tail -1 | grep -o "exit [0-9]*" | awk '{print $2}' || echo "")
  LAST_RUN=$(grep "=== .* start " "$LOG" 2>/dev/null | tail -1 | sed 's/=== //' | sed 's/ start.*//' || echo "never")
  TOKEN_OK=$( [ -f "$TOKEN" ] && echo "yes" || echo "MISSING" )

  if [ "$TOKEN_OK" = "MISSING" ]; then
    fail "$slug — token MISSING"
  elif [ "$LAST_STATUS" = "0" ]; then
    ok "$slug — last run OK · $LAST_RUN"
  elif [ -z "$LAST_STATUS" ]; then
    warn "$slug — no runs recorded yet · token OK"
  else
    fail "$slug — last run FAILED · $LAST_RUN"
  fi
done

# ── Venvs ─────────────────────────────────────────────────────────────────────
section "Python Venvs"
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  if [ -f "/home/ubuntu/$v/bin/python3" ]; then
    ok "$v"
  else
    fail "$v — MISSING"
  fi
done

# ── API Keys ──────────────────────────────────────────────────────────────────
section "API Keys"
KEY_DIR="/home/ubuntu/keys"
declare -A KEYS=(
  ["google_api_key.txt"]="YouTube Data API v3"
  ["freesound.json"]="FreeSound audio"
  ["github_token.txt"]="GitHub API"
  ["pixabay.txt"]="Pixabay images"
  ["tiktok.json"]="TikTok Content API"
  ["tiktok_token.json"]="TikTok OAuth token"
)
for fname in "${!KEYS[@]}"; do
  label="${KEYS[$fname]}"
  if [ -f "$KEY_DIR/$fname" ] && [ -s "$KEY_DIR/$fname" ]; then
    ok "$label ($fname)"
  else
    fail "$label ($fname) — MISSING or empty"
  fi
done

# ── Root Cleanliness ──────────────────────────────────────────────────────────
section "Root Cleanliness"
ALLOWED="AGENT.md CLAUDE.md README.md apps archive bin documents downloads inbox keys legal media projects renderer scripts snap system tg-agent-env venv yt-upload-venv antigravity-bot-venv"
CLUTTER=""
for item in /home/ubuntu/* /home/ubuntu/.[^.]*; do
  name=$(basename "$item")
  [[ "$name" == .* ]] && continue
  echo "$ALLOWED" | grep -qw "$name" || CLUTTER+="$name "
done
if [ -z "$(echo $CLUTTER | xargs)" ]; then
  ok "Root is clean — no clutter"
else
  fail "Root clutter detected: $CLUTTER"
fi

# ── Inbox ─────────────────────────────────────────────────────────────────────
section "Inbox"
NOTES=$(ls /home/ubuntu/inbox/*.md 2>/dev/null | wc -l)
if [ "$NOTES" -gt 0 ]; then
  warn "$NOTES note(s) from previous agents:"
  for f in /home/ubuntu/inbox/*.md; do
    echo "    $(basename $f): $(tail -1 $f)"
  done
else
  ok "No messages"
fi

# ── Recent Activity ───────────────────────────────────────────────────────────
section "Recent Activity (last 5 changelog entries)"
if [ -f /home/ubuntu/documents/changelog.md ]; then
  grep "^-" /home/ubuntu/documents/changelog.md | tail -5 | sed 's/^/    /'
else
  echo "  (no changelog yet)"
fi

echo -e "\n${BOLD}Run 'map' to refresh README · 'note \"msg\"' to leave a message${NC}\n"
