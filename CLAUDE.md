# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Your Workspace

**Your workspace is `$HOME`. That is the computer.**

The authoritative files are the ones already installed — `~/bin/`, `~/system/`, `~/scripts/`. Everything you do lives under `$HOME` in the correct zone (see Zone Map in `~/AGENT.md`).

---

## Session Startup — MANDATORY, NO EXCEPTIONS

**Step 1: Run boot. Do it before you read anything else, before you touch any file.**

```bash
boot
```

`boot` shows: disk health, active sessions, cron count, and **inbox messages from the previous agent**.
If you skip it, you are flying blind. The owner will not tell you what the last agent did — that's what the inbox is for.

**If `boot` shows inbox messages — read and act on them before doing anything else.**
**If `boot` shows disk < 2GB — free space before doing anything else.**

---

## Session End — Write to Inbox if ANY of these are true

```bash
note "your message"    # → ~/inbox/ — next agent reads this on boot
```

**You MUST write a note if:**
- You did meaningful work (finished a feature, fixed a bug, made a config change)
- You left something half-done or paused mid-task
- You discovered a problem you didn't fix
- You changed a cron job, service, or background process
- You modified a protected path or a shared config
- The owner gave you a task that spans multiple sessions
- Anything broke and you want the next agent to know

**You do NOT need a note if:**
- You only answered a question (no files changed)
- `boot` inbox was empty and you changed nothing

One note per session is enough. Be specific: what you did, what's left, what to watch for.

---

## File Rules (read carefully — agents often get these wrong)

### Flat files — never nest unnecessarily
```
✓  ~/documents/links.md
✗  ~/documents/links/links.md

✓  ~/documents/notes.md
✗  ~/documents/notes/notes.md
```
Only create a subfolder inside a zone if you have **multiple related files** that belong together.

### Always check before creating
```bash
ls ~/documents/          # does the file already exist?
cat ~/documents/foo.md   # read it before writing
```

### Zone rules
| Type | Zone |
|------|------|
| New app / bot | `~/apps/<name>/` |
| New project | `~/projects/<name>/` |
| New script | `~/scripts/` |
| Notes / docs | `~/documents/` |
| Images | `~/media/images/` |
| Videos | `~/media/videos/` |
| Audio | `~/media/audio/` |
| Temp files | `~/downloads/` |
| Python venvs | `~/apps/envs/<name>/` |
| **Root** | **NOTHING** — only AGENT.md, CLAUDE.md, README.md |

---

## Inter-Agent Messages → `note`, not files

```bash
note "your message"    # → ~/inbox/ (next agent sees this on boot)
```

Never create files in `~/documents/` to leave messages. Use `note`.

---

## After Every Change

```bash
map    # regenerate README.md — always do this
```

---

## Never Delete Without Archiving

```bash
mv ~/apps/old-bot ~/archive/old-bot   # ✓ archive first
rm -rf ~/apps/old-bot                 # ✗ never
```

---

## Never Touch Protected Paths

Add this computer's protected paths below (customize per installation):

```
# Example:
# ~/keys/          — API credentials, read-only
# ~/some-app/db/   — live database, never touch
```

---

## Permission Mode
`bypassPermissions` — no confirmation prompts for normal operations.
**Real-money or destructive actions — always confirm with the owner first.**

---

## Quick Reference

| Command | Action |
|---------|--------|
| `boot` | Session startup |
| `check` | Full color health report |
| `map` | Regenerate README.md |
| `update` | Pull latest from GitHub |
| `note "msg"` | Leave message for next agent |
| `export` | Package for migration |
| `memory set/get/list/del` | Cross-session persistent knowledge |
| `task add/list/done/del` | Work queue surviving context resets |
| `budget log/show` | Cost and spend tracking |
| `log today/week/errors` | Activity viewer |
| `snapshot` | Archive current state |
| `secret list/get` | Safe access to ~/keys/ |
| `plan show/set/add/done` | Session work plan |
| `agent list/add/ping` | Agent registry with live status |
| `mcp list/add/status` | MCP server management |
| `cron list/add/del` | Manage cron jobs by number |
| `msg <agent> "text"` | Message a specific agent's inbox |
| `cfg set/get/show <app>` | Manage .env config files for apps |
