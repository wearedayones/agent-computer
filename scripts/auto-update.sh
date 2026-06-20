#!/bin/bash
# auto-update.sh — keep agent-computer in sync with GitHub
# Strategy: git pull if repo is cloned (fast); tarball fallback for legacy installs.
# Cron: */15 * * * * bash ~/scripts/auto-update.sh >> ~/system/update.log 2>&1

HOME_DIR="$HOME"
REPO_DIR="$HOME_DIR/projects/agent-computer"
VERSION_FILE="$HOME_DIR/system/.version"
SOURCE_FILE="$HOME_DIR/system/.update-source"
CHANGELOG="$HOME_DIR/documents/changelog.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log() { echo "- [$NOW] [update] $*" | tee -a "$CHANGELOG"; }

REPO_URL=$(cat "$SOURCE_FILE" 2>/dev/null || echo "")
[ -z "$REPO_URL" ] && { echo "[update] No update source ($SOURCE_FILE missing)"; exit 0; }

# ── Strategy 1: git pull (preferred — repo already cloned) ───────────────────
if [ -d "$REPO_DIR/.git" ]; then
  LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")

  git -C "$REPO_DIR" fetch origin main --quiet 2>/dev/null || {
    echo "[update] fetch failed — skipping"
    exit 0
  }

  BEHIND=$(git -C "$REPO_DIR" rev-list HEAD..origin/main --count 2>/dev/null || echo "0")
  if [ "$BEHIND" = "0" ]; then
    echo "[update] Already up to date (v$LOCAL_VERSION)"
    exit 0
  fi

  git -C "$REPO_DIR" pull origin main --quiet 2>/dev/null || { log "git pull failed"; exit 1; }

  REMOTE_VERSION=$(cat "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  bash "$REPO_DIR/link.sh" >> "$HOME_DIR/system/update.log" 2>&1
  echo "$REMOTE_VERSION" > "$VERSION_FILE"
  log "Updated v$LOCAL_VERSION → v$REMOTE_VERSION via git pull"
  bash "$HOME_DIR/scripts/vps-map.sh" &>/dev/null &
  exit 0
fi

# ── Strategy 2: tarball (fallback for legacy installs without git clone) ──────
LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")
REMOTE_VERSION=$(curl -fsSL "${REPO_URL}/raw/main/VERSION" 2>/dev/null | tr -d '[:space:]')
[ -z "$REMOTE_VERSION" ] && { log "Could not fetch remote version"; exit 1; }
[ "$REMOTE_VERSION" = "$LOCAL_VERSION" ] && { echo "[update] Already up to date (v$LOCAL_VERSION)"; exit 0; }

log "Update available v$LOCAL_VERSION → v$REMOTE_VERSION — downloading tarball..."
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

curl -fsSL "${REPO_URL}/archive/refs/heads/main.tar.gz" -o "$TMP_DIR/update.tar.gz" || { log "Download failed"; exit 1; }
tar -xzf "$TMP_DIR/update.tar.gz" -C "$TMP_DIR" || { log "Extract failed"; exit 1; }
SRC="$TMP_DIR/$(ls "$TMP_DIR" | grep -v update.tar.gz | head -1)"

copy() { [ -f "$SRC/$1" ] && { mkdir -p "$(dirname "$HOME_DIR/$2")"; cp "$SRC/$1" "$HOME_DIR/$2"; }; }

copy "AGENT.md"                 "AGENT.md"
copy "CLAUDE.md"                "CLAUDE.md"
copy "link.sh"                  "projects/agent-computer/link.sh"
copy "system/boot.sh"           "system/boot.sh"
copy "system/health.sh"         "system/health.sh"
copy "system/relocator.sh"      "system/relocator.sh"
copy "scripts/auto-update.sh"   "scripts/auto-update.sh"
copy "scripts/session-brief.sh" "scripts/session-brief.sh"
copy "scripts/vps-map.sh"       "scripts/vps-map.sh"
copy "scripts/vps-export.sh"    "scripts/vps-export.sh"
copy "scripts/vps-sync.sh"      "scripts/vps-sync.sh"
for f in "$SRC/bin/"*; do [ -f "$f" ] && copy "bin/$(basename "$f")" "bin/$(basename "$f")"; done

chmod +x "$HOME_DIR/bin/"* "$HOME_DIR/system/"*.sh "$HOME_DIR/scripts/"*.sh 2>/dev/null
echo "$REMOTE_VERSION" > "$VERSION_FILE"
log "Updated to v$REMOTE_VERSION via tarball"
bash "$HOME_DIR/scripts/vps-map.sh" &>/dev/null &
