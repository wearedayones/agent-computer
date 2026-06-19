# Agent Computer
> Universal operating guide. Any agent — read this entire file before doing anything.
> Live system state: `README.md` (auto-generated, always current).

---

## House Rules — Non-Negotiable

### Zone map (where everything goes)
| What | Zone | Example path |
|------|------|-------------|
| New autonomous app / bot | `~/apps/` | `~/apps/my-bot/` |
| New development project | `~/projects/` | `~/projects/my-app/` |
| New script or utility | `~/scripts/` | `~/scripts/my-tool.sh` |
| Notes, guides, references | `~/documents/` | `~/documents/my-notes.md` |
| Images, photos, thumbnails | `~/media/images/` | `~/media/images/hero.png` |
| Videos, clips, exports | `~/media/videos/` | `~/media/videos/clip.mp4` |
| Audio, music, recordings | `~/media/audio/` | `~/media/audio/track.mp3` |
| Rendered / exported output | `~/media/exports/` | `~/media/exports/final.mp4` |
| Temp / downloaded content | `~/downloads/` | `~/downloads/tmp/file.zip` |
| API keys and credentials | `~/keys/` | `~/keys/api_key.txt` |
| **Root `~/`** | **NEVER** | Nothing goes here |

---

### Creating New Folders — Allowed ✓

If a folder you need doesn't exist yet, **create it inside the correct zone**. Do not create it at root.

```bash
mkdir ~/media/screenshots       # new media type — OK
mkdir ~/documents/reports       # new doc category — OK
mkdir ~/downloads/task-files    # temp space — OK
mkdir ~/apps/my-new-bot         # new app — OK
# NEVER: mkdir ~/screenshots    # at root — WRONG
```

**Naming rules:** lowercase, hyphens only (no spaces, no underscores, no capitals).
After creating, run `map` to update README.

---

### What you can NEVER create
- Any folder or file directly at `~/` root (other than the 3 `.md` files that already exist)
- Folders inside `~/keys/`

---

### Never touch
- `~/keys/` — read-only, never write or delete

### Before deleting anything
Move to `~/archive/<name>/` first. Never directly `rm -rf` an app or project.

### After every change
```bash
map    # keeps README.md accurate for the next agent
```

---

## Quick Orientation

```bash
boot                    # session startup: pulse, inbox, quick commands
check                   # full color health report
map                     # refresh README after any change
update                  # pull latest agent-computer version from GitHub
cat ~/AGENT.md          # this file
cat ~/README.md         # live system state + JSON manifest
```

---

## Shell Commands (`~/bin/` — all in PATH)

| Command | What it does |
|---------|-------------|
| `boot` | Session startup: disk pulse, inbox check, last changes, quick commands |
| `check` | Full color health report (disk, apps, channels, venvs, keys, inbox) |
| `map` | Regenerate README.md from live state |
| `update` | Pull latest infrastructure from GitHub (safe, never touches your data) |
| `note "message"` | Leave a note in `~/inbox/` for the next agent |
| `export [--include-secrets]` | Package computer for server migration |

---

## Inter-Agent Messaging (`~/inbox/`)

Agents leave messages for each other here. Check it on arrival with `boot`.

```bash
note "finished audit, all tokens valid"    # leave a message
ls ~/inbox/                                # see all messages
cat ~/inbox/*.md                           # read all messages
```

---

## Auto-Relocator

If you drop a file in the wrong place, the relocator (runs every 5 min) will move it automatically:

| File type | Auto-moved to |
|-----------|--------------|
| `.jpg`, `.png`, `.gif`, `.webp` | `~/media/images/` |
| `.mp4`, `.mov`, `.avi` | `~/media/videos/` |
| `.mp3`, `.wav`, `.flac` | `~/media/audio/` |
| `.pdf`, `.md`, `.txt` | `~/documents/` |
| `.zip`, `.tar.gz` | `~/downloads/` |
| `.sh` | `~/scripts/` |
| `.log` | `~/documents/logs/` |
| Unknown directories | `~/downloads/` or `~/apps/` or `~/projects/` |

All moves are logged to `~/documents/changelog.md`.

---

## Auto-Updates

The computer auto-updates daily at 06:00 UTC from GitHub.

```bash
update         # manual update now
cat ~/documents/changelog.md    # see update history
```

Updates only touch infrastructure files (scripts, system, bin, AGENT.md, CLAUDE.md).
Your apps, projects, documents, and keys are never modified.

---

## Computer Layout

| Zone | Path | Purpose |
|------|------|---------|
| **Apps** | `~/apps/` | Autonomous applications that run 24/7 |
| **Projects** | `~/projects/` | Things being actively built / developed |
| **Scripts** | `~/scripts/` | Tools, utilities, one-off automations |
| **Documents** | `~/documents/` | Guides, notes, references |
| **Media** | `~/media/` | images/ · videos/ · audio/ · exports/ |
| **Downloads** | `~/downloads/` | Temporary fetched content (safe to clear) |
| **Keys** | `~/keys/` | API credentials (never commit, never log) |
| **Archive** | `~/archive/` | Old versions (safe to ignore) |
| **Bin** | `~/bin/` | Short command aliases (in PATH) |
| **System** | `~/system/` | Health, boot, relocator, version tracking |
| **Inbox** | `~/inbox/` | Inter-agent messages |

**Root only contains:** `AGENT.md`, `CLAUDE.md`, `README.md`, and the zones above.

---

## System Internals (`~/system/`)

| File | Purpose |
|------|---------|
| `health.sh` | Full color health check (called by `check`) |
| `boot.sh` | Session startup script (called by `boot`) |
| `relocator.sh` | Auto-moves misplaced files every 5 min |
| `.version` | Installed version number |
| `.update-source` | GitHub repo URL for auto-updates |

---

## Credentials (`~/keys/`)

Store all API keys here as plain text or JSON files. Name them descriptively:
- `service_api_key.txt` — API key for a service
- `service_token.json` — OAuth token

**Check key presence:** `check` shows each key file status.

---

## Update Protocol

After ANY change to this computer:
```bash
map
```
This regenerates `README.md` with live state so every agent always has accurate info.

---

## Migration

```bash
export                         # configs only
export --include-secrets       # full export with keys
# Output: ~/vps-export-YYYYMMDD.tar.gz
```
