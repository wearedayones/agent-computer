#!/bin/bash
# auto-update.sh — pulls latest computer infrastructure from GitHub into root
# Completely independent from ~/projects/agent-computer/ dev repo.
# Cron: */15 * * * * bash ~/scripts/auto-update.sh >> ~/system/update.log 2>&1

HOME_DIR="$HOME"
VERSION_FILE="$HOME_DIR/system/.version"
SOURCE_FILE="$HOME_DIR/system/.update-source"
CHANGELOG="$HOME_DIR/documents/changelog.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log() { echo "- [$NOW] [update] $*" | tee -a "$CHANGELOG"; }

REPO_URL=$(cat "$SOURCE_FILE" 2>/dev/null || echo "")
[ -z "$REPO_URL" ] && { echo "[update] No update source ($SOURCE_FILE missing)"; exit 0; }

LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")

# Cheap check — fetch only the VERSION file first
REMOTE_VERSION=$(curl -fsSL "${REPO_URL}/raw/main/VERSION" 2>/dev/null | tr -d '[:space:]')
[ -z "$REMOTE_VERSION" ] && { echo "[update] Could not reach GitHub — skipping"; exit 0; }
[ "$REMOTE_VERSION" = "$LOCAL_VERSION" ] && { echo "[update] Up to date (v$LOCAL_VERSION)"; exit 0; }

log "New version available: v$LOCAL_VERSION → v$REMOTE_VERSION — applying..."

# Download tarball into temp dir
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

curl -fsSL "${REPO_URL}/archive/refs/heads/main.tar.gz" -o "$TMP_DIR/update.tar.gz" || {
  log "Download failed"
  exit 1
}
tar -xzf "$TMP_DIR/update.tar.gz" -C "$TMP_DIR" || {
  log "Extract failed"
  exit 1
}
SRC="$TMP_DIR/$(ls "$TMP_DIR" | grep -v update.tar.gz | head -1)"

# Copy infrastructure files to root — never touches user data
apply() {
  local src="$SRC/$1" dst="$HOME_DIR/$2"
  [ -f "$src" ] || return
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

apply "AGENT.md"                  "AGENT.md"
apply "CLAUDE.md"                 "CLAUDE.md"
apply "system/boot.sh"            "system/boot.sh"
apply "system/health.sh"          "system/health.sh"
apply "system/relocator.sh"       "system/relocator.sh"
apply "system/trace.sh"           "system/trace.sh"
apply "system/env.sh"             "system/env.sh"
apply "system/ctx.sh"             "system/ctx.sh"
apply "system/metric.sh"          "system/metric.sh"
apply "scripts/auto-update.sh"    "scripts/auto-update.sh"
apply "scripts/session-brief.sh"  "scripts/session-brief.sh"
apply "scripts/vps-map.sh"        "scripts/vps-map.sh"
apply "scripts/vps-export.sh"     "scripts/vps-export.sh"
apply "scripts/vps-sync.sh"       "scripts/vps-sync.sh"

for f in "$SRC/bin/"*; do
  [ -f "$f" ] && apply "bin/$(basename "$f")" "bin/$(basename "$f")"
done

# Permissions
chmod +x "$HOME_DIR/bin/"* "$HOME_DIR/system/"*.sh "$HOME_DIR/scripts/"*.sh 2>/dev/null

# Re-symlink bin to /usr/local/bin in case new commands were added
for cmd in "$HOME_DIR/bin/"*; do
  sudo ln -sf "$cmd" "/usr/local/bin/$(basename "$cmd")" 2>/dev/null || true
done

# Re-symlink machine-level docs to / so any agent on this computer finds them
for doc in AGENT.md CLAUDE.md README.md; do
  sudo ln -sf "$HOME_DIR/$doc" "/$doc" 2>/dev/null || true
done

echo "$REMOTE_VERSION" > "$VERSION_FILE"
log "Updated to v$REMOTE_VERSION successfully"

# Show what changed — pull first non-empty line after version heading in new AGENT.md
WHATSNEW=$(awk "/^## Shell Commands/,/^---/" "$SRC/AGENT.md" 2>/dev/null | \
           grep "^| \`" | tail -5 | sed 's/^| //;s/ |.*//' | tr '\n' ', ' | sed 's/, $//')
[ -n "$WHATSNEW" ] && log "New/updated commands: $WHATSNEW"

# Refresh README
bash "$HOME_DIR/scripts/vps-map.sh" &>/dev/null &
