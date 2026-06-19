#!/bin/bash
# health.sh — full agent computer status report
# Usage: check   (via ~/bin/check shortcut)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }
section() { echo -e "\n${BOLD}${BLUE}── $1${NC}"; }

VERSION=$(cat /home/ubuntu/system/.version 2>/dev/null || echo "unknown")
echo -e "${BOLD}Agent Computer v${VERSION} — Health Report${NC}"
echo "$(date -u '+%Y-%m-%d %H:%M UTC')"

# ── Disk ──────────────────────────────────────────────────────────────────────
section "Disk"
DISK_FREE_GB=$(df -BG /home/ubuntu | awk 'NR==2{gsub("G","",$4); print $4}')
DISK_PCT=$(df /home/ubuntu | awk 'NR==2{print $5}')
DISK_FREE=$(df -h /home/ubuntu | awk 'NR==2{print $4}')
if [ "${DISK_FREE_GB:-99}" -lt 2 ] 2>/dev/null; then
  fail "Only ${DISK_FREE} free (${DISK_PCT} used) — CRITICAL: clear downloads/ or node_modules/"
elif [ "${DISK_FREE_GB:-99}" -lt 4 ] 2>/dev/null; then
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
  fail "bybit-bot — STOPPED  →  tmux new-session -d -s persistent-agent '~/.bybit/persistent_agent.sh'"
fi

# social-factory
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
  warn "telegram — not running (start manually if needed)"
fi

# GitHub backup sync
section "GitHub Sync"
SYNC_LOG="/home/ubuntu/documents/sync.log"
if [ -f "$SYNC_LOG" ]; then
  LAST_PUSH=$(grep "Pushed" "$SYNC_LOG" | tail -1)
  LAST_LINE=$(tail -1 "$SYNC_LOG")
  LAST_TS=$(grep -o '\[.*\]' "$SYNC_LOG" | tail -1 | tr -d '[]')
  if [ -n "$LAST_PUSH" ]; then
    ok "Last push: $LAST_TS"
    echo "      $(echo "$LAST_PUSH" | sed 's/\[.*\] //')"
  elif grep -q "No changes" "$SYNC_LOG"; then
    ok "Last sync: $LAST_TS — no changes (up to date)"
  else
    warn "Sync log exists but no successful push found"
    echo "      Last line: $LAST_LINE"
  fi
else
  warn "No sync log — run: bash ~/scripts/vps-sync.sh  (or check crontab)"
fi

# ── YouTube Channels ──────────────────────────────────────────────────────────
section "YouTube Channels"
SF="/home/ubuntu/apps/social-factory"
if [ -d "$SF/channels" ]; then
  for slug in "$SF/channels"/*/; do
    [ -d "$slug" ] || continue
    slug=$(basename "$slug")
    LOG="$SF/channels/$slug/state/pipeline.log"
    TOKEN="$SF/tokens/$slug-youtube.json"
    LAST_STATUS=$(grep "=== .* end " "$LOG" 2>/dev/null | tail -1 | grep -o "exit [0-9]*" | awk '{print $2}' || echo "")
    LAST_RUN=$(grep "=== .* start " "$LOG" 2>/dev/null | tail -1 | sed 's/=== //' | sed 's/ start.*//' || echo "never")
    TOKEN_OK=$([ -f "$TOKEN" ] && echo "yes" || echo "MISSING")

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
else
  warn "social-factory channels not found at $SF/channels"
fi

# ── Python Venvs ──────────────────────────────────────────────────────────────
section "Python Venvs"
venv_found=0

# Check ~/apps/envs/ (primary location)
ENVS_DIR="/home/ubuntu/apps/envs"
if [ -d "$ENVS_DIR" ]; then
  for v in "$ENVS_DIR"/*/; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    if [ -f "$v/bin/python3" ]; then
      ok "$name  ($ENVS_DIR/$name)"
      venv_found=$((venv_found+1))
    else
      fail "$name — broken (no python3 binary)"
    fi
  done
fi

# Check legacy venv paths (may be symlinks pointing to ~/apps/envs/)
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  path="/home/ubuntu/$v"
  [ -e "$path" ] || continue
  if [ -L "$path" ]; then
    target=$(readlink -f "$path")
    ok "$v → $target  (symlink)"
    venv_found=$((venv_found+1))
  elif [ -f "$path/bin/python3" ]; then
    ok "$v  (legacy path)"
    venv_found=$((venv_found+1))
  else
    fail "$v — broken"
  fi
done

[ "$venv_found" -eq 0 ] && warn "No Python venvs found (check ~/apps/envs/)"

# ── API Keys ──────────────────────────────────────────────────────────────────
section "API Keys"
KEY_DIR="/home/ubuntu/keys"
if [ -d "$KEY_DIR" ]; then
  KEY_COUNT=0
  MISSING_COUNT=0
  for f in "$KEY_DIR"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if [ -s "$f" ]; then
      ok "$name"
      KEY_COUNT=$((KEY_COUNT+1))
    else
      fail "$name — empty file"
      MISSING_COUNT=$((MISSING_COUNT+1))
    fi
  done
  [ "$KEY_COUNT" -eq 0 ] && warn "No key files found in ~/keys/"
else
  warn "~/keys/ directory not found"
fi

# ── Root Cleanliness ──────────────────────────────────────────────────────────
section "Root Cleanliness"
ALLOWED="AGENT.md CLAUDE.md README.md apps archive bin documents downloads inbox keys legal media projects renderer scripts snap system tg-agent-env venv yt-upload-venv antigravity-bot-venv"
CLUTTER=""
for item in /home/ubuntu/* /home/ubuntu/.[^.]*; do
  [ -e "$item" ] || continue
  name=$(basename "$item")
  [[ "$name" == .* ]] && continue
  echo "$ALLOWED" | grep -qw "$name" || CLUTTER+="$name "
done
CLUTTER=$(echo "$CLUTTER" | xargs)
if [ -z "$CLUTTER" ]; then
  ok "Root is clean — no clutter"
else
  fail "Root clutter: $CLUTTER — move to correct zone then run: map"
fi

# ── Inbox ─────────────────────────────────────────────────────────────────────
section "Inbox"
NOTES=$(ls /home/ubuntu/inbox/*.md 2>/dev/null | wc -l)
if [ "$NOTES" -gt 0 ]; then
  warn "$NOTES note(s) from previous agents:"
  for f in /home/ubuntu/inbox/*.md; do
    [ -f "$f" ] || continue
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
