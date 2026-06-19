# Agent Computer
> Universal operating guide. Any agent — read this entire file before doing anything.
> Live system state: `README.md` (auto-generated, always current).

---

## 60-Second Orientation

```bash
boot    # run this first — disk, apps, inbox, last 3 changes, quick commands
```

After `boot`: check README.md alerts → fix any FAILED/STOPPED/MISSING items → do your work → run `map`.

---

## Shell Commands (`~/bin/` — all in PATH)

| Command | Action |
|---------|--------|
| `boot` | Session startup: disk, apps, inbox, last changes, command list |
| `check` | Full color health report (disk · apps · channels · venvs · keys · inbox) |
| `map` | Regenerate README.md from live state |
| `update` | Pull latest agent-computer infrastructure from GitHub |
| `note "msg"` | Leave a message for the next agent in `~/inbox/` |
| `export` | Package computer for server migration (configs only) |
| `export --include-secrets` | Full export including API keys and OAuth tokens |

---

## Zone Map

| What | Where | Example |
|------|-------|---------|
| New autonomous app / bot | `~/apps/<name>/` | `~/apps/my-bot/` |
| New development project | `~/projects/<name>/` | `~/projects/my-app/` |
| New script or utility | `~/scripts/` | `~/scripts/cleanup.sh` |
| Notes, guides, references | `~/documents/` | `~/documents/guide.md` |
| Images / thumbnails | `~/media/images/` | `~/media/images/hero.png` |
| Videos / clips | `~/media/videos/` | `~/media/videos/intro.mp4` |
| Audio / music | `~/media/audio/` | `~/media/audio/bgm.mp3` |
| Rendered / exported output | `~/media/exports/` | `~/media/exports/final.mp4` |
| Temp / downloaded content | `~/downloads/` | `~/downloads/import.zip` |
| API keys and credentials | `~/keys/` | `~/keys/openai.txt` |
| Python venvs (shared) | `~/apps/envs/` | `~/apps/envs/my-bot-venv/` |
| **Root (`~/`)** | **NEVER** | Nothing goes here |

---

## House Rules — Never Break These

### 1. Files live in zones
Never drop files at `~/` root. Always use a zone.
```bash
mkdir ~/media/screenshots   # new subfolder inside a zone — OK
# NEVER: mkdir ~/screenshots  (at root — WRONG)
```
**Naming:** lowercase and hyphens only. No spaces, no underscores, no capitals.

### 2. Archive before deleting
```bash
mv ~/apps/old-bot ~/archive/old-bot    # archive first
# rm -rf ~/apps/old-bot                # NEVER skip archiving
```

### 3. Update the map after any change
```bash
map
```
Run after: adding apps, moving files, changing cron, installing packages, editing configs.

### 4. Never touch these
- `~/keys/` — read-only; never write or delete
- `~/.hermes/` — managed by Hermes; hands off
- `~/.bybit/` — trading bot credentials and live state; never touch
- `~/apps/social-factory/tokens/` — OAuth tokens; read-only

---

## Computer Layout

| Zone | Path | Purpose |
|------|------|---------|
| **Apps** | `~/apps/` | Autonomous apps that run 24/7 |
| **Projects** | `~/projects/` | Active development work |
| **Scripts** | `~/scripts/` | Tools and utilities |
| **Documents** | `~/documents/` | Guides, notes, references |
| **Media** | `~/media/` | images/ · videos/ · audio/ · exports/ |
| **Downloads** | `~/downloads/` | Temporary fetched content (safe to clear) |
| **Keys** | `~/keys/` | API credentials (never commit, never log) |
| **Archive** | `~/archive/` | Old versions (safe to ignore) |
| **Bin** | `~/bin/` | Shell command aliases (all in PATH) |
| **System** | `~/system/` | Health, boot, relocator, version tracking |
| **Inbox** | `~/inbox/` | Inter-agent messages |
| **App venvs** | `~/apps/envs/` | Shared Python virtual environments |

Root only contains: `AGENT.md`, `CLAUDE.md`, `README.md`

---

## App Registry

### social-factory (YouTube + TikTok automation)

```bash
# Location
~/apps/social-factory/

# Test pipeline (no upload)
~/apps/social-factory/scripts/run.sh <channel> short --no-upload
~/apps/social-factory/scripts/run.sh <channel> long --no-upload

# Upload now
~/apps/social-factory/scripts/run.sh <channel> short
~/apps/social-factory/scripts/run.sh <channel> long 1900   # schedule for 19:00 UTC

# Check channel logs
tail -50 ~/apps/social-factory/channels/<channel>/state/pipeline.log

# List channels
ls ~/apps/social-factory/channels/

# Tokens (OAuth — read only, never delete)
ls ~/apps/social-factory/tokens/

# Config for a channel
cat ~/apps/social-factory/channels/<channel>/config.json
```

### bybit-bot (trading)

```bash
# Check status
tmux has-session -t persistent-agent && echo running || echo STOPPED

# Start if stopped
tmux new-session -d -s persistent-agent '~/.bybit/persistent_agent.sh'

# Attach and watch
tmux attach -t persistent-agent
# Detach: Ctrl+B then D

# State and logs
ls ~/.bybit/
```

> **Mainnet trades (real money) — always confirm with the owner before placing.**

### telegram

```bash
# Check status
pgrep -f "alex.py\|antigravity_bot" && echo running || echo stopped

# App location
ls ~/apps/telegram/
```

---

## Python Venvs

Shared venvs live in `~/apps/envs/`:
```bash
ls ~/apps/envs/                              # list all venvs
source ~/apps/envs/sf-venv/bin/activate     # activate one
deactivate                                   # deactivate
```

Install packages into the correct venv — never into the system Python:
```bash
~/apps/envs/sf-venv/bin/pip install <package>
```

---

## Inter-Agent Messaging

Leave messages for the next agent in `~/inbox/`:
```bash
note "finished token refresh for aura-clips — all channels healthy"
note "bybit bot was STOPPED — restarted at 14:30 UTC, investigate why it stopped"

ls ~/inbox/         # list all messages
cat ~/inbox/*.md    # read all messages
```

`boot` shows inbox messages automatically on arrival.

---

## Fixing Common Problems

### bybit-bot stopped
```bash
tmux new-session -d -s persistent-agent '~/.bybit/persistent_agent.sh'
note "bybit-bot was STOPPED — restarted"
```

### YouTube pipeline FAILED
```bash
# See what failed
tail -100 ~/apps/social-factory/channels/<channel>/state/pipeline.log

# Re-run as a test
~/apps/social-factory/scripts/run.sh <channel> short --no-upload

# If token error: token needs re-auth (OAuth expired)
ls ~/apps/social-factory/tokens/
```

### Disk over 85%
```bash
df -h ~                                            # current usage
du -sh ~/downloads/* 2>/dev/null | sort -h         # what's in downloads?
du -sh ~/media/exports/* 2>/dev/null | sort -h     # old exports?
du -sh ~/projects/*/node_modules 2>/dev/null | sort -h  # node_modules?

# Clean safely
npm cache clean --force                            # npm cache
find ~/projects -name ".next" -type d -maxdepth 3 -exec du -sh {} \;  # Next.js build dirs
```

### OAuth token expired (YouTube)
```bash
# Re-auth: run the OAuth script for that channel
# The token file will be at ~/apps/social-factory/tokens/<channel>-youtube.json
# Check the channel's README or auth script for re-auth instructions
```

### Root clutter (file dropped in wrong place)
```bash
# The relocator runs every 15min and auto-moves files
# To move manually:
mv ~/some-file.py ~/scripts/
mv ~/some-image.png ~/media/images/
map
```

---

## GitHub Backup

This computer auto-syncs to a private GitHub repo every 6 hours:
```bash
bash ~/scripts/vps-sync.sh           # sync now
tail -20 ~/documents/sync.log        # check last sync result
```

The backup includes: apps (excl. venvs/node_modules), projects, scripts, documents, crontab, pip freeze lists.
It does NOT include: secret keys, OAuth tokens, `.next/`, node_modules, Python venvs.

---

## Auto-Relocator

Files dropped in the wrong place are automatically moved every 15 minutes:

| File type | Auto-moved to |
|-----------|--------------|
| `.jpg`, `.png`, `.gif`, `.webp`, `.svg` | `~/media/images/` |
| `.mp4`, `.mov`, `.avi`, `.mkv`, `.webm` | `~/media/videos/` |
| `.mp3`, `.wav`, `.flac`, `.ogg`, `.aac` | `~/media/audio/` |
| `.pdf`, `.doc`, `.docx`, `.epub` | `~/documents/` |
| `.zip`, `.tar.gz`, `.rar`, `.7z` | `~/downloads/` |
| `.sh` | `~/scripts/` |
| `.log` | `~/documents/logs/` |
| `.md`, `.txt` (non-system) | `~/documents/` |
| Unknown directories | `~/downloads/` or `~/apps/` or `~/projects/` |

All moves are logged to `~/documents/changelog.md`.

---

## Auto-Updates

Infrastructure updates daily at 06:00 UTC from the GitHub repo:
```bash
update    # manual update now
```

Updates only replace: `scripts/`, `system/`, `bin/`, `AGENT.md`, `CLAUDE.md`.
Your apps, projects, documents, and keys are **never touched**.

---

## Migration

```bash
# Create export
export                         # configs only (safe to share)
export --include-secrets       # full export with tokens and keys
# Output: ~/vps-export-YYYYMMDD.tar.gz

# Restore on new server
scp ~/vps-export-*.tar.gz ubuntu@<new-server>:~/
ssh ubuntu@<new-server>
tar -xzf vps-export-*.tar.gz && cd vps-export-* && bash restore.sh
```

---

## System Internals (`~/system/`)

| File | Purpose |
|------|---------|
| `boot.sh` | Session startup (called by `boot`) |
| `health.sh` | Full health check (called by `check`) |
| `relocator.sh` | Auto-moves misplaced files every 15 min |
| `.version` | Installed agent-computer version |
| `.update-source` | GitHub repo URL for auto-updates |
| `.installed` | Installation details and timestamp |

---

## Update Protocol

After **any** change to this computer:
```bash
map
```
This regenerates `README.md` from live state so every agent always starts with accurate info.
