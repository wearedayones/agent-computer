# Agent Computer
> Universal operating guide. Any agent — read this entire file before doing anything.
> Live system state: `README.md` (auto-generated, always current).

---

## 60-Second Orientation

```bash
boot    # run this first — disk, sessions, inbox, last changes, quick commands
```

After `boot`: check README.md alerts → fix anything broken → do your work → run `map`.

---

## Shell Commands (`~/bin/` — all in PATH)

| Command | Action |
|---------|--------|
| `boot` | Session startup: disk, sessions, inbox, last changes |
| `check` | Full color health report |
| `map` | Regenerate README.md from live state |
| `update` | Pull latest agent-computer infrastructure from GitHub |
| `note "msg"` | Leave a message for the next agent in `~/inbox/` |
| `export` | Package computer for migration (configs only) |
| `export --include-secrets` | Full export including API keys and tokens |

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
Naming: lowercase and hyphens only. No spaces, no underscores, no capitals.

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

### 4. Never touch protected paths
Check `~/CLAUDE.md` for the list of protected paths specific to this computer.

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

Add your apps here after installing them. Example format:

```
### my-bot
- Location: ~/apps/my-bot/
- Start: tmux new-session -d -s my-bot 'bash ~/apps/my-bot/run.sh'
- Check: tmux has-session -t my-bot && echo running || echo STOPPED
- Logs: tail -f ~/apps/my-bot/bot.log
```

`~/CLAUDE.md` is where you put app-specific rules and protected paths.

---

## Python Venvs

Shared venvs live in `~/apps/envs/`:
```bash
ls ~/apps/envs/                              # list all venvs
source ~/apps/envs/my-venv/bin/activate     # activate one
deactivate                                   # deactivate

# Install packages into a venv (never into system Python)
~/apps/envs/my-venv/bin/pip install <package>
```

---

## Inter-Agent Messaging

Leave messages for the next agent in `~/inbox/`:
```bash
note "finished token refresh — all services healthy"
note "bot was STOPPED — restarted at 14:30 UTC, investigate why"

ls ~/inbox/         # list all messages
cat ~/inbox/*.md    # read all messages
```

`boot` shows inbox messages automatically on arrival.

---

## Fixing Common Problems

### App stopped unexpectedly
```bash
tmux ls                      # see all running sessions
cat ~/documents/changelog.md | tail -20   # see recent events
# Check your app's logs in ~/apps/<name>/
```

### Disk over 85%
```bash
df -h ~
du -sh ~/downloads/* 2>/dev/null | sort -h     # downloads?
du -sh ~/media/exports/* 2>/dev/null | sort -h # old exports?
du -sh ~/projects/*/node_modules 2>/dev/null | sort -h  # node_modules?
npm cache clean --force                        # npm cache
```

### Root clutter
```bash
# The relocator runs every 15 min — or move manually:
mv ~/some-file.py ~/scripts/
mv ~/some-image.png ~/media/images/
map
```

---

## GitHub Backup

Set up auto-sync to a private GitHub repo every 6 hours:
```bash
bash ~/scripts/vps-sync.sh           # sync now
tail -20 ~/documents/sync.log        # check last sync
```

See `~/scripts/vps-sync.sh` for one-time setup instructions.

The backup includes: apps (excl. venvs/node_modules), projects, scripts, documents, crontab, pip freeze lists.
It does NOT include: secret keys, OAuth tokens, build dirs, venvs.

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

All moves logged to `~/documents/changelog.md`.

---

## Auto-Updates

Infrastructure updates daily at 06:00 UTC:
```bash
update    # manual update now
```

Updates only replace: `scripts/`, `system/`, `bin/`, `AGENT.md`, `CLAUDE.md`.
Your apps, projects, documents, and keys are **never touched**.

---

## Migration

```bash
export                         # configs only (safe to share)
export --include-secrets       # full export with keys and tokens
# Output: ~/vps-export-YYYYMMDD.tar.gz

# Restore on new server:
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
This regenerates `README.md` so every agent starts with accurate info.
