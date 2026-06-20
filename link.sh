#!/bin/bash
# link.sh — symlink all computer infrastructure files to their live locations
# Run after install or after adding new files to the repo.
# Safe to re-run: replaces existing files/symlinks, never touches user data.

set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

link() {
  local src="$REPO_DIR/$1" dst="$HOME_DIR/$2"
  mkdir -p "$(dirname "$dst")"
  # Remove existing file or symlink (but never a directory)
  [ -f "$dst" ] && rm -f "$dst"
  [ -L "$dst" ] && rm -f "$dst"
  ln -s "$src" "$dst"
  echo -e "  ${GREEN}✓${NC}  ~/$2"
}

echo ""
echo "── Linking agent-computer files to live locations ──"

# Root docs
link "CLAUDE.md"  "CLAUDE.md"
link "AGENT.md"   "AGENT.md"

# System
link "system/boot.sh"       "system/boot.sh"
link "system/health.sh"     "system/health.sh"
link "system/relocator.sh"  "system/relocator.sh"

# Scripts
link "scripts/auto-update.sh"    "scripts/auto-update.sh"
link "scripts/session-brief.sh"  "scripts/session-brief.sh"
link "scripts/vps-map.sh"        "scripts/vps-map.sh"
link "scripts/vps-export.sh"     "scripts/vps-export.sh"
link "scripts/vps-sync.sh"       "scripts/vps-sync.sh"

# Bin commands
for f in "$REPO_DIR/bin/"*; do
  fname="$(basename "$f")"
  link "bin/$fname" "bin/$fname"
done

# Ensure bin commands are executable and in system PATH
chmod +x "$REPO_DIR/bin/"* "$REPO_DIR/system/"*.sh "$REPO_DIR/scripts/"*.sh
for cmd in "$REPO_DIR/bin/"*; do
  fname="$(basename "$cmd")"
  sudo ln -sf "$cmd" "/usr/local/bin/$fname" 2>/dev/null && true
done

echo -e "\n  ${YELLOW}All linked. Edit files in the repo — changes are live instantly.${NC}"
echo -e "  To publish: cd $REPO_DIR && git commit -am \"msg\" && git push\n"
