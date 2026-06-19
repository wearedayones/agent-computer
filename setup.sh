#!/bin/bash
# setup.sh — install Agent Computer on a fresh Ubuntu VPS
# Usage:
#   bash setup.sh                   # fresh install (blocked if already installed)
#   bash setup.sh --update          # update existing installation
#   bash setup.sh --force           # reinstall over existing (archives old first)
#
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/wearedayones/agent-computer/main/setup.sh)

set -e

REPO_URL="${REPO_URL:-https://github.com/wearedayones/agent-computer}"
HOME_DIR="$HOME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$HOME_DIR/system/.installed"
VERSION_FILE="$HOME_DIR/system/.version"
MODE="install"

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --update) MODE="update" ;;
    --force)  MODE="force"  ;;
  esac
done

# ── singleton guard ───────────────────────────────────────────────────────────
if [ -f "$LOCK_FILE" ] && [ "$MODE" = "install" ]; then
  echo ""
  echo "  ✗  Agent Computer is already installed on this server."
  echo ""
  cat "$LOCK_FILE"
  echo ""
  echo "  Each server can only have ONE Agent Computer installation."
  echo ""
  echo "  Options:"
  echo "    update   → pull latest version from GitHub"
  echo "    bash setup.sh --force  → archive existing and reinstall"
  echo ""
  exit 1
fi

# ── archive existing before force reinstall ───────────────────────────────────
if [ "$MODE" = "force" ] && [ -f "$LOCK_FILE" ]; then
  ARCHIVE="$HOME_DIR/archive/agent-computer-backup-$(date -u +%Y%m%d-%H%M%S)"
  echo "→ Archiving existing installation to $ARCHIVE..."
  mkdir -p "$ARCHIVE"
  for f in AGENT.md CLAUDE.md; do
    [ -f "$HOME_DIR/$f" ] && cp "$HOME_DIR/$f" "$ARCHIVE/"
  done
  for d in scripts system bin; do
    [ -d "$HOME_DIR/$d" ] && cp -r "$HOME_DIR/$d" "$ARCHIVE/"
  done
  echo "  Archived. Proceeding with reinstall..."
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Agent Computer — Setup"
if [ "$MODE" = "force" ]; then
  echo "  Mode: FORCE REINSTALL"
else
  echo "  Mode: FRESH INSTALL"
fi
echo "  Target: $HOME_DIR"
echo "═══════════════════════════════════════════"

# ── create directory zones ────────────────────────────────────────────────────
echo "→ Creating directory zones..."
mkdir -p \
  "$HOME_DIR/apps" \
  "$HOME_DIR/apps/envs" \
  "$HOME_DIR/archive" \
  "$HOME_DIR/bin" \
  "$HOME_DIR/documents" \
  "$HOME_DIR/downloads" \
  "$HOME_DIR/inbox" \
  "$HOME_DIR/keys" \
  "$HOME_DIR/legal" \
  "$HOME_DIR/media/images" \
  "$HOME_DIR/media/videos" \
  "$HOME_DIR/media/audio" \
  "$HOME_DIR/media/exports" \
  "$HOME_DIR/projects" \
  "$HOME_DIR/scripts" \
  "$HOME_DIR/system"

# ── install files ─────────────────────────────────────────────────────────────
echo "→ Installing infrastructure files..."

cp "$SCRIPT_DIR/AGENT.md"  "$HOME_DIR/AGENT.md"
cp "$SCRIPT_DIR/CLAUDE.md" "$HOME_DIR/CLAUDE.md"

cp "$SCRIPT_DIR/scripts/"* "$HOME_DIR/scripts/"
cp "$SCRIPT_DIR/system/"*  "$HOME_DIR/system/"
cp "$SCRIPT_DIR/bin/"*     "$HOME_DIR/bin/"

# ── make executable ───────────────────────────────────────────────────────────
echo "→ Setting permissions..."
chmod +x "$HOME_DIR/bin/"*
chmod +x "$HOME_DIR/system/"*.sh
chmod +x "$HOME_DIR/scripts/"*.sh

# ── write version and lock file ───────────────────────────────────────────────
INSTALLED_VERSION=$(cat "$SCRIPT_DIR/VERSION")
echo "$INSTALLED_VERSION" > "$VERSION_FILE"
echo "$REPO_URL" > "$HOME_DIR/system/.update-source"

cat > "$LOCK_FILE" <<LOCK
  Installed:  $(date -u '+%Y-%m-%d %H:%M UTC')
  Version:    v$INSTALLED_VERSION
  Server:     $(hostname)
  User:       $USER
  Source:     $REPO_URL
LOCK

# ── add ~/bin to PATH ─────────────────────────────────────────────────────────
if ! grep -q '"$HOME/bin"' "$HOME_DIR/.bashrc" 2>/dev/null && ! grep -q '/home/.*bin.*PATH' "$HOME_DIR/.bashrc" 2>/dev/null; then
  echo "→ Adding ~/bin to PATH..."
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME_DIR/.bashrc"
fi

# ── add cron jobs (idempotent — never duplicates) ─────────────────────────────
echo "→ Installing cron jobs..."
EXISTING=$(crontab -l 2>/dev/null || echo "")

add_cron() {
  local job="$1" label="$2"
  echo "$EXISTING" | grep -qF "$label" || EXISTING="${EXISTING}
$job"
}

add_cron "*/5 * * * * bash $HOME_DIR/system/relocator.sh >> $HOME_DIR/system/relocator.log 2>&1" "relocator"
add_cron "0 * * * * bash $HOME_DIR/scripts/vps-map.sh >> /dev/null 2>&1" "vps-map"
add_cron "0 6 * * * bash $HOME_DIR/scripts/auto-update.sh >> $HOME_DIR/system/update.log 2>&1" "auto-update"

echo "$EXISTING" | crontab -

# ── generate initial README ───────────────────────────────────────────────────
echo "→ Generating README..."
bash "$HOME_DIR/scripts/vps-map.sh" 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════"
echo "  ✓ Agent Computer v$INSTALLED_VERSION installed!"
echo "  Run: source ~/.bashrc && boot"
echo "═══════════════════════════════════════════"
