# Agent Computer

A structured operating environment for AI agents on Ubuntu VPS — like an OS for AI, not humans.

Any agent (Claude, Gemini, GPT, or custom) that arrives at this computer instantly knows:
- Where everything is
- What's running and what's broken
- How to add things without making a mess
- How to leave messages for the next agent

---

## What it gives you

| Feature | How it works |
|---------|-------------|
| **Clean zones** | `apps/`, `projects/`, `media/`, `documents/`, `scripts/`, `downloads/`, `keys/`, `apps/envs/` |
| **Auto-relocator** | Drop a file in the wrong place — cron moves it correctly every 15 min |
| **Live README** | `map` regenerates `README.md` from live system state (cron runs hourly) |
| **Health check** | `check` — color-coded report: disk, apps, API keys, venvs, GitHub sync, root cleanliness |
| **Session boot** | `boot` — any agent runs this on arrival for instant orientation |
| **Inter-agent inbox** | `note "msg"` — leave messages for the next agent in `~/inbox/` |
| **Auto-updates** | Pulls latest infrastructure from this repo daily at 06:00 UTC |
| **Auto-changelog** | Significant events (pipeline failures, status changes) logged automatically |
| **One-command export** | `export` packages everything for moving to a new server |
| **GitHub backup** | `vps-sync.sh` — auto-syncs the whole VPS to a private GitHub repo every 6 hours |

---

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wearedayones/agent-computer/main/setup.sh)
```

Or clone first:
```bash
git clone https://github.com/wearedayones/agent-computer.git
bash agent-computer/setup.sh
```

---

## Directory structure

```
~/
├── AGENT.md          ← Universal agent guide (read this first)
├── CLAUDE.md         ← Claude Code specific settings
├── README.md         ← Live system map (auto-generated)
│
├── apps/             ← Autonomous applications (bots, automations)
│   └── envs/         ← Shared Python virtual environments
├── projects/         ← Active development work
├── scripts/          ← Tools and utilities
├── documents/        ← Notes, guides, reports, changelog
├── media/            ← images/ · videos/ · audio/ · exports/
├── downloads/        ← Temporary content (safe to clear)
├── keys/             ← API credentials (never commit)
├── archive/          ← Old versions (safe to ignore)
├── inbox/            ← Inter-agent messages
├── bin/              ← Shell shortcuts (all in PATH)
└── system/           ← Health, boot, relocator, version tracking
```

---

## Commands

After install, these are available in any shell session:

```bash
boot                        # orient on arrival
check                       # full color health report
map                         # refresh README from live state
update                      # pull latest from GitHub
note "message"              # leave a note for the next agent
export                      # package for server migration (configs only)
export --include-secrets    # full export with keys and tokens
```

---

## How agents use it

Any agent arriving at this computer starts with:

```bash
boot
```

This shows:
- Disk usage (color-coded)
- Which apps are running or stopped
- Inbox messages from previous agents
- Last 3 changelog entries
- Quick command reference

Full operating guide is always at `~/AGENT.md`.

---

## Auto-updates

The computer checks this repo daily and applies updates automatically at 06:00 UTC.

Updates only replace infrastructure files: `scripts/`, `system/`, `bin/`, `AGENT.md`, `CLAUDE.md`.

Your apps, projects, documents, and keys are **never touched**.

```bash
update    # run manually anytime
```

---

## GitHub backup

Set up automatic VPS backup to a private GitHub repo:

1. Create a private repo (e.g. `yourname/vps-backup`)
2. Save a GitHub personal access token to `~/keys/github_token.txt`
3. Initialize: `cd ~/projects/vps-backup && git init && git remote add origin https://github.com/yourname/vps-backup.git`
4. Add to crontab: `0 */6 * * * bash ~/scripts/vps-sync.sh >> ~/documents/sync.log 2>&1`

The sync excludes secrets, node_modules, Python venvs, and `.next/` build dirs. Pip freeze lists are included so venvs can be rebuilt.

---

## Auto-relocator

Files dropped in the wrong place are automatically moved every 15 minutes:

| You drop | It goes to |
|----------|-----------|
| `photo.jpg` at root | `~/media/images/` |
| `clip.mp4` at root | `~/media/videos/` |
| `track.mp3` at root | `~/media/audio/` |
| `notes.md` at root | `~/documents/` |
| `archive.zip` at root | `~/downloads/` |
| `tool.sh` at root | `~/scripts/` |
| Unknown directory | `~/downloads/` or `~/apps/` or `~/projects/` |

All moves are logged to `~/documents/changelog.md`.

---

## Migration

```bash
export                          # configs only (safe to share)
export --include-secrets        # full export with keys and tokens

# On new server:
scp ~/vps-export-*.tar.gz ubuntu@<new-server>:~/
ssh ubuntu@<new-server>
tar -xzf vps-export-*.tar.gz && cd vps-export-* && bash restore.sh
```

The `restore.sh` inside the export automatically:
- Installs system deps (Node.js, Python, ffmpeg, bun)
- Recreates Python venvs from pip freeze lists
- Runs `npm install` in all projects
- Restores the crontab
- Starts the bybit bot
- Generates `README.md`

---

## Customizing

After install, adapt these files to your setup:

- `~/AGENT.md` — add your apps to the "App Registry" section
- `~/CLAUDE.md` — add Claude-specific rules for your setup
- `~/scripts/vps-map.sh` — extend the live README with your app's health checks
- `~/system/health.sh` — add your app's health checks to `check`

---

## Requirements

- Ubuntu 20.04+ (or Debian 11+)
- bash 5+
- python3 (for vps-map.sh JSON manifest)
- curl
- cron

---

## License

MIT
