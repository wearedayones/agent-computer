#!/bin/bash
# Agent Computer — Installer
# https://github.com/wearedayones/agent-computer
#
# Quick install (one line):
#   bash <(curl -fsSL https://raw.githubusercontent.com/wearedayones/agent-computer/main/setup.sh)
#
# Options:
#   --update   update existing installation to latest version
#   --force    reinstall over existing (archives current first)
#   --uninstall  remove Agent Computer from this server

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO="wearedayones/agent-computer"
REPO_URL="https://github.com/$REPO"
RAW_URL="https://raw.githubusercontent.com/$REPO/main"
TARBALL_URL="$REPO_URL/archive/refs/heads/main.tar.gz"
HOME_DIR="$HOME"
LOCK_FILE="$HOME_DIR/system/.installed"
VERSION_FILE="$HOME_DIR/system/.version"
UPDATE_SOURCE="$HOME_DIR/system/.update-source"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── UI helpers ────────────────────────────────────────────────────────────────
banner() {
  echo -e "\n${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║         Agent Computer — Installer       ║"
  echo "  ║         $REPO         ║"
  echo "  ╚══════════════════════════════════════════╝${NC}"
  echo ""
}
phase()   { echo -e "\n${BOLD}${BLUE}  $*${NC}"; }
step()    { echo -e "  ${DIM}→${NC}  $*"; }
ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
abort()   { echo -e "\n  ${RED}✗  $*${NC}\n"; exit 1; }
divider() { echo -e "  ${DIM}──────────────────────────────────────────${NC}"; }

# ── Parse flags ───────────────────────────────────────────────────────────────
MODE="install"
for arg in "$@"; do
  case "$arg" in
    --update)    MODE="update"    ;;
    --force)     MODE="force"     ;;
    --uninstall) MODE="uninstall" ;;
  esac
done

# ── Bootstrap: self-download if run via curl (no sibling files) ───────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ ! -f "$SCRIPT_DIR/AGENT.md" ]; then
  banner
  phase "Bootstrapping..."
  step "Downloading package from GitHub..."

  BOOT_TMP=$(mktemp -d)
  trap "rm -rf $BOOT_TMP" EXIT

  curl -fsSL --progress-bar "$TARBALL_URL" -o "$BOOT_TMP/pkg.tar.gz" \
    || abort "Download failed — check your internet connection."

  tar -xzf "$BOOT_TMP/pkg.tar.gz" -C "$BOOT_TMP" \
    || abort "Extraction failed."

  PKG_DIR="$BOOT_TMP/$(ls "$BOOT_TMP" | grep -v pkg.tar.gz | head -1)"
  ok "Package ready"

  # Re-execute the real setup.sh from inside the extracted package
  exec bash "$PKG_DIR/setup.sh" "$@"
fi

# ── From here: running from inside the package (repo or extracted tarball) ────
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

banner
echo -e "  Version : ${BOLD}v$VERSION${NC}"
echo -e "  Target  : ${BOLD}$HOME_DIR${NC}"
echo -e "  Mode    : ${BOLD}$(echo $MODE | tr '[:lower:]' '[:upper:]')${NC}"
divider

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "uninstall" ]; then
  phase "Uninstalling..."
  if [ ! -f "$LOCK_FILE" ]; then
    abort "Agent Computer is not installed on this server."
  fi
  ARCHIVE="$HOME_DIR/archive/agent-computer-$(date -u +%Y%m%d-%H%M%S)"
  step "Archiving to $ARCHIVE..."
  mkdir -p "$ARCHIVE"
  for f in AGENT.md CLAUDE.md; do [ -f "$HOME_DIR/$f" ] && cp "$HOME_DIR/$f" "$ARCHIVE/"; done
  for d in bin scripts system; do [ -d "$HOME_DIR/$d" ] && cp -r "$HOME_DIR/$d" "$ARCHIVE/"; done
  # Remove cron jobs added by this installer
  crontab -l 2>/dev/null | grep -v "relocator\|vps-map\|auto-update" | crontab - 2>/dev/null || true
  rm -f "$LOCK_FILE" "$VERSION_FILE" "$UPDATE_SOURCE"
  ok "Archived to $ARCHIVE"
  ok "Cron jobs removed"
  warn "Directory zones (apps/, projects/, etc.) kept — your data is untouched."
  echo -e "\n  ${GREEN}Agent Computer uninstalled.${NC}\n"
  exit 0
fi

# ── Singleton guard ───────────────────────────────────────────────────────────
if [ -f "$LOCK_FILE" ] && [ "$MODE" = "install" ]; then
  echo -e "  ${YELLOW}Agent Computer is already installed on this server.${NC}\n"
  cat "$LOCK_FILE"
  echo ""
  echo "  To update  : bash setup.sh --update"
  echo "  To reinstall: bash setup.sh --force"
  echo ""
  exit 1
fi

# ── Archive before force reinstall ───────────────────────────────────────────
if [ "$MODE" = "force" ] && [ -f "$LOCK_FILE" ]; then
  phase "Archiving existing installation..."
  ARCHIVE="$HOME_DIR/archive/agent-computer-$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$ARCHIVE"
  for f in AGENT.md CLAUDE.md; do [ -f "$HOME_DIR/$f" ] && cp "$HOME_DIR/$f" "$ARCHIVE/"; done
  for d in bin scripts system; do [ -d "$HOME_DIR/$d" ] && cp -r "$HOME_DIR/$d" "$ARCHIVE/"; done
  ok "Backed up to ~/archive/$(basename "$ARCHIVE")"
fi

# ── Phase 1: Requirements ─────────────────────────────────────────────────────
phase "Checking requirements..."

check_cmd() {
  local cmd="$1" note="${2:-}"
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd  ${DIM}$(command -v $cmd)${NC}"
  else
    [ -n "$note" ] && warn "$cmd not found — $note" || abort "$cmd is required but not installed."
  fi
}

check_cmd "bash"
check_cmd "curl"
check_cmd "git"   "optional — needed only for ~/projects/ work"
check_cmd "python3" "optional — needed for Claude Code hook wiring"
check_cmd "tmux"  "optional — recommended for persistent sessions"

# ── Phase 2: Directory zones ──────────────────────────────────────────────────
phase "Creating directory structure..."

ZONES=(
  apps apps/envs archive bin documents downloads
  inbox keys legal media/images media/videos media/audio
  media/exports projects scripts system
  skills plugins
)
for zone in "${ZONES[@]}"; do
  mkdir -p "$HOME_DIR/$zone"
done
ok "${#ZONES[@]} zones ready"

# ── Phase 3: Install infrastructure files ─────────────────────────────────────
phase "Installing infrastructure files..."

apply() {
  local src="$SCRIPT_DIR/$1" dst="$HOME_DIR/$2"
  [ -f "$src" ] || return
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo -e "  ${GREEN}✓${NC}  ${DIM}~/$2${NC}"
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

chmod +x "$HOME_DIR/bin/"* "$HOME_DIR/system/"*.sh "$HOME_DIR/scripts/"*.sh 2>/dev/null

# ── Phase 4: PATH ─────────────────────────────────────────────────────────────
phase "Configuring PATH..."

# ~/.bashrc for interactive shells
if ! grep -qE '(HOME/bin|\$HOME/bin|~/bin)' "$HOME_DIR/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME_DIR/.bashrc"
  ok "Added ~/bin to ~/.bashrc"
else
  ok "~/bin already in ~/.bashrc"
fi

# /usr/local/bin for all shell types (non-interactive, Claude Code, cron, etc.)
# v4.0 internal scripts (axis subcommands only — not standalone): envdata ctx trace metric
AXIS_ONLY="envdata ctx trace metric"
LINKED=0
for cmd in "$HOME_DIR/bin/"*; do
  fname="$(basename "$cmd")"
  echo "$AXIS_ONLY" | grep -qw "$fname" && continue
  if sudo ln -sf "$cmd" "/usr/local/bin/$fname" 2>/dev/null; then
    LINKED=$((LINKED + 1))
  fi
done
[ "$LINKED" -gt 0 ] && ok "$LINKED commands linked to /usr/local/bin" \
  || warn "Could not link to /usr/local/bin (no sudo) — commands work in login shells only"

# axis bash completion
COMPLETION="$HOME_DIR/system/axis-completion.bash"
if [ -f "$COMPLETION" ]; then
  if sudo cp "$COMPLETION" /etc/bash_completion.d/axis 2>/dev/null; then
    ok "axis tab-completion installed"
  fi
  grep -q "axis-completion" "$HOME_DIR/.bashrc" 2>/dev/null \
    || echo "source $COMPLETION" >> "$HOME_DIR/.bashrc"
fi

# / root — machine-level discovery (any agent on this computer, any user)
ROOT_LINKED=0
for doc in AGENT.md CLAUDE.md README.md; do
  if sudo ln -sf "$HOME_DIR/$doc" "/$doc" 2>/dev/null; then
    ROOT_LINKED=$((ROOT_LINKED + 1))
  fi
done
[ "$ROOT_LINKED" -gt 0 ] && ok "AGENT.md, CLAUDE.md, README.md linked to / (machine-level)" \
  || warn "Could not link docs to / (no sudo) — discoverable at ~/AGENT.md only"

# ── Phase 5: Claude Code integration ─────────────────────────────────────────
phase "Configuring Claude Code integration..."

CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && command -v python3 &>/dev/null; then
  if ! grep -q "session-brief" "$CLAUDE_SETTINGS" 2>/dev/null; then
    python3 - "$CLAUDE_SETTINGS" "$HOME_DIR/scripts/session-brief.sh" <<'PYEOF'
import json, sys
path, brief_path = sys.argv[1], sys.argv[2]
with open(path) as f:
    s = json.load(f)
s.setdefault("hooks", {}).setdefault("Stop", [])
hook_cmd = f"bash {brief_path} 2>>/tmp/session-brief.log"
already = any(
    any("session-brief" in h.get("command", "") for h in e.get("hooks", []))
    for e in s["hooks"]["Stop"]
)
if not already:
    s["hooks"]["Stop"].append({"matcher": "", "hooks": [{"type": "command", "command": hook_cmd}]})
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
PYEOF
    ok "Session auto-brief wired into Claude Code"
  else
    ok "Claude Code hook already configured"
  fi
elif [ ! -f "$CLAUDE_SETTINGS" ]; then
  warn "Claude Code not found — skipping hook setup (safe, can add later)"
fi

# ── Phase 6: Cron jobs ────────────────────────────────────────────────────────
phase "Installing background jobs..."

CRONTAB=$(crontab -l 2>/dev/null || echo "")

add_cron() {
  local job="$1" label="$2"
  if echo "$CRONTAB" | grep -qF "$label"; then
    ok "$label  ${DIM}(already set)${NC}"
  else
    CRONTAB="$CRONTAB
$job"
    ok "$label"
  fi
}

add_cron "*/15 * * * * bash $HOME_DIR/system/relocator.sh >> $HOME_DIR/system/relocator.log 2>&1"  "relocator   (every 15 min — keeps zones tidy)"
add_cron "0 * * * * bash $HOME_DIR/scripts/vps-map.sh >> /dev/null 2>&1"                           "vps-map     (every hour  — refreshes README)"
add_cron "*/15 * * * * bash $HOME_DIR/scripts/auto-update.sh >> $HOME_DIR/system/update.log 2>&1"  "auto-update (every 15 min — pulls latest from GitHub)"

echo "$CRONTAB" | crontab -

# ── Phase 7: Finalize ─────────────────────────────────────────────────────────
phase "Finalizing..."

echo "$VERSION" > "$VERSION_FILE"
echo "$REPO_URL" > "$UPDATE_SOURCE"

cat > "$LOCK_FILE" <<LOCK
  Installed : $(date -u '+%Y-%m-%d %H:%M UTC')
  Version   : v$VERSION
  Server    : $(hostname)
  User      : $USER
  Source    : $REPO_URL
LOCK

step "Generating README..."
bash "$HOME_DIR/scripts/vps-map.sh" 2>/dev/null || true
ok "README generated"

# ── Done ──────────────────────────────────────────────────────────────────────
divider
echo -e "\n  ${BOLD}${GREEN}✓  Agent Computer v$VERSION installed successfully!${NC}\n"
echo -e "  ${BOLD}Next step:${NC}"
echo -e "    source ~/.bashrc && boot\n"
echo -e "  ${DIM}Commands available: boot  check  map  note  update  run  export${NC}"
echo -e "  ${DIM}Auto-updates from GitHub every 15 minutes.${NC}\n"
divider
echo ""
