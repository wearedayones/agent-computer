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

# ── Tmux Sessions ─────────────────────────────────────────────────────────────
section "Running Sessions (tmux)"
TMUX_OUT=$(tmux ls 2>/dev/null || echo "")
if [ -n "$TMUX_OUT" ]; then
  while IFS= read -r line; do
    ok "$line"
  done <<< "$TMUX_OUT"
else
  warn "No tmux sessions running"
fi

# ── Cron ──────────────────────────────────────────────────────────────────────
section "Cron Jobs"
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
if [ "$CRON_COUNT" -gt 0 ]; then
  ok "$CRON_COUNT active cron jobs"
else
  warn "No cron jobs found — run: crontab -e"
fi

# ── GitHub Sync ───────────────────────────────────────────────────────────────
section "GitHub Sync"
SYNC_LOG="/home/ubuntu/documents/sync.log"
if [ -f "$SYNC_LOG" ]; then
  LAST_PUSH=$(grep "Pushed" "$SYNC_LOG" | tail -1)
  LAST_TS=$(grep -o '\[.*\]' "$SYNC_LOG" | tail -1 | tr -d '[]')
  if [ -n "$LAST_PUSH" ]; then
    ok "Last push: $LAST_TS"
  elif grep -q "No changes" "$SYNC_LOG"; then
    ok "Last sync: $LAST_TS — no changes (up to date)"
  else
    warn "Sync log exists but no successful push recorded"
  fi
else
  warn "No sync log — see ~/scripts/vps-sync.sh for setup"
fi

# ── Python Venvs ──────────────────────────────────────────────────────────────
section "Python Venvs"
venv_found=0
ENVS_DIR="/home/ubuntu/apps/envs"

if [ -d "$ENVS_DIR" ]; then
  for v in "$ENVS_DIR"/*/; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    if [ -f "$v/bin/python3" ]; then
      ok "$name"
      venv_found=$((venv_found+1))
    else
      fail "$name — broken (no python3 binary)"
    fi
  done
fi

# Legacy venv paths (may be symlinks)
for v in /home/ubuntu/venv /home/ubuntu/yt-upload-venv /home/ubuntu/tg-agent-env /home/ubuntu/antigravity-bot-venv; do
  [ -e "$v" ] || continue
  name=$(basename "$v")
  if [ -L "$v" ]; then
    target=$(readlink -f "$v")
    ok "$name → $target  (symlink)"
    venv_found=$((venv_found+1))
  elif [ -f "$v/bin/python3" ]; then
    ok "$name  (legacy path)"
    venv_found=$((venv_found+1))
  fi
done

[ "$venv_found" -eq 0 ] && warn "No Python venvs found (expected in ~/apps/envs/)"

# ── API Keys ──────────────────────────────────────────────────────────────────
section "API Keys"
KEY_DIR="/home/ubuntu/keys"
if [ -d "$KEY_DIR" ]; then
  key_count=0
  for f in "$KEY_DIR"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if [ -s "$f" ]; then
      ok "$name"
      key_count=$((key_count+1))
    else
      fail "$name — empty"
    fi
  done
  [ "$key_count" -eq 0 ] && warn "No key files in ~/keys/"
else
  warn "~/keys/ not found"
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
  ok "Root is clean"
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
