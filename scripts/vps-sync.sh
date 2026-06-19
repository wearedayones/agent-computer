#!/bin/bash
# vps-sync.sh — Auto-sync this VPS to a private GitHub repo.
# Runs on cron. Detects changes, commits with timestamp, pushes.
#
# Setup (one time):
#   1. Create a private GitHub repo (e.g. yourname/vps-backup)
#   2. Save a GitHub personal access token to ~/keys/github_token.txt
#   3. Initialize: cd ~/projects/vps-backup && git init && git remote add origin ...
#   4. Add to crontab: 0 */6 * * * bash ~/scripts/vps-sync.sh >> ~/documents/sync.log 2>&1
#
# Cron: 0 */6 * * * bash ~/scripts/vps-sync.sh >> ~/documents/sync.log 2>&1

set -euo pipefail

H="/home/ubuntu"
REPO="$H/projects/vps-backup"
LOG_PREFIX="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')]"

log() { echo "$LOG_PREFIX $1"; }

# ── Validate setup ────────────────────────────────────────────────────────────
if [ ! -d "$REPO/.git" ]; then
  log "ERROR: $REPO is not a git repository. Run setup first:"
  log "  mkdir -p $REPO && cd $REPO && git init && git remote add origin https://github.com/YOUR/vps-backup.git"
  exit 1
fi

TOKEN=$(cat "$H/keys/github_token.txt" 2>/dev/null || echo "")
if [ -z "$TOKEN" ]; then
  log "ERROR: no GitHub token at ~/keys/github_token.txt"
  exit 1
fi

REMOTE_URL=$(cd "$REPO" && git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REMOTE_URL" ]; then
  log "ERROR: no remote 'origin' configured in $REPO"
  exit 1
fi

# Extract repo path from URL (works for https or git@ URLs)
REPO_PATH=$(echo "$REMOTE_URL" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')

# ── Pull latest first ─────────────────────────────────────────────────────────
cd "$REPO"
git fetch origin main --quiet 2>/dev/null || { log "WARN: fetch failed, continuing"; }

# ── Sync all files into the repo ─────────────────────────────────────────────
rsync -a --delete \
  --exclude='envs/' --exclude='*/venv/' --exclude='__pycache__/' --exclude='*.pyc' \
  "$H/apps/" "$REPO/apps/"

rsync -a --delete \
  --exclude='node_modules/' --exclude='.next/' --exclude='__pycache__/' --exclude='*.pyc' \
  "$H/projects/" "$REPO/projects/"

rsync -a --delete \
  --exclude='node_modules/' --exclude='out/' \
  "$H/renderer/" "$REPO/renderer/" 2>/dev/null || true

rsync -a --delete "$H/scripts/"   "$REPO/scripts/"
rsync -a --delete "$H/bin/"       "$REPO/bin/"
rsync -a --delete "$H/system/"    "$REPO/system/"
rsync -a          "$H/documents/" "$REPO/documents/" 2>/dev/null || true
rsync -a          "$H/legal/"     "$REPO/legal/"     2>/dev/null || true

cp "$H/AGENT.md" "$H/CLAUDE.md" "$H/README.md" "$REPO/" 2>/dev/null || true

# Crontab snapshot
crontab -l > "$REPO/crontab.txt" 2>/dev/null || true

# Venv package lists
mkdir -p "$REPO/venv-packages"
if [ -d "$H/apps/envs" ]; then
  for v in "$H/apps/envs"/*/; do
    [ -d "$v" ] || continue
    name=$(basename "$v")
    if [ -f "$v/bin/python3" ]; then
      "$v/bin/python3" -m pip freeze > "$REPO/venv-packages/$name.txt" 2>/dev/null || true
    fi
  done
fi
# Legacy venv paths
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  vpath="$H/apps/envs/$v"
  if [ -f "$vpath/bin/python3" ]; then
    "$vpath/bin/python3" -m pip freeze > "$REPO/venv-packages/$v.txt" 2>/dev/null || true
  fi
done

# ── Check for changes ─────────────────────────────────────────────────────────
cd "$REPO"
if git diff --quiet && git diff --staged --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  log "No changes — nothing to push"
  exit 0
fi

# ── Commit and push ───────────────────────────────────────────────────────────
CHANGED=$(git status --short | wc -l | tr -d ' ')
git add -A

git commit -m "auto-sync: $CHANGED file(s) changed — $(date -u '+%Y-%m-%d %H:%M UTC')" \
  --author="VPS AutoSync <noreply@vps.local>" --quiet

git push "https://${TOKEN}@github.com/${REPO_PATH}.git" main --quiet

log "Pushed — $CHANGED file(s) updated → github.com/${REPO_PATH}"
