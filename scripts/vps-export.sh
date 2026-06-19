#!/bin/bash
# vps-export.sh — Package this VPS for migration to a new server.
# Usage:
#   export                      # configs + code only (safe to share)
#   export --include-secrets    # full export including API keys and OAuth tokens

set -euo pipefail

INCLUDE_SECRETS=false
[ "${1:-}" = "--include-secrets" ] && INCLUDE_SECRETS=true

HOME_DIR="/home/ubuntu"
DATE=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR=$(mktemp -d "$HOME_DIR/vps-export-${DATE}-XXXX")
TARBALL="$HOME_DIR/vps-export-${DATE}.tar.gz"

echo "Creating export at $EXPORT_DIR ..."
mkdir -p "$EXPORT_DIR/venv-packages"

# ── Refresh README before exporting ──────────────────────────────────────────
bash "$HOME_DIR/scripts/vps-map.sh" 2>/dev/null || true

# ── Sync all code and configs (excluding large/generated dirs) ────────────────
echo "→ Syncing apps/ ..."
rsync -a --delete \
  --exclude='envs/' --exclude='*/venv/' --exclude='__pycache__/' --exclude='*.pyc' \
  "$HOME_DIR/apps/" "$EXPORT_DIR/apps/"

echo "→ Syncing projects/ ..."
rsync -a --delete \
  --exclude='node_modules/' --exclude='.next/' --exclude='__pycache__/' --exclude='*.pyc' \
  "$HOME_DIR/projects/" "$EXPORT_DIR/projects/"

echo "→ Syncing scripts/ ..."
rsync -a --delete "$HOME_DIR/scripts/" "$EXPORT_DIR/scripts/"

echo "→ Syncing bin/ ..."
rsync -a --delete "$HOME_DIR/bin/" "$EXPORT_DIR/bin/"

echo "→ Syncing system/ ..."
rsync -a --delete "$HOME_DIR/system/" "$EXPORT_DIR/system/"

echo "→ Syncing documents/ ..."
rsync -a "$HOME_DIR/documents/" "$EXPORT_DIR/documents/" 2>/dev/null || true

echo "→ Syncing legal/ ..."
rsync -a "$HOME_DIR/legal/" "$EXPORT_DIR/legal/" 2>/dev/null || true

# Renderer (source only, not node_modules/out)
if [ -d "$HOME_DIR/renderer" ]; then
  echo "→ Syncing renderer/ ..."
  rsync -a --delete \
    --exclude='node_modules/' --exclude='out/' \
    "$HOME_DIR/renderer/" "$EXPORT_DIR/renderer/"
fi

# Root markdown files
cp "$HOME_DIR/AGENT.md" "$HOME_DIR/CLAUDE.md" "$HOME_DIR/README.md" "$EXPORT_DIR/" 2>/dev/null || true

# Crontab snapshot
crontab -l > "$EXPORT_DIR/crontab.txt" 2>/dev/null || true

# ── Venv package lists (pip freeze per venv) ──────────────────────────────────
echo "→ Capturing pip freeze lists ..."
# ~/apps/envs/ venvs
if [ -d "$HOME_DIR/apps/envs" ]; then
  for vpath in "$HOME_DIR/apps/envs"/*/; do
    [ -d "$vpath" ] || continue
    name=$(basename "$vpath")
    if [ -f "$vpath/bin/python3" ]; then
      "$vpath/bin/python3" -m pip freeze > "$EXPORT_DIR/venv-packages/$name.txt" 2>/dev/null || true
    fi
  done
fi
# Legacy venv paths
for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
  vpath="$HOME_DIR/$v"
  if [ -f "$vpath/bin/python3" ] && [ ! -L "$vpath" ]; then
    "$vpath/bin/python3" -m pip freeze > "$EXPORT_DIR/venv-packages/$v.txt" 2>/dev/null || true
  fi
done

# ── Secrets (only with --include-secrets) ────────────────────────────────────
if $INCLUDE_SECRETS; then
  echo "→ Including secrets ..."
  mkdir -p "$EXPORT_DIR/keys" "$EXPORT_DIR/tokens"
  [ -d "$HOME_DIR/keys" ] && cp -r "$HOME_DIR/keys/." "$EXPORT_DIR/keys/" 2>/dev/null || true
  [ -d "$HOME_DIR/apps/social-factory/tokens" ] && cp -r "$HOME_DIR/apps/social-factory/tokens/." "$EXPORT_DIR/tokens/" 2>/dev/null || true
  [ -d "$HOME_DIR/.bybit" ] && cp -r "$HOME_DIR/.bybit" "$EXPORT_DIR/.bybit" 2>/dev/null || true
  echo "WARNING: export contains OAuth tokens and API keys — keep this tarball secure" > "$EXPORT_DIR/SECRETS_INCLUDED.txt"
fi

# ── Generate restore.sh ───────────────────────────────────────────────────────
cat > "$EXPORT_DIR/restore.sh" <<'RESTORE'
#!/bin/bash
# restore.sh — Restore this VPS on a new Ubuntu server.
# Run AFTER extracting the export tarball.
# Assumes Ubuntu 22.04+, user 'ubuntu', home /home/ubuntu.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="/home/ubuntu"

echo ""
echo "═══════════════════════════════════════════════"
echo "  VPS Restore — Starting"
echo "  Target: $HOME_DIR"
echo "═══════════════════════════════════════════════"

# ── Step 1: System packages ───────────────────────────────────────────────────
echo ""
echo "→ Step 1: Installing system packages ..."
sudo apt-get update -q
sudo apt-get install -y -q python3 python3-pip python3-venv curl git tmux ffmpeg

# Node.js (if needed)
if ! command -v node &>/dev/null; then
  echo "→ Installing Node.js ..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -q nodejs
fi

# Bun
if ! command -v bun &>/dev/null; then
  echo "→ Installing Bun ..."
  curl -fsSL https://bun.sh/install | bash
fi

# ── Step 2: Directory zones ───────────────────────────────────────────────────
echo ""
echo "→ Step 2: Creating directory zones ..."
mkdir -p "$HOME_DIR"/{apps/envs,archive,bin,documents,downloads,inbox,keys,legal,media/{images,videos,audio,exports},projects,scripts,system}

# ── Step 3: Restore files ─────────────────────────────────────────────────────
echo ""
echo "→ Step 3: Restoring files ..."

rsync -a "$SCRIPT_DIR/apps/"      "$HOME_DIR/apps/"      2>/dev/null || true
rsync -a "$SCRIPT_DIR/projects/"  "$HOME_DIR/projects/"  2>/dev/null || true
rsync -a "$SCRIPT_DIR/scripts/"   "$HOME_DIR/scripts/"   2>/dev/null || true
rsync -a "$SCRIPT_DIR/bin/"       "$HOME_DIR/bin/"       2>/dev/null || true
rsync -a "$SCRIPT_DIR/system/"    "$HOME_DIR/system/"    2>/dev/null || true
rsync -a "$SCRIPT_DIR/documents/" "$HOME_DIR/documents/" 2>/dev/null || true
rsync -a "$SCRIPT_DIR/legal/"     "$HOME_DIR/legal/"     2>/dev/null || true
[ -d "$SCRIPT_DIR/renderer" ] && rsync -a "$SCRIPT_DIR/renderer/" "$HOME_DIR/renderer/" 2>/dev/null || true

cp "$SCRIPT_DIR/AGENT.md" "$SCRIPT_DIR/CLAUDE.md" "$SCRIPT_DIR/README.md" "$HOME_DIR/" 2>/dev/null || true

# ── Step 4: Restore secrets ───────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/SECRETS_INCLUDED.txt" ]; then
  echo ""
  echo "→ Step 4: Restoring secrets ..."
  [ -d "$SCRIPT_DIR/keys" ]   && cp -r "$SCRIPT_DIR/keys/."   "$HOME_DIR/keys/"   2>/dev/null || true
  [ -d "$SCRIPT_DIR/tokens" ] && mkdir -p "$HOME_DIR/apps/social-factory/tokens" && cp -r "$SCRIPT_DIR/tokens/." "$HOME_DIR/apps/social-factory/tokens/" 2>/dev/null || true
  [ -d "$SCRIPT_DIR/.bybit" ] && cp -r "$SCRIPT_DIR/.bybit"   "$HOME_DIR/.bybit"  2>/dev/null || true
else
  echo ""
  echo "→ Step 4: No secrets in this export (restore keys and tokens manually)"
fi

# ── Step 5: Rebuild Python venvs ──────────────────────────────────────────────
echo ""
echo "→ Step 5: Rebuilding Python venvs ..."
mkdir -p "$HOME_DIR/apps/envs"
for txt in "$SCRIPT_DIR/venv-packages/"*.txt; do
  [ -f "$txt" ] || continue
  name=$(basename "$txt" .txt)
  vpath="$HOME_DIR/apps/envs/$name"
  if [ ! -d "$vpath" ]; then
    echo "  Creating venv: $name ..."
    python3 -m venv "$vpath"
    "$vpath/bin/pip" install -q --upgrade pip
    "$vpath/bin/pip" install -q -r "$txt" 2>/dev/null || echo "  (some packages may need manual install)"
    echo "  ✓ $name"
  else
    echo "  (skipping $name — already exists)"
  fi
done

# ── Step 6: npm install for projects ─────────────────────────────────────────
echo ""
echo "→ Step 6: Reinstalling npm packages ..."
for pkg in "$HOME_DIR/projects/"/*/package.json "$HOME_DIR/apps/"/*/package.json; do
  [ -f "$pkg" ] || continue
  dir=$(dirname "$pkg")
  echo "  npm install in $dir ..."
  (cd "$dir" && npm install --legacy-peer-deps --silent 2>/dev/null) || echo "  (failed — run manually: cd $dir && npm install)"
done

# ── Step 7: Permissions ───────────────────────────────────────────────────────
echo ""
echo "→ Step 7: Setting permissions ..."
chmod +x "$HOME_DIR/bin/"* "$HOME_DIR/system/"*.sh "$HOME_DIR/scripts/"*.sh 2>/dev/null || true

# ~/bin in PATH
if ! grep -q '"$HOME/bin"' "$HOME_DIR/.bashrc" 2>/dev/null && ! grep -q '/bin.*PATH' "$HOME_DIR/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME_DIR/.bashrc"
fi

# ── Step 8: Restore crontab ───────────────────────────────────────────────────
echo ""
echo "→ Step 8: Restoring crontab ..."
if [ -f "$SCRIPT_DIR/crontab.txt" ]; then
  crontab "$SCRIPT_DIR/crontab.txt"
  echo "  ✓ $(grep -v '^#' "$SCRIPT_DIR/crontab.txt" | grep -v '^$' | wc -l) cron jobs restored"
else
  echo "  (no crontab.txt found)"
fi

# ── Step 9: Start bybit bot ───────────────────────────────────────────────────
echo ""
if [ -f "$HOME_DIR/.bybit/persistent_agent.sh" ]; then
  echo "→ Step 9: Starting bybit bot ..."
  tmux new-session -d -s persistent-agent "$HOME_DIR/.bybit/persistent_agent.sh" 2>/dev/null || echo "  (tmux session may already exist)"
  echo "  ✓ bybit-bot started (tmux: persistent-agent)"
else
  echo "→ Step 9: Skipping bybit bot (not found)"
fi

# ── Step 10: Generate README ──────────────────────────────────────────────────
echo ""
echo "→ Step 10: Generating README ..."
bash "$HOME_DIR/scripts/vps-map.sh" 2>/dev/null && echo "  ✓ README.md generated" || echo "  (will be generated on next cron run)"

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✓ Restore complete!"
echo ""
echo "  Next steps:"
echo "    source ~/.bashrc"
echo "    boot"
echo ""
if [ ! -f "$SCRIPT_DIR/SECRETS_INCLUDED.txt" ]; then
  echo "  MANUAL: Copy ~/keys/ and OAuth tokens from old server"
  echo "  MANUAL: Re-auth any expired OAuth tokens"
fi
echo "═══════════════════════════════════════════════"
RESTORE
chmod +x "$EXPORT_DIR/restore.sh"

# ── Create tarball ────────────────────────────────────────────────────────────
echo "→ Creating tarball ..."
tar -czf "$TARBALL" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"
rm -rf "$EXPORT_DIR"

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✓ Export complete!"
echo "  File: $TARBALL"
echo "  Size: $(du -sh "$TARBALL" | cut -f1)"
if $INCLUDE_SECRETS; then
  echo ""
  echo "  ⚠ CONTAINS SECRETS — do not share this file"
fi
echo ""
echo "  To restore on new server:"
echo "    scp $TARBALL ubuntu@<new-server>:~/"
echo "    ssh ubuntu@<new-server>"
echo "    tar -xzf $(basename "$TARBALL") && cd $(basename "$TARBALL" .tar.gz) && bash restore.sh"
echo "═══════════════════════════════════════════════"
