#!/bin/bash
# vps-export.sh — Packages everything needed to restore this VPS on a new server.
# Usage:
#   bash ~/tools/scripts/vps-export.sh                   # configs only (safe to share)
#   bash ~/tools/scripts/vps-export.sh --include-secrets # full export incl. tokens + keys

set -euo pipefail

INCLUDE_SECRETS=false
[ "${1:-}" = "--include-secrets" ] && INCLUDE_SECRETS=true

HOME_DIR="/home/ubuntu"
YT_DIR="$HOME_DIR/agents/youtube"
DATE=$(date +%Y%m%d_%H%M%S)
EXPORT_DIR="$HOME_DIR/vps-export-$DATE"
TARBALL="$HOME_DIR/vps-export-$DATE.tar.gz"

echo "Creating export at $EXPORT_DIR ..."
mkdir -p "$EXPORT_DIR/configs" "$EXPORT_DIR/tokens" "$EXPORT_DIR/keys"

# ── README + CLAUDE.md ──────────────────────────────────────────────────────
# Refresh README before exporting
bash "$HOME_DIR/tools/scripts/vps-map.sh" 2>/dev/null || true
cp "$HOME_DIR/README.md" "$EXPORT_DIR/"
cp "$HOME_DIR/CLAUDE.md" "$EXPORT_DIR/"

# ── crontab ─────────────────────────────────────────────────────────────────
crontab -l > "$EXPORT_DIR/crontab.txt" 2>/dev/null || echo "# empty" > "$EXPORT_DIR/crontab.txt"

# ── channel configs (secrets redacted unless --include-secrets) ─────────────
for slug in aura-clips crvgrowth curiosity-files; do
  src="$YT_DIR/channels/$slug/config.json"
  dst="$EXPORT_DIR/configs/$slug.json"
  if [ ! -f "$src" ]; then
    echo "WARNING: $src not found, skipping"
    continue
  fi
  if $INCLUDE_SECRETS; then
    cp "$src" "$dst"
  else
    python3 - <<PYEOF
import json
with open("$src") as f:
    d = json.load(f)
secret_fields = ["pexels_key", "elevenlabs_key", "notify_webhook"]
for k in secret_fields:
    if k in d:
        d[k] = "REDACTED"
if "platforms" in d:
    for p, v in d["platforms"].items():
        if isinstance(v, dict) and "token" in v:
            v["token"] = "REDACTED"
with open("$dst", "w") as f:
    json.dump(d, f, indent=2)
PYEOF
  fi
done

# ── tokens (only with --include-secrets) ────────────────────────────────────
if $INCLUDE_SECRETS; then
  cp -r "$YT_DIR/tokens/"* "$EXPORT_DIR/tokens/" 2>/dev/null || true
  cp "$HOME_DIR/keys/"* "$EXPORT_DIR/keys/" 2>/dev/null || true
  echo "WARNING: export contains OAuth tokens and API keys — keep this tarball secure" > "$EXPORT_DIR/SECRETS_INCLUDED.txt"
fi

# ── venv dependency snapshots ────────────────────────────────────────────────
{
  echo "# Python venv dependencies snapshot — $DATE"
  echo "# Reinstall with: pip install -r venvs.txt (per venv)"
  echo ""
  for v in venv yt-upload-venv tg-agent-env antigravity-bot-venv; do
    if [ -f "$HOME_DIR/$v/bin/pip" ]; then
      echo "## $v"
      "$HOME_DIR/$v/bin/pip" freeze 2>/dev/null || echo "# (freeze failed)"
      echo ""
    else
      echo "## $v — NOT FOUND at $HOME_DIR/$v"
      echo ""
    fi
  done
} > "$EXPORT_DIR/venvs.txt"

# ── manifest.json ────────────────────────────────────────────────────────────
python3 - <<PYEOF
import json, os, subprocess, datetime

channels = []
for slug in ["aura-clips", "crvgrowth", "curiosity-files"]:
    cfg_path = f"$YT_DIR/channels/{slug}/config.json"
    try:
        with open(cfg_path) as f:
            cfg = json.load(f)
        channels.append({
            "slug": slug,
            "niche": cfg.get("niche", ""),
            "theme": cfg.get("video_theme", ""),
            "voice": cfg.get("voice", ""),
            "project_dir": cfg.get("project_dir", ""),
        })
    except Exception as e:
        channels.append({"slug": slug, "error": str(e)})

try:
    cron = subprocess.check_output(["crontab", "-l"], text=True)
except:
    cron = ""

try:
    tmux = subprocess.check_output(["tmux", "ls"], text=True)
except:
    tmux = ""

try:
    df = subprocess.check_output(["df", "-h", "$HOME_DIR"], text=True)
except:
    df = ""

manifest = {
    "exported_at": datetime.datetime.utcnow().isoformat() + "Z",
    "include_secrets": $( $INCLUDE_SECRETS && echo 'True' || echo 'False'),
    "server": {
        "home": "$HOME_DIR",
        "disk": df.splitlines()[1] if len(df.splitlines()) > 1 else "",
    },
    "agents": {
        "youtube": "$YT_DIR",
        "trading": "$HOME_DIR/agents/trading",
        "telegram": "$HOME_DIR/agents/telegram",
    },
    "renderer": "$HOME_DIR/renderer",
    "channels": channels,
    "cron_jobs": [l for l in cron.splitlines() if l.strip() and not l.startswith("#")],
    "tmux_sessions": [l.split(":")[0] for l in tmux.splitlines() if ":" in l],
    "venvs": {
        "venv": "$HOME_DIR/venv",
        "yt-upload-venv": "$HOME_DIR/yt-upload-venv",
        "tg-agent-env": "$HOME_DIR/tg-agent-env",
        "antigravity-bot-venv": "$HOME_DIR/antigravity-bot-venv",
    },
    "restore_steps": [
        "1. Copy ~/agents/, ~/projects/, ~/renderer/, ~/tools/, ~/keys/ to new server",
        "2. Restore crontab: crontab < crontab.txt",
        "3. Recreate venvs using venvs.txt (pip install per venv section)",
        "4. If --include-secrets: restore tokens/ → ~/agents/youtube/tokens/ and keys/ → ~/keys/",
        "5. Re-auth any expired OAuth tokens via ~/tools/auth/auth_google.py",
        "6. Start trading bot: tmux new-session -d -s persistent-agent '/home/ubuntu/.bybit/persistent_agent.sh'",
        "7. Run test: /home/ubuntu/apps/social-factory/scripts/run.sh aura-clips short --no-upload",
    ]
}

with open("$EXPORT_DIR/manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)
print("manifest.json written")
PYEOF

# ── setup.sh (restore script for new server) ────────────────────────────────
cat > "$EXPORT_DIR/setup.sh" <<'SETUP'
#!/bin/bash
# setup.sh — Idempotent restore script for a new Ubuntu server.
# Run this AFTER copying the export directory to the new server.
# Assumes Ubuntu 22.04+, user is 'ubuntu', home is /home/ubuntu.

set -euo pipefail
HOME_DIR="/home/ubuntu"

echo "=== VPS Restore Setup ==="

# Create directory structure
echo "Creating directories..."
mkdir -p "$HOME_DIR/agents/youtube/channels"
mkdir -p "$HOME_DIR/agents/youtube/tokens"
mkdir -p "$HOME_DIR/agents/youtube/scripts"
mkdir -p "$HOME_DIR/agents/trading"
mkdir -p "$HOME_DIR/agents/telegram"
mkdir -p "$HOME_DIR/projects/altaris-capital"
mkdir -p "$HOME_DIR/projects/web3-dapp"
mkdir -p "$HOME_DIR/projects/content-creator-skill"
mkdir -p "$HOME_DIR/renderer"
mkdir -p "$HOME_DIR/tools/auth"
mkdir -p "$HOME_DIR/tools/scripts"
mkdir -p "$HOME_DIR/keys"
mkdir -p "$HOME_DIR/archive"
mkdir -p "$HOME_DIR/legal"

echo "Directory structure created."

# Restore crontab
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/crontab.txt" ]; then
  echo "Restoring crontab..."
  crontab "$SCRIPT_DIR/crontab.txt"
  echo "Crontab restored ($(grep -v '^#' "$SCRIPT_DIR/crontab.txt" | grep -v '^$' | wc -l) active jobs)"
fi

# Copy CLAUDE.md and README.md
cp "$SCRIPT_DIR/CLAUDE.md" "$HOME_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/README.md" "$HOME_DIR/" 2>/dev/null || true

echo ""
echo "=== TODO (manual steps) ========================="
echo "1. Clone repos into the directories above:"
echo "   git clone <youtube-factory-repo> $HOME_DIR/agents/youtube"
echo "   git clone <renderer-repo> $HOME_DIR/renderer"
echo ""
echo "2. Recreate Python venvs (see venvs.txt):"
echo "   python3 -m venv $HOME_DIR/yt-upload-venv"
echo "   $HOME_DIR/yt-upload-venv/bin/pip install <packages from venvs.txt ## yt-upload-venv section>"
echo ""
echo "3. Restore OAuth tokens:"
echo "   Copy tokens/ → $HOME_DIR/agents/youtube/tokens/"
echo "   Copy keys/   → $HOME_DIR/keys/"
echo ""
echo "4. Install system deps: nodejs, bun, ffmpeg, chromium"
echo "   curl -fsSL https://bun.sh/install | bash"
echo "   sudo apt install -y ffmpeg chromium-browser"
echo ""
echo "5. Start trading bot:"
echo "   tmux new-session -d -s persistent-agent '/home/ubuntu/.bybit/persistent_agent.sh'"
echo ""
echo "6. Test YouTube pipeline:"
echo "   /home/ubuntu/apps/social-factory/scripts/run.sh aura-clips short --no-upload"
echo ""
echo "=== Setup complete ==="
SETUP
chmod +x "$EXPORT_DIR/setup.sh"

# ── tarball ──────────────────────────────────────────────────────────────────
tar -czf "$TARBALL" -C "$HOME_DIR" "$(basename "$EXPORT_DIR")"
rm -rf "$EXPORT_DIR"

echo ""
echo "Export complete: $TARBALL"
echo "Size: $(du -sh "$TARBALL" | cut -f1)"
if $INCLUDE_SECRETS; then
  echo "CONTAINS SECRETS — keep this file secure and do not share"
fi
echo ""
echo "To use on new server:"
echo "  scp $TARBALL ubuntu@<new-server>:~/"
echo "  ssh ubuntu@<new-server>"
echo "  tar -xzf $(basename "$TARBALL") && cd $(basename "$EXPORT_DIR") && bash setup.sh"
