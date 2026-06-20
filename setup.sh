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
  echo "    bash setup.sh --update  → pull latest version from GitHub"
  echo "    bash setup.sh --force   → archive existing and reinstall"
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
elif [ "$MODE" = "update" ]; then
  echo "  Mode: UPDATE"
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

# ── copy infrastructure files to root ────────────────────────────────────────
echo "→ Installing infrastructure files..."

apply() {
  local src="$SCRIPT_DIR/$1" dst="$HOME_DIR/$2"
  [ -f "$src" ] || return
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

apply "AGENT.md"                  "AGENT.md"
apply "CLAUDE.md"                 "CLAUDE.md"
apply "system/boot.sh"            "system/boot.sh"
apply "system/health.sh"          "system/health.sh"
apply "system/relocator.sh"       "system/relocator.sh"
apply "scripts/auto-update.sh"    "scripts/auto-update.sh"
apply "scripts/session-brief.sh"  "scripts/session-brief.sh"
apply "scripts/vps-map.sh"        "scripts/vps-map.sh"
apply "scripts/vps-export.sh"     "scripts/vps-export.sh"
apply "scripts/vps-sync.sh"       "scripts/vps-sync.sh"

for f in "$SCRIPT_DIR/bin/"*; do
  [ -f "$f" ] && apply "bin/$(basename "$f")" "bin/$(basename "$f")"
done

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
if ! grep -qE '(HOME/bin|\$HOME/bin|~/bin).*PATH|PATH.*(HOME/bin|\$HOME/bin|~/bin)' "$HOME_DIR/.bashrc" 2>/dev/null; then
  echo "→ Adding ~/bin to PATH in .bashrc..."
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME_DIR/.bashrc"
fi

# ── symlink ~/bin commands to /usr/local/bin (works in all shell types) ──────
# This ensures commands like boot, note, map work even in non-interactive shells
# (e.g. Claude Code's Bash tool, which doesn't source .bashrc)
echo "→ Symlinking commands to /usr/local/bin..."
for cmd in boot check map note update run export; do
  [ -f "$HOME_DIR/bin/$cmd" ] && sudo ln -sf "$HOME_DIR/bin/$cmd" "/usr/local/bin/$cmd" 2>/dev/null || true
done

# ── wire Claude Code Stop hook for auto session brief ────────────────────────
CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && ! grep -q "session-brief" "$CLAUDE_SETTINGS" 2>/dev/null; then
  echo "→ Wiring session-brief Stop hook into Claude Code settings..."
  # Insert hooks block before closing brace
  python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s.setdefault("hooks", {}).setdefault("Stop", [])
hook_cmd = "bash " + path.replace("/.claude/settings.json", "/scripts/session-brief.sh") + " 2>>/tmp/session-brief.log"
already = any(
    any(h.get("command","").startswith("bash") and "session-brief" in h.get("command","")
        for h in entry.get("hooks", []))
    for entry in s["hooks"]["Stop"]
)
if not already:
    s["hooks"]["Stop"].append({"matcher": "", "hooks": [{"type": "command", "command": hook_cmd}]})
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PYEOF
fi

# ── add cron jobs (idempotent — never duplicates) ─────────────────────────────
echo "→ Installing cron jobs..."
EXISTING=$(crontab -l 2>/dev/null || echo "")

add_cron() {
  local job="$1" label="$2"
  echo "$EXISTING" | grep -qF "$label" || EXISTING="${EXISTING}
$job"
}

# Relocator: every 15 min (not 5 — reduces noise without losing responsiveness)
add_cron "*/15 * * * * bash $HOME_DIR/system/relocator.sh >> $HOME_DIR/system/relocator.log 2>&1" "relocator"

# Map: every hour
add_cron "0 * * * * bash $HOME_DIR/scripts/vps-map.sh >> /dev/null 2>&1" "vps-map"

# Auto-update: every 15 min — git pull if available, tarball fallback
add_cron "*/15 * * * * bash $HOME_DIR/scripts/auto-update.sh >> $HOME_DIR/system/update.log 2>&1" "auto-update"

echo "$EXISTING" | crontab -

# ── generate initial README ───────────────────────────────────────────────────
echo "→ Generating README..."
bash "$HOME_DIR/scripts/vps-map.sh" 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════"
echo "  ✓ Agent Computer v$INSTALLED_VERSION installed!"
echo ""
echo "  Run: source ~/.bashrc && boot"
echo ""
echo "  Optional:"
echo "    Set up GitHub backup: edit ~/scripts/vps-sync.sh"
echo "    Add to crontab: 0 */6 * * * bash ~/scripts/vps-sync.sh >> ~/documents/sync.log 2>&1"
echo "═══════════════════════════════════════════"
