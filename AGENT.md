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

**`axis`** is the master CLI — use it for everything. All commands below are also callable directly.

| Command | Action |
|---------|--------|
| `axis` | Live status dashboard — system, work, agents at a glance |
| `axis help` | Full categorized command reference |
| `axis version` | Version info |
| `axis <command> [args]` | Run any command below via axis |
| `boot` | Session startup: disk, sessions, inbox, last changes |
| `check` | Full color health report |
| `map` | Regenerate README.md from live state |
| `update` | Pull latest agent-computer infrastructure from GitHub |
| `note "msg"` | Leave a message for the next agent in `~/inbox/` |
| `export` | Package computer for migration (configs only) |
| `export --include-secrets` | Full export including API keys and tokens |
| `memory set <key> <value>` | Persist a fact across sessions |
| `memory get <key>` | Recall a stored fact |
| `memory list` | List all stored memories |
| `memory del <key>` | Delete a stored memory |
| `task add "desc"` | Add a task to the work queue |
| `task list` | Show all tasks (open + done) |
| `task done <id>` | Mark a task complete |
| `task del <id>` | Remove a task |
| `task clear` | Remove all completed tasks |
| `budget log <amount> "desc"` | Record a cost or spend entry |
| `budget show [YYYY-MM]` | Show spend for current (or given) month |
| `budget reset` | Clear spend entries for current month |
| `log today` | Show today's activity from changelog |
| `log week` | Show last 7 days of activity |
| `log errors` | Show error/failure entries |
| `snapshot` | Archive memory/tasks/budget/cron to ~/archive/ |
| `snapshot list` | List saved snapshots |
| `snapshot restore <name>` | Restore state from a snapshot |
| `secret list` | List key names in ~/keys/ (never values) |
| `secret get <name>` | Read a key from ~/keys/ |
| `secret set <name>` | Write a key (prompts securely) |
| `plan show` | Display active session plan |
| `plan set "title"` | Start a new plan |
| `plan add "step"` | Add a step to current plan |
| `plan done "step"` | Mark a step complete |
| `plan clear` | Remove active plan |
| `agent list` | Show all registered agents with live status |
| `agent add <name> "desc"` | Register an agent |
| `agent ping <name>` | Check if an agent is alive |
| `agent del <name>` | Remove from registry |
| `mcp list` | Show configured MCP servers |
| `mcp add <name> <cmd> [args]` | Register an MCP server |
| `mcp del <name>` | Remove an MCP server |
| `mcp status` | Check which MCP commands are installed |
| `cron list` | Show all cron jobs with numbers |
| `cron add "<schedule>" "<cmd>"` | Add a cron job |
| `cron del <n>` | Remove cron job number n |
| `msg <agent> "text"` | Send a message to a specific agent's inbox |
| `msg list` | Show registered agents and their inboxes |
| `cfg list [app]` | List apps with .env, or keys inside one app |
| `cfg get <app> <KEY>` | Read a config value |
| `cfg set <app> <KEY> <value>` | Set or update a config value |
| `cfg show <app>` | Print full .env with values |
| `cfg del <app> <KEY>` | Remove a key |
| `watch <app>` | Tail all logs for an app in ~/apps/ |
| `watch <app> list` | Show available log files for an app |
| `note list` | Show inbox summaries |
| `note read [file]` | Read notes in full |
| `note clear` | Remove all inbox messages |
| `run list` | Show runnable apps (auto-detected by start script) |
| `run <app>` | Start an app via its run/start script |
| `axis doctor` | Full diagnostics — infra, cron, agents, disk, deps |
| `axis ps` | Running tmux sessions, cron queue, background processes |
| `axis size` | Disk usage by zone with bar chart |
| `axis clean [--force]` | Dry-run (or apply) cleanup of old files, caches, logs |
| `axis start/stop/restart <app>` | App lifecycle via tmux sessions |
| `axis diff` | Changes since last snapshot (tasks, memory, cron) |
| `axis alert` | Scan all app alert logs for errors and failures |
| `axis ports` | Show listening ports (`ss -tlnp`) |
| `axis sync` | Trigger GitHub backup now |
| `axis history [n]` | Last n meaningful changelog events (noise filtered) |

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
# rm -rf ~/apps/old-bot                # NEVER — always archive first
```

### 3. Update the map after any change
```bash
map
```
Run after: creating files, adding apps, moving things, editing configs, changing cron.

### 4. Never touch protected paths
Check `~/CLAUDE.md` for the protected paths specific to this computer.

---

## Creating Files — Do It Right

**Always use the shortest valid path. Never create a folder just to hold one file.**

```
✓  ~/documents/links.md
✗  ~/documents/links/links.md     ← unnecessary nesting

✓  ~/documents/notes.md
✗  ~/documents/notes/notes.md     ← same mistake

✓  ~/scripts/cleanup.sh
✗  ~/scripts/cleanup/cleanup.sh   ← wrong
```

**Only create a subfolder when you have multiple related files:**
```
✓  ~/documents/api-docs/auth.md
✓  ~/documents/api-docs/endpoints.md
   (two files that belong together — subfolder makes sense)

✗  ~/documents/api-docs/api-docs.md
   (just one file — use ~/documents/api-docs.md instead)
```

**Check before creating.** Always check if a file already exists before making a new one:
```bash
ls ~/documents/          # see what's already there
cat ~/documents/links.md # read it before overwriting
```

---

## Inter-Agent Messaging

`note` is for leaving messages that the **next agent reads on arrival**. It goes to `~/inbox/`, not `~/documents/`.

```bash
note "finished token refresh — all services healthy"
note "disk was at 89% — cleared downloads/, now 74%"
note "DO NOT restart the bot — owner is monitoring a live trade"

ls ~/inbox/         # list all messages
cat ~/inbox/*.md    # read all messages
```

`boot` shows inbox messages automatically on arrival.

### When you MUST write a note (non-negotiable)

Write a note at the end of any session where at least one of these is true:

| Trigger | Example note |
|---------|-------------|
| Finished meaningful work | "Wired pipeline gate into orchestrator — all 23 tests pass" |
| Left something half-done | "Producer rewrite 2/3 done — crvgrowth still uses old agy call" |
| Found a problem you didn't fix | "Disk at 91% — downloads/ is safe to clear but I ran out of time" |
| Changed a cron job or background process | "Added 6am gate-check cron — see crontab line 14" |
| Something broke during your session | "LLM bridge blacklisted claude-3-haiku — check core/llm_bridge_blacklist.json" |
| Task spans multiple sessions | "Phase 1 of 3 done — next: wire upload gate check" |

If none of these apply, no note needed.

**Do not** use `~/documents/` to leave messages for the next agent. Use `note`.

---

## Computer Layout

| Zone | Path | Purpose |
|------|------|---------|
| **Apps** | `~/apps/` | Autonomous apps that run 24/7 |
| **Projects** | `~/projects/` | Active development work |
| **Scripts** | `~/scripts/` | Tools and utilities |
| **Documents** | `~/documents/` | Guides, notes, references — flat files |
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

## Common Mistakes — Don't Do These

| Wrong | Right |
|-------|-------|
| `~/documents/links/links.md` | `~/documents/links.md` |
| `~/temp/`, `~/tmp/`, `~/data/` at root | `~/downloads/` |
| `rm -rf ~/apps/old-bot` | `mv ~/apps/old-bot ~/archive/old-bot` |
| Putting scripts in `~/apps/` | `~/scripts/your-script.sh` |
| Putting projects in `~/apps/` | `~/projects/your-project/` |
| Creating files without running `map` | Always run `map` after |
| Leaving messages in `~/documents/` | Use `note "msg"` → `~/inbox/` |
| Writing to `~/keys/` | Read-only — never write |
| Not checking if a file exists before creating | Always `ls` first |

---

## App Registry

Add your apps here after installing them. Example:

```
### my-bot
- Location: ~/apps/my-bot/
- Start:    tmux new-session -d -s my-bot 'bash ~/apps/my-bot/run.sh'
- Check:    tmux has-session -t my-bot && echo running || echo STOPPED
- Logs:     tail -f ~/apps/my-bot/bot.log
- Stop:     tmux kill-session -t my-bot
```

App-specific commands and protected paths go in `~/CLAUDE.md`.

---

## Python Venvs

Shared venvs live in `~/apps/envs/`:
```bash
ls ~/apps/envs/                              # list all venvs
source ~/apps/envs/my-venv/bin/activate     # activate one
deactivate                                   # deactivate

# Install packages into a venv — never into system Python
~/apps/envs/my-venv/bin/pip install <package>
```

---

## Fixing Common Problems

### App stopped unexpectedly
```bash
tmux ls                                    # see all running sessions
tail -20 ~/documents/changelog.md          # see recent events
# Check the app's own logs in ~/apps/<name>/
```

### Disk over 85%
```bash
df -h ~
du -sh ~/downloads/* 2>/dev/null | sort -h         # large downloads?
du -sh ~/media/exports/* 2>/dev/null | sort -h     # old exports?
du -sh ~/projects/*/node_modules 2>/dev/null | sort -h  # node_modules?
npm cache clean --force
```

### Root clutter
```bash
# The relocator auto-moves files every 15 min — or move manually:
mv ~/some-file.txt ~/documents/
mv ~/some-image.png ~/media/images/
map
```

---

## GitHub Backup

Auto-sync to a private GitHub repo every 6 hours:
```bash
bash ~/scripts/vps-sync.sh           # sync now
tail -20 ~/documents/sync.log        # check last sync
```

See `~/scripts/vps-sync.sh` for one-time setup instructions.

Backup includes: apps (excl. venvs/node_modules), projects, scripts, documents, crontab, pip freeze lists.
Does NOT include: secret keys, OAuth tokens, build dirs, Python venvs.

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
| No extension (text content) | `~/downloads/` |
| Unknown directories | `~/downloads/`, `~/apps/`, or `~/projects/` |

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
export                         # configs only
export --include-secrets       # full export with keys and tokens

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
| `memory.json` | Persistent cross-session knowledge store |
| `tasks.json` | Work queue surviving context resets |
| `budget.json` | Cost and spend ledger |

---

## Update Protocol

After **any** change:
```bash
map
```
This regenerates `README.md` so every agent always starts with accurate info.
