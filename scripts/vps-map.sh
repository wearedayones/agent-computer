#!/bin/bash
# vps-map.sh — Regenerates ~/README.md from live system state.
# Runs automatically hourly via cron and after each pipeline run.
# Safe to call anytime: read-only except writing ~/README.md.

set -euo pipefail

HOME_DIR="/home/ubuntu"
SF_DIR="$HOME_DIR/apps/social-factory"
README="$HOME_DIR/README.md"
NOW_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOW_HUMAN=$(date -u "+%Y-%m-%d %H:%M UTC")

# ── helpers ──────────────────────────────────────────────────────────────────

json_field() { python3 -c "import sys,json; d=json.load(open('$1')); print(d.get('$2',''))" 2>/dev/null || echo ""; }

last_upload() {
  local f="$SF_DIR/channels/$1/state/uploads.jsonl"
  [ -f "$f" ] || { echo "none"; return; }
  tail -1 "$f" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('url','') or d.get('video_id','none'))" 2>/dev/null || echo "none"
}

last_run_ts() {
  local f="$SF_DIR/channels/$1/state/pipeline.log"
  [ -f "$f" ] || { echo "never"; return; }
  grep "=== .* start " "$f" 2>/dev/null | tail -1 | sed 's/=== //' | sed 's/ start.*//' || echo "never"
}

last_run_status() {
  local f="$SF_DIR/channels/$1/state/pipeline.log"
  [ -f "$f" ] || { echo "unknown"; return; }
  grep "=== .* end " "$f" 2>/dev/null | tail -1 | grep -o "exit [0-9]*" | awk '{print ($2=="0")?"ok":"FAILED"}' || echo "unknown"
}

token_ok() { [ -f "$SF_DIR/tokens/$1" ] && echo "present" || echo "MISSING"; }

app_health() {
  case "$1" in
    bybit)          tmux has-session -t persistent-agent 2>/dev/null && echo "running" || echo "STOPPED" ;;
    social-factory) crontab -l 2>/dev/null | grep -q "social-factory" && echo "scheduled" || echo "no-crons" ;;
    telegram)       pgrep -f "alex.py\|antigravity_bot" &>/dev/null && echo "running" || echo "stopped" ;;
  esac
}

# ── collect live data ─────────────────────────────────────────────────────────

DISK_TOTAL=$(df -h "$HOME_DIR" | awk 'NR==2{print $2}')
DISK_USED=$(df -h "$HOME_DIR" | awk 'NR==2{print $3}')
DISK_FREE=$(df -h "$HOME_DIR" | awk 'NR==2{print $4}')
DISK_PCT=$(df "$HOME_DIR" | awk 'NR==2{print $5}')
DISK_FREE_GB=$(df -BG "$HOME_DIR" | awk 'NR==2{gsub("G","",$4); print $4}')
DISK_STATUS="ok"
[ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null && DISK_STATUS="LOW — clear ~/downloads/ or ~/archive/"

TMUX_LIST=$(tmux ls 2>/dev/null || echo "none")
TMUX_SESSIONS=$(echo "$TMUX_LIST" | awk -F: '{print $1}' | tr '\n' ',' | sed 's/,$//')
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)

HEALTH_SF=$(app_health social-factory)
HEALTH_BYBIT=$(app_health bybit)
HEALTH_TG=$(app_health telegram)

# GitHub sync status
LAST_SYNC_LINE=$(grep "Pushed\|No changes" "$HOME_DIR/documents/sync.log" 2>/dev/null | tail -1 || echo "")
LAST_SYNC_TS=$(grep -o '\[.*\]' "$HOME_DIR/documents/sync.log" 2>/dev/null | tail -1 | tr -d '[]' || echo "never")
SYNC_STATUS="unknown"
[ -n "$LAST_SYNC_LINE" ] && SYNC_STATUS="ok ($LAST_SYNC_TS)"

# Root clutter check
ALLOWED_ROOT="AGENT.md CLAUDE.md README.md apps archive bin documents downloads inbox keys legal media projects renderer scripts snap system venv yt-upload-venv tg-agent-env antigravity-bot-venv"
ROOT_CLUTTER=""
for item in /home/ubuntu/*/; do
  name=$(basename "$item")
  echo "$ALLOWED_ROOT" | grep -qw "$name" || ROOT_CLUTTER+="$name "
done
for item in /home/ubuntu/*; do
  name=$(basename "$item")
  [[ "$name" == *.md ]] && continue
  [[ -d "$item" ]] && continue
  echo "$ALLOWED_ROOT" | grep -qw "$name" || ROOT_CLUTTER+="$name "
done
ROOT_CLUTTER=$(echo "$ROOT_CLUTTER" | xargs)

# Collect channel data dynamically
declare -A CH_NICHE CH_THEME CH_RUN CH_STATUS CH_UPLOAD CH_TOKEN
CHANNELS=()
if [ -d "$SF_DIR/channels" ]; then
  for ch in "$SF_DIR/channels"/*/; do
    [ -d "$ch" ] || continue
    slug=$(basename "$ch")
    CHANNELS+=("$slug")
    cfg="$SF_DIR/channels/$slug/config.json"
    CH_NICHE[$slug]=$(json_field "$cfg" "niche")
    CH_THEME[$slug]=$(json_field "$cfg" "video_theme")
    CH_RUN[$slug]=$(last_run_ts "$slug")
    CH_STATUS[$slug]=$(last_run_status "$slug")
    CH_UPLOAD[$slug]=$(last_upload "$slug")
    CH_TOKEN[$slug]=$(token_ok "$slug-youtube.json")
  done
fi

# Venv inventory
VENVS_JSON="["
ENVS_DIR="$HOME_DIR/apps/envs"
if [ -d "$ENVS_DIR" ]; then
  for v in "$ENVS_DIR"/*/; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    if [ -f "$v/bin/python3" ]; then
      VENVS_JSON+="\"$name\","
    else
      VENVS_JSON+="\"${name}(BROKEN)\","
    fi
  done
fi
# Legacy venv paths
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  path="$HOME_DIR/$v"
  [ -e "$path" ] || continue
  if [ -L "$path" ]; then
    VENVS_JSON+="\"$v→symlink\","
  elif [ -f "$path/bin/python3" ]; then
    VENVS_JSON+="\"$v\","
  fi
done
VENVS_JSON="${VENVS_JSON%,}]"

# Alerts
ATTENTION=""
for slug in "${CHANNELS[@]}"; do
  [ "${CH_STATUS[$slug]:-}" = "FAILED" ] && ATTENTION+="- social-factory/$slug last run FAILED\n"
  [ "${CH_TOKEN[$slug]:-}" = "MISSING" ] && ATTENTION+="- social-factory/$slug YouTube token MISSING\n"
done
[ "$HEALTH_BYBIT" = "STOPPED" ] && ATTENTION+="- bybit-bot (persistent-agent) is NOT running\n"
[ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null && ATTENTION+="- DISK LOW: only ${DISK_FREE_GB}GB free\n"
[ -n "$ROOT_CLUTTER" ] && ATTENTION+="- ROOT CLUTTER: $ROOT_CLUTTER — move to correct zone\n"
[ -z "$ATTENTION" ] && ATTENTION="None — all systems nominal"

PROJECTS=$(ls "$HOME_DIR/projects/" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "none")
VERSION=$(cat "$HOME_DIR/system/.version" 2>/dev/null || echo "unknown")

# ── build channel table rows ──────────────────────────────────────────────────
CHANNEL_TABLE_ROWS=""
for slug in "${CHANNELS[@]}"; do
  CHANNEL_TABLE_ROWS+="| $slug | ${CH_NICHE[$slug]:-?} | ${CH_TOKEN[$slug]:-?} | ${CH_RUN[$slug]:-never} | ${CH_STATUS[$slug]:-unknown} | ${CH_UPLOAD[$slug]:-none} |\n"
done
[ -z "$CHANNEL_TABLE_ROWS" ] && CHANNEL_TABLE_ROWS="| — | no channels found | — | — | — | — |\n"

# ── build JSON manifest ───────────────────────────────────────────────────────
MANIFEST=$(python3 - <<PYEOF
import json

channels = []
for slug in [$(printf '"%s",' "${CHANNELS[@]}" | sed 's/,$//') ]:
    channels.append({
        "slug": slug,
        "niche":   "${CH_NICHE[$slug]:-}",
        "status":  "${CH_STATUS[$slug]:-unknown}",
        "token":   "${CH_TOKEN[$slug]:-MISSING}",
    })

manifest = {
    "generated_at": "$NOW_UTC",
    "version": "$VERSION",
    "disk": {"total": "$DISK_TOTAL", "used": "$DISK_USED", "free": "$DISK_FREE", "pct": "$DISK_PCT", "status": "$DISK_STATUS"},
    "health": {"social_factory": "$HEALTH_SF", "bybit_bot": "$HEALTH_BYBIT", "telegram": "$HEALTH_TG"},
    "sync": "$SYNC_STATUS",
    "tmux_sessions": [s.strip() for s in "$TMUX_SESSIONS".split(",") if s.strip() and s != "none"],
    "cron_count": int("$CRON_COUNT"),
    "channels": channels,
    "projects": [p.strip() for p in "$PROJECTS".split(",") if p.strip() and p != "none"],
    "venvs": $VENVS_JSON,
}
print(json.dumps(manifest, indent=2))
PYEOF
)

# ── write README.md ───────────────────────────────────────────────────────────

cat > "$README" <<README
<!-- AGENT-MANIFEST
$MANIFEST
-->

# Agent Computer v${VERSION} — Live System Map
_Generated: ${NOW_HUMAN} · Updated hourly + after each pipeline run_
_Full guide: \`~/AGENT.md\` · Refresh this file: \`map\`_

---

## What Needs Attention
$(echo -e "$ATTENTION")

---

## Disk
\`$DISK_USED / $DISK_TOTAL used ($DISK_PCT) — $DISK_FREE free — $DISK_STATUS\`

---

## App Health

| App | Status | Location |
|-----|--------|----------|
| social-factory (YouTube) | **$HEALTH_SF** | \`~/apps/social-factory/\` |
| bybit-bot (Trading) | **$HEALTH_BYBIT** | \`~/.bybit/\` · tmux: \`persistent-agent\` |
| telegram | **$HEALTH_TG** | \`~/apps/telegram/\` |
| github-sync | **$SYNC_STATUS** | cron every 6h · log: \`~/documents/sync.log\` |

tmux sessions: \`$TMUX_LIST\`

---

## YouTube Channels

| Channel | Niche | Token | Last Run | Status | Last Upload |
|---------|-------|-------|----------|--------|-------------|
$(echo -e "$CHANNEL_TABLE_ROWS")

---

## Computer Layout

\`\`\`
~/
├── AGENT.md          ← Universal agent guide (read this first)
├── CLAUDE.md         ← Claude Code specific settings
├── README.md         ← This file (auto-generated)
├── apps/             ← social-factory · bybit-bot · telegram
│   └── envs/         ← shared Python venvs
├── projects/         ← active development projects
├── renderer/         ← Remotion video renderer (shared)
├── media/            ← images/ · videos/ · audio/ · exports/
├── scripts/          ← vps-map.sh · vps-export.sh · vps-sync.sh
├── documents/        ← guides · reports · changelog.md · sync.log
├── downloads/        ← temporary content (safe to clear)
├── keys/             ← API credentials (never commit)
└── archive/          ← old versions
\`\`\`

---

## Cron ($CRON_COUNT active jobs)

\`\`\`bash
crontab -l    # see all active jobs
\`\`\`

---

## Projects

$(ls "$HOME_DIR/projects/" 2>/dev/null | while read p; do echo "- \`~/projects/$p/\`"; done || echo "- (none)")

---

## Migration

\`\`\`bash
export                              # configs only
export --include-secrets            # full export with tokens + keys
# Output: ~/vps-export-YYYYMMDD.tar.gz
\`\`\`
README

echo "[$NOW_UTC] README updated → $README"

# ── auto-changelog: record significant state changes ─────────────────────────
CHANGELOG="$HOME_DIR/documents/changelog.md"
STATE_FILE="$HOME_DIR/system/.last-state"
mkdir -p "$HOME_DIR/system"

PREV_BYBIT=$(cat "$STATE_FILE.bybit" 2>/dev/null || echo "")
PREV_SF=$(cat "$STATE_FILE.sf" 2>/dev/null || echo "")

if [ "$HEALTH_BYBIT" != "$PREV_BYBIT" ] && [ -n "$PREV_BYBIT" ]; then
  echo "- [$NOW_UTC] bybit-bot changed: $PREV_BYBIT → $HEALTH_BYBIT" >> "$CHANGELOG"
fi
if [ "$HEALTH_SF" != "$PREV_SF" ] && [ -n "$PREV_SF" ]; then
  echo "- [$NOW_UTC] social-factory changed: $PREV_SF → $HEALTH_SF" >> "$CHANGELOG"
fi

for slug in "${CHANNELS[@]}"; do
  PREV_STATUS=$(cat "$STATE_FILE.$slug" 2>/dev/null || echo "")
  if [ "${CH_STATUS[$slug]:-}" = "FAILED" ] && [ "$PREV_STATUS" != "FAILED" ]; then
    echo "- [$NOW_UTC] $slug pipeline FAILED (was: ${PREV_STATUS:-unknown})" >> "$CHANGELOG"
  fi
  echo "${CH_STATUS[$slug]:-unknown}" > "$STATE_FILE.$slug"
done

echo "$HEALTH_BYBIT" > "$STATE_FILE.bybit"
echo "$HEALTH_SF" > "$STATE_FILE.sf"
