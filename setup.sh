#!/bin/bash
# setup.sh — install Agent Computer on a fresh Ubuntu VPS
# Usage: bash setup.sh [--repo-url <github-url>]
# Or one-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/wearedayones/agent-computer/main/setup.sh)

set -e

REPO_URL="${REPO_URL:-https://github.com/wearedayones/agent-computer}"
HOME_DIR="$HOME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "═══════════════════════════════════════════"
echo "  Agent Computer — Setup"
echo "  Installing to: $HOME_DIR"
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

# ── version tracking ──────────────────────────────────────────────────────────
cp "$SCRIPT_DIR/VERSION" "$HOME_DIR/system/.version"
echo "$REPO_URL" > "$HOME_DIR/system/.update-source"

# ── add ~/bin to PATH ─────────────────────────────────────────────────────────
if ! grep -q 'home/.*bin.*PATH' "$HOME_DIR/.bashrc" 2>/dev/null; then
  echo "→ Adding ~/bin to PATH..."
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME_DIR/.bashrc"
fi

# ── add cron jobs ─────────────────────────────────────────────────────────────
echo "→ Installing cron jobs..."
EXISTING=$(crontab -l 2>/dev/null || echo "")

add_cron() {
  local job="$1"
  local label="$2"
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
echo "  ✓ Agent Computer installed!"
echo "  Run 'source ~/.bashrc && boot' to start"
echo "═══════════════════════════════════════════"
