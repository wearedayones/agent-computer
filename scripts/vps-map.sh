#!/bin/bash
# vps-map.sh — Regenerates ~/README.md from live system state.
# Runs automatically hourly via cron.
# Safe to call anytime: read-only except writing ~/README.md.

set -euo pipefail

HOME_DIR="$HOME"
README="$HOME_DIR/README.md"
NOW_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOW_HUMAN=$(date -u "+%Y-%m-%d %H:%M UTC")

# ── collect live data ─────────────────────────────────────────────────────────

DISK_TOTAL=$(df -h "$HOME_DIR" | awk 'NR==2{print $2}')
DISK_USED=$(df -h "$HOME_DIR" | awk 'NR==2{print $3}')
DISK_FREE=$(df -h "$HOME_DIR" | awk 'NR==2{print $4}')
DISK_PCT=$(df "$HOME_DIR" | awk 'NR==2{print $5}')
DISK_FREE_GB=$(df -BG "$HOME_DIR" | awk 'NR==2{gsub("G","",$4); print $4}')
DISK_STATUS="ok"
[ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null && DISK_STATUS="LOW — clear ~/downloads/ or ~/archive/"

TMUX_LIST=$(tmux ls 2>/dev/null | awk -F: '{print $1}' | tr '\n' ', ' | sed 's/, $//' || echo "none")
CRON_COUNT=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)

# GitHub sync status
LAST_SYNC_LINE=$(grep "Pushed\|No changes" "$HOME_DIR/documents/sync.log" 2>/dev/null | tail -1 || echo "")
LAST_SYNC_TS=$(grep -o '\[.*\]' "$HOME_DIR/documents/sync.log" 2>/dev/null | tail -1 | tr -d '[]' || echo "never")
SYNC_STATUS="not configured"
[ -n "$LAST_SYNC_LINE" ] && SYNC_STATUS="ok ($LAST_SYNC_TS)"

# Venv inventory (dynamic)
VENVS_LIST=""
ENVS_DIR="$HOME_DIR/apps/envs"
if [ -d "$ENVS_DIR" ]; then
  for v in "$ENVS_DIR"/*/; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    [ -f "$v/bin/python3" ] && VENVS_LIST+="$name " || VENVS_LIST+="${name}(BROKEN) "
  done
fi
VENVS_LIST=$(echo "$VENVS_LIST" | xargs)
[ -z "$VENVS_LIST" ] && VENVS_LIST="none"

# Root clutter
ALLOWED_ROOT="AGENT.md CLAUDE.md README.md apps archive bin documents downloads inbox keys legal media projects renderer scripts snap system venv yt-upload-venv tg-agent-env antigravity-bot-venv"
ROOT_CLUTTER=""
for item in "$HOME_DIR"/*/; do
  name=$(basename "$item")
  echo "$ALLOWED_ROOT" | grep -qw "$name" || ROOT_CLUTTER+="$name "
done
for item in "$HOME_DIR"/*; do
  name=$(basename "$item")
  [[ "$name" == *.md ]] && continue
  [[ -d "$item" ]] && continue
  echo "$ALLOWED_ROOT" | grep -qw "$name" || ROOT_CLUTTER+="$name "
done
ROOT_CLUTTER=$(echo "$ROOT_CLUTTER" | xargs)

# Projects list
PROJECTS_LIST=$(ls "$HOME_DIR/projects/" 2>/dev/null | tr '\n' ' ' | xargs || echo "none")

# Open tasks (from task store)
OPEN_TASKS_BLOCK=""
TASKS_FILE="$HOME_DIR/system/tasks.json"
if [ -f "$TASKS_FILE" ]; then
  OPEN_TASKS_BLOCK=$(python3 - "$TASKS_FILE" <<'EOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
tasks = [t for t in d.get("tasks",[]) if t.get("status") == "open"]
if not tasks:
    print("_No open tasks_")
else:
    for t in tasks:
        print(f"- [ ] #{t['id']} {t['desc']}")
EOF
)
else
  OPEN_TASKS_BLOCK="_No tasks yet_"
fi

# Active memories (top 5)
MEMORIES_BLOCK=""
MEMORY_FILE="$HOME_DIR/system/memory.json"
if [ -f "$MEMORY_FILE" ]; then
  MEMORIES_BLOCK=$(python3 - "$MEMORY_FILE" <<'EOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
if not d:
    print("_No memories stored_")
else:
    items = list(d.items())[:5]
    for k, v in items:
        v_short = v[:60] + "…" if len(v) > 60 else v
        print(f"- **{k}**: {v_short}")
    if len(d) > 5:
        print(f"- _{len(d)-5} more — run `memory list`_")
EOF
)
else
  MEMORIES_BLOCK="_No memories yet_"
fi

# Recent activity (last 5 changelog entries)
RECENT_ACTIVITY=""
CHANGELOG="$HOME_DIR/documents/changelog.md"
if [ -f "$CHANGELOG" ]; then
  RECENT_ACTIVITY=$(grep "^-" "$CHANGELOG" 2>/dev/null | tail -5 || echo "_No activity logged_")
else
  RECENT_ACTIVITY="_No activity logged yet_"
fi

# Budget this month
BUDGET_BLOCK=""
BUDGET_FILE="$HOME_DIR/system/budget.json"
if [ -f "$BUDGET_FILE" ]; then
  BUDGET_BLOCK=$(python3 - "$BUDGET_FILE" <<'EOF'
import json, sys
from datetime import datetime, timezone
with open(sys.argv[1]) as f: d = json.load(f)
month = datetime.now(timezone.utc).strftime("%Y-%m")
entries = [e for e in d.get("entries",[]) if e.get("month") == month]
if not entries:
    print(f"_No spend logged for {month}_")
else:
    total = sum(e["amount"] for e in entries)
    print(f"**${total:.4f}** across {len(entries)} entries in {month}")
EOF
)
else
  BUDGET_BLOCK="_No budget logged yet_"
fi

# Active plan
PLAN_BLOCK=""
PLAN_FILE="$HOME_DIR/system/plan.md"
if [ -f "$PLAN_FILE" ]; then
  PLAN_BLOCK=$(head -6 "$PLAN_FILE")
else
  PLAN_BLOCK="_No active plan — run \`plan set \"title\"\`_"
fi

# Alerts
ATTENTION=""
[ "${DISK_FREE_GB:-99}" -lt 3 ] 2>/dev/null && ATTENTION+="- **DISK LOW**: only ${DISK_FREE_GB}GB free — clear downloads/ or archive/\n"
[ -n "$ROOT_CLUTTER" ] && ATTENTION+="- **ROOT CLUTTER**: $ROOT_CLUTTER — move to correct zone\n"
INBOX_COUNT=$(ls "$HOME_DIR/inbox/"*.md 2>/dev/null | wc -l)
[ "$INBOX_COUNT" -gt 0 ] && ATTENTION+="- **INBOX**: $INBOX_COUNT message(s) waiting — run \`boot\` to read\n"
OPEN_COUNT=$(python3 -c "
import json
try:
    with open('$TASKS_FILE') as f: d=json.load(f)
    print(len([t for t in d.get('tasks',[]) if t.get('status')=='open']))
except: print(0)
" 2>/dev/null || echo 0)
[ "$OPEN_COUNT" -gt 0 ] && ATTENTION+="- **TASKS**: $OPEN_COUNT open task(s) — run \`task list\`\n"
[ -z "$ATTENTION" ] && ATTENTION="None — all systems nominal"

VERSION=$(cat "$HOME_DIR/system/.version" 2>/dev/null || echo "unknown")

# ── build JSON manifest ───────────────────────────────────────────────────────
MANIFEST=$(python3 - <<PYEOF
import json
manifest = {
    "generated_at": "$NOW_UTC",
    "version": "$VERSION",
    "disk": {
        "total": "$DISK_TOTAL",
        "used": "$DISK_USED",
        "free": "$DISK_FREE",
        "pct": "$DISK_PCT",
        "status": "$DISK_STATUS"
    },
    "tmux_sessions": [s.strip() for s in "$TMUX_LIST".split(",") if s.strip() and s.strip() != "none"],
    "cron_count": int("$CRON_COUNT"),
    "sync": "$SYNC_STATUS",
    "venvs": [v for v in "$VENVS_LIST".split() if v],
    "projects": [p for p in "$PROJECTS_LIST".split() if p and p != "none"],
    "open_tasks": $OPEN_COUNT,
}
print(json.dumps(manifest, indent=2))
PYEOF
)

# ── build tmux session table ──────────────────────────────────────────────────
TMUX_TABLE=""
TMUX_FULL=$(tmux ls 2>/dev/null || echo "")
if [ -n "$TMUX_FULL" ]; then
  while IFS= read -r line; do
    TMUX_TABLE+="| $line |\n"
  done <<< "$TMUX_FULL"
else
  TMUX_TABLE="| (no sessions) |\n"
fi

# ── write README.md ───────────────────────────────────────────────────────────

cat > "$README" <<README
<!-- AGENT-MANIFEST
$MANIFEST
-->

# Agent Computer v${VERSION} — Live System Map
_Generated: ${NOW_HUMAN} · Refresh: \`map\`_
_Full guide: \`~/AGENT.md\`_

---

## What Needs Attention
$(echo -e "$ATTENTION")

---

## Open Tasks
$OPEN_TASKS_BLOCK

---

## Active Plan
$PLAN_BLOCK

---

## Memories
$MEMORIES_BLOCK

---

## Recent Activity
$RECENT_ACTIVITY

---

## System

\`Disk: $DISK_USED / $DISK_TOTAL ($DISK_PCT) — $DISK_FREE free\`
Cron: **$CRON_COUNT** jobs · Sync: **$SYNC_STATUS** · Budget: $BUDGET_BLOCK

### Running Sessions

| Session |
|---------|
$(echo -e "$TMUX_TABLE")

---

## Computer Layout

\`\`\`
~/
├── AGENT.md          ← Universal agent guide (read this first)
├── CLAUDE.md         ← Claude Code settings + protected paths
├── README.md         ← This file (auto-generated)
├── apps/             ← Autonomous apps
│   └── envs/         ← Shared Python venvs: $VENVS_LIST
├── projects/         ← Active development
├── scripts/          ← Tools and utilities
├── documents/        ← Notes, guides, changelog
├── media/            ← images/ · videos/ · audio/ · exports/
├── downloads/        ← Temp content (safe to clear)
└── keys/             ← API credentials (never commit)
\`\`\`

---

## Projects

$(ls "$HOME_DIR/projects/" 2>/dev/null | while read p; do echo "- \`~/projects/$p/\`"; done || echo "- (none)")

---

## Migration

\`\`\`bash
export                              # configs only
export --include-secrets            # full export with keys + tokens
\`\`\`
README

echo "[$NOW_UTC] README updated → $README"

# ── auto-changelog: record state changes ──────────────────────────────────────
CHANGELOG="$HOME_DIR/documents/changelog.md"
STATE_FILE="$HOME_DIR/system/.last-state"
mkdir -p "$HOME_DIR/system"

PREV_DISK=$(cat "$STATE_FILE.disk" 2>/dev/null || echo "")
if [ "$DISK_STATUS" != "ok" ] && [ "$PREV_DISK" != "$DISK_STATUS" ]; then
  echo "- [$NOW_UTC] DISK WARNING: $DISK_STATUS" >> "$CHANGELOG"
fi
echo "$DISK_STATUS" > "$STATE_FILE.disk"
