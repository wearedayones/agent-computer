#!/bin/bash
# vps-map.sh — Regenerates ~/README.md from live system state.
# Runs automatically after each pipeline and hourly via cron.
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
    bybit) tmux has-session -t persistent-agent 2>/dev/null && echo "running" || echo "STOPPED" ;;
    social-factory) crontab -l 2>/dev/null | grep -q "social-factory" && echo "scheduled" || echo "no-crons" ;;
    telegram) pgrep -f "alex.py\|antigravity_bot" &>/dev/null && echo "running" || echo "stopped" ;;
  esac
}

# ── collect live data ────────────────────────────────────────────────────────

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

# Root clutter check — only these items should exist at root
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

declare -A CH_NICHE CH_THEME CH_RUN CH_STATUS CH_UPLOAD CH_TOKEN

CHANNELS=(aura-clips crvgrowth curiosity-files)
for slug in "${CHANNELS[@]}"; do
  cfg="$SF_DIR/channels/$slug/config.json"
  CH_NICHE[$slug]=$(json_field "$cfg" "niche")
  CH_THEME[$slug]=$(json_field "$cfg" "video_theme")
  CH_RUN[$slug]=$(last_run_ts "$slug")
  CH_STATUS[$slug]=$(last_run_status "$slug")
  CH_UPLOAD[$slug]=$(last_upload "$slug")
  CH_TOKEN[$slug]=$(token_ok "$slug-youtube.json")
done

# Alerts
ATTENTION=""
for slug in "${CHANNELS[@]}"; do
  [ "${CH_STATUS[$slug]}" = "FAILED" ] && ATTENTION+="- social-factory/$slug last run FAILED\n"
  [ "${CH_TOKEN[$slug]}" = "MISSING" ] && ATTENTION+="- social-factory/$slug YouTube token MISSING\n"
done
[ "$HEALTH_BYBIT" = "STOPPED" ] && ATTENTION+="- bybit-bot (persistent-agent) is NOT running\n"
[ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null && ATTENTION+="- DISK LOW: only ${DISK_FREE_GB}GB free\n"
[ -n "$ROOT_CLUTTER" ] && ATTENTION+="- ROOT CLUTTER: $ROOT_CLUTTER — move these to the correct zone\n"
[ -z "$ATTENTION" ] && ATTENTION="None — all systems nominal"

PROJECTS=$(ls "$HOME_DIR/projects/" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "none")

VENVS_JSON="["
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  [ -f "$HOME_DIR/$v/bin/python3" ] && VENVS_JSON+="\"$v\"," || VENVS_JSON+="\"${v}(MISSING)\","
done
VENVS_JSON="${VENVS_JSON%,}]"

# ── build JSON manifest ───────────────────────────────────────────────────────

MANIFEST=$(python3 - <<PYEOF
import json

slugs = ["aura-clips", "crvgrowth", "curiosity-files"]
channels = []
for slug in slugs:
    channels.append({
        "slug": slug,
        "niche":            {"aura-clips": "${CH_NICHE[aura-clips]}", "crvgrowth": "${CH_NICHE[crvgrowth]}", "curiosity-files": "${CH_NICHE[curiosity-files]}"}[slug],
        "theme":            {"aura-clips": "${CH_THEME[aura-clips]}", "crvgrowth": "${CH_THEME[crvgrowth]}", "curiosity-files": "${CH_THEME[curiosity-files]}"}[slug],
        "last_run":         {"aura-clips": "${CH_RUN[aura-clips]}", "crvgrowth": "${CH_RUN[crvgrowth]}", "curiosity-files": "${CH_RUN[curiosity-files]}"}[slug],
        "last_run_status":  {"aura-clips": "${CH_STATUS[aura-clips]}", "crvgrowth": "${CH_STATUS[crvgrowth]}", "curiosity-files": "${CH_STATUS[curiosity-files]}"}[slug],
        "last_upload":      {"aura-clips": "${CH_UPLOAD[aura-clips]}", "crvgrowth": "${CH_UPLOAD[crvgrowth]}", "curiosity-files": "${CH_UPLOAD[curiosity-files]}"}[slug],
        "youtube_token":    {"aura-clips": "${CH_TOKEN[aura-clips]}", "crvgrowth": "${CH_TOKEN[crvgrowth]}", "curiosity-files": "${CH_TOKEN[curiosity-files]}"}[slug],
    })

manifest = {
    "generated_at": "$NOW_UTC",
    "disk": {"total": "$DISK_TOTAL", "used": "$DISK_USED", "free": "$DISK_FREE", "pct": "$DISK_PCT", "status": "$DISK_STATUS"},
    "health": {"social_factory": "$HEALTH_SF", "bybit_bot": "$HEALTH_BYBIT", "telegram": "$HEALTH_TG"},
    "tmux_sessions": [s.strip() for s in "$TMUX_SESSIONS".split(",") if s.strip() and s != "none"],
    "cron_count": int("$CRON_COUNT"),
    "channels": channels,
    "projects": [p.strip() for p in "$PROJECTS".split(",") if p.strip() and p != "none"],
    "venvs": $VENVS_JSON,
    "paths": {
        "social_factory": "/home/ubuntu/apps/social-factory",
        "bybit_bot":      "/home/ubuntu/apps/bybit-bot",
        "telegram":       "/home/ubuntu/apps/telegram",
        "renderer":       "/home/ubuntu/renderer",
        "scripts":        "/home/ubuntu/scripts",
        "keys":           "/home/ubuntu/keys",
        "documents":      "/home/ubuntu/documents",
    },
    "agent_guide": "/home/ubuntu/AGENT.md",
}
print(json.dumps(manifest, indent=2))
PYEOF
)

# ── write README.md ───────────────────────────────────────────────────────────

cat > "$README" <<README
<!-- AGENT-MANIFEST
$MANIFEST
-->
<!-- To parse: python3 -c "import json; d=open('README.md').read(); print(json.loads(d.split('AGENT-MANIFEST')[1].split('-->')[0]))" -->

# Agent Computer — Live System Map
_Generated: ${NOW_HUMAN} · Updated every hour + after each pipeline run_
_Full operating guide: \`~/AGENT.md\` · Update this file: \`bash ~/scripts/vps-map.sh\`_

---

## What Needs Attention
${ATTENTION}

---

## Disk
\`$DISK_USED / $DISK_TOTAL used ($DISK_PCT) — $DISK_FREE free — $DISK_STATUS\`

---

## App Health

| App | Status | Location |
|-----|--------|----------|
| social-factory (YouTube) | **$HEALTH_SF** | \`~/apps/social-factory/\` |
| bybit-bot (Trading) | **$HEALTH_BYBIT** | \`~/apps/bybit-bot/\` · tmux: \`persistent-agent\` |
| telegram | **$HEALTH_TG** | \`~/apps/telegram/\` |

tmux: \`$TMUX_LIST\`

---

## YouTube Channels

| Channel | Niche | Token | Last Run | Status | Last Upload |
|---------|-------|-------|----------|--------|-------------|
| aura-clips | ${CH_NICHE[aura-clips]} | ${CH_TOKEN[aura-clips]} | ${CH_RUN[aura-clips]} | ${CH_STATUS[aura-clips]} | ${CH_UPLOAD[aura-clips]} |
| crvgrowth | ${CH_NICHE[crvgrowth]} | ${CH_TOKEN[crvgrowth]} | ${CH_RUN[crvgrowth]} | ${CH_STATUS[crvgrowth]} | ${CH_UPLOAD[crvgrowth]} |
| curiosity-files | ${CH_NICHE[curiosity-files]} | ${CH_TOKEN[curiosity-files]} | ${CH_RUN[curiosity-files]} | ${CH_STATUS[curiosity-files]} | ${CH_UPLOAD[curiosity-files]} |

---

## Computer Layout

\`\`\`
~/
├── AGENT.md          ← Universal agent guide (read this first)
├── CLAUDE.md         ← Claude Code specific settings
├── README.md         ← This file (auto-generated)
├── apps/             ← social-factory · bybit-bot · telegram
├── projects/         ← altaris-capital · web3-dapp · content-creator-skill
├── renderer/         ← Remotion video renderer (shared)
├── media/            ← images/ · videos/ · audio/ · thumbnails/ · exports/
├── scripts/          ← vps-map.sh · vps-export.sh · rethumb.py · push_repo.sh
├── documents/        ← yt-briefing.md · guides/ · reports/
├── downloads/        ← temporary content (tmp/ · imports/)
├── keys/             ← API credentials
├── legal/            ← OAuth consent pages
└── archive/          ← old versions
\`\`\`

---

## Cron ($CRON_COUNT active jobs)

| Time (UTC) | Job |
|------------|-----|
| 11:25 / 16:25 / 23:25 | aura-clips short |
| 06:00 | aura-clips long (19:00 UTC publish) |
| 11:55 / 16:55 / 23:55 | crvgrowth short |
| 06:30 | crvgrowth long |
| 11:05 / 16:05 / 23:05 | curiosity-files short |
| 07:00 | curiosity-files long |
| 04:00 / 04:30 / 04:45 | analytics per channel |
| every :30 | healthcheck per channel |
| every :15 | janitor.sh |
| every :00 | vps-map.sh (this file) |
| @reboot + every 5min | bybit persistent-agent |

---

## Projects

| Project | Path |
|---------|------|
| Altaris Capital | \`~/projects/altaris-capital/\` |
| Web3 Dapp | \`~/projects/web3-dapp/\` |
| Content Creator Skill | \`~/projects/content-creator-skill/\` |

---

## Migration

\`\`\`bash
bash ~/scripts/vps-export.sh                    # configs only
bash ~/scripts/vps-export.sh --include-secrets  # full export with tokens + keys
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
  if [ "${CH_STATUS[$slug]}" = "FAILED" ] && [ "$PREV_STATUS" != "FAILED" ]; then
    echo "- [$NOW_UTC] $slug pipeline FAILED (was: ${PREV_STATUS:-unknown})" >> "$CHANGELOG"
  fi
  echo "${CH_STATUS[$slug]}" > "$STATE_FILE.$slug"
done

echo "$HEALTH_BYBIT" > "$STATE_FILE.bybit"
echo "$HEALTH_SF" > "$STATE_FILE.sf"
