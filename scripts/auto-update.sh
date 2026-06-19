#!/bin/bash
# auto-update.sh — pull latest agent-computer infrastructure from GitHub
# Safe: only updates scripts/, system/, bin/, AGENT.md, CLAUDE.md
# Never touches: apps/, projects/, documents/, keys/, tokens/, channels/

HOME_DIR="/home/ubuntu"
VERSION_FILE="$HOME_DIR/system/.version"
SOURCE_FILE="$HOME_DIR/system/.update-source"
CHANGELOG="$HOME_DIR/documents/changelog.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

log() { echo "- [$NOW] [update] $*" >> "$CHANGELOG"; echo "[update] $*"; }

# Read source repo
REPO_URL=$(cat "$SOURCE_FILE" 2>/dev/null || echo "")
if [ -z "$REPO_URL" ]; then
  log "No update source configured ($SOURCE_FILE missing)"
  exit 0
fi

LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")

# Fetch remote VERSION file
REMOTE_VERSION=$(curl -fsSL "${REPO_URL}/raw/main/VERSION" 2>/dev/null | tr -d '[:space:]')
if [ -z "$REMOTE_VERSION" ]; then
  log "Could not fetch remote version from $REPO_URL"
  exit 1
fi

# Compare versions (simple string compare works for semver if padded properly)
if [ "$REMOTE_VERSION" = "$LOCAL_VERSION" ]; then
  echo "[update] Already up to date (v$LOCAL_VERSION)"
  exit 0
fi

log "Update available: v$LOCAL_VERSION → v$REMOTE_VERSION — applying..."

# Download repo as tarball
curl -fsSL "${REPO_URL}/archive/refs/heads/main.tar.gz" -o "$TMP_DIR/update.tar.gz" || {
  log "Download failed"
  exit 1
}

tar -xzf "$TMP_DIR/update.tar.gz" -C "$TMP_DIR" || {
  log "Extract failed"
  exit 1
}

EXTRACTED=$(ls "$TMP_DIR" | grep -v update.tar.gz | head -1)
SRC="$TMP_DIR/$EXTRACTED"

# Apply updates — ONLY infrastructure files, never user data
update_file() {
  local src="$1" dst="$2"
  [ -f "$src" ] || return
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

update_file "$SRC/AGENT.md"           "$HOME_DIR/AGENT.md"
update_file "$SRC/CLAUDE.md"          "$HOME_DIR/CLAUDE.md"
update_file "$SRC/scripts/vps-map.sh"    "$HOME_DIR/scripts/vps-map.sh"
update_file "$SRC/scripts/vps-export.sh" "$HOME_DIR/scripts/vps-export.sh"
update_file "$SRC/scripts/auto-update.sh" "$HOME_DIR/scripts/auto-update.sh"
update_file "$SRC/system/health.sh"   "$HOME_DIR/system/health.sh"
update_file "$SRC/system/boot.sh"     "$HOME_DIR/system/boot.sh"
update_file "$SRC/system/relocator.sh" "$HOME_DIR/system/relocator.sh"

for f in "$SRC/bin/"*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  update_file "$f" "$HOME_DIR/bin/$fname"
done

# Make everything executable
chmod +x "$HOME_DIR/bin/"* "$HOME_DIR/system/"*.sh "$HOME_DIR/scripts/"*.sh 2>/dev/null

# Update version and lock file
echo "$REMOTE_VERSION" > "$VERSION_FILE"
cat > "$HOME_DIR/system/.installed" <<LOCK
  Installed:  $(cat "$HOME_DIR/system/.installed" 2>/dev/null | grep 'Installed:' | sed 's/.*Installed: *//' || echo "unknown")
  Version:    v$REMOTE_VERSION
  Updated:    $(date -u '+%Y-%m-%d %H:%M UTC')
  Server:     $(hostname)
  Source:     $REPO_URL
LOCK

log "Updated to v$REMOTE_VERSION successfully"

# Refresh README
bash "$HOME_DIR/scripts/vps-map.sh" &>/dev/null &

echo "[update] Done — agent computer is now v$REMOTE_VERSION"
