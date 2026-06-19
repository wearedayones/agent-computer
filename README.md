# Agent Computer

A structured operating environment for AI agents on Ubuntu VPS — like Windows for humans, but designed for AI agents.

Any agent (Claude, Gemini, GPT, custom) that arrives at this computer instantly knows:
- Where everything is
- What's running and what's broken
- How to add things without making a mess
- How to leave messages for the next agent

---

## What it gives you

| Feature | How it works |
|---------|-------------|
| **Clean zones** | `apps/`, `projects/`, `media/`, `documents/`, `scripts/`, `downloads/`, `keys/` |
| **Auto-relocator** | Drop a file anywhere wrong — cron moves it to the right place every 5 min |
| **Live README** | `map` regenerates `README.md` from live system state (cron runs hourly) |
| **Health check** | `check` — color-coded report: disk, apps, API keys, venvs, root cleanliness |
| **Session boot** | `boot` — any agent runs this on arrival for instant orientation |
| **Inter-agent inbox** | `note "msg"` — leave messages for the next agent in `~/inbox/` |
| **Auto-updates** | Pulls latest infrastructure from this repo daily at 06:00 UTC |
| **Auto-changelog** | Significant events (pipeline failures, status changes) logged automatically |
| **One-command migration** | `export` packages everything for moving to a new server |

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
├── projects/         ← Active development work
├── scripts/          ← Tools and utilities
├── documents/        ← Notes, guides, reports
├── media/            ← images/ · videos/ · audio/ · exports/
├── downloads/        ← Temporary content (safe to clear)
├── keys/             ← API credentials (never commit)
├── archive/          ← Old versions
├── inbox/            ← Inter-agent messages
├── bin/              ← Shell shortcuts (all in PATH)
└── system/           ← Health, boot, relocator scripts
```

---

## Commands

After install, these are available in any shell session:

```bash
boot              # orientation on arrival
check             # full health report
map               # refresh README
update            # pull latest from GitHub
note "message"    # leave a note for the next agent
export            # package for server migration
```

---

## How agents use it

Any agent arriving at this computer should start with:

```bash
boot
```

This shows:
- Disk usage
- Which apps are running / stopped
- Inbox messages from previous agents
- Last 3 changelog entries
- Quick command reference

Full operating guide is always at `~/AGENT.md`.

---

## Auto-updates

The computer checks this repo daily and applies updates automatically.

Updates only replace infrastructure files: `scripts/`, `system/`, `bin/`, `AGENT.md`, `CLAUDE.md`.

Your apps, projects, documents, and keys are **never touched**.

Run manually:
```bash
update
```

---

## Auto-relocator

Files dropped in the wrong place are automatically moved:

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

## Customizing

After install, edit these files to add your apps:

- `~/AGENT.md` — add your apps to the "App Registry" section
- `~/CLAUDE.md` — add Claude-specific rules for your setup
- `~/scripts/vps-map.sh` — extend the live README with your app's health checks

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
