# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Session Startup (do this every time you arrive)

```bash
boot        # quick orientation: disk, apps, inbox, last changes, command reference
```

Or manually:
```bash
cat ~/AGENT.md          # full operating guide
cat ~/README.md         # live state + alerts
check                   # full color health report
```

If `boot` or README shows any alerts (FAILED runs, STOPPED bots, MISSING tokens) — **fix those first**.

---

## House Rules (mandatory — never break these)

### Where things go
| Type of thing | Put it in |
|--------------|-----------|
| New autonomous app / bot | `~/apps/<name>/` |
| New dev project | `~/projects/<name>/` |
| New script / tool | `~/scripts/` |
| Notes, guides, references | `~/documents/` |
| Images, photos, thumbnails | `~/media/images/` |
| Videos, clips | `~/media/videos/` |
| Audio, music | `~/media/audio/` |
| Exported/rendered output | `~/media/exports/` |
| Temp / downloaded content | `~/downloads/` |
| Python venvs | `~/apps/envs/<name>-venv/` |
| **Root (`~/`)** | **NOTHING** — only the 3 `.md` files that already exist |

**Creating new sub-folders is allowed** — but only inside an existing zone, never at root.
Example: need screenshots? → `mkdir ~/media/screenshots` ✓ — not `mkdir ~/screenshots` ✗

### Never delete without archiving
Move to `~/archive/<name>/` first. Never `rm -rf` an app or project directly.

### Always update the map after changes
```bash
map
```

### Never touch these
- `~/keys/` — read-only, never write or delete
- `~/.hermes/` — managed by Hermes, hands off
- `~/.bybit/` — trading bot state, never touch
- `~/apps/social-factory/tokens/` — OAuth tokens, read-only

---

## Permission Mode
`bypassPermissions` — no confirmation prompts needed for normal operations.
**Mainnet financial actions (real money, real Bybit trades) — always confirm with owner first.**

---

## Quick Reference

| Command | Action |
|---------|--------|
| `boot` | Session startup: disk + inbox + quick commands |
| `check` | Full color health report |
| `map` | Regenerate README.md |
| `update` | Pull latest from GitHub |
| `note "msg"` | Leave a message for next agent |
| `export` | Package for migration |

---

## Common Patterns

```bash
# Test YouTube pipeline (never upload without testing first)
~/apps/social-factory/scripts/run.sh <channel> short --no-upload

# Check all channel statuses
for ch in $(ls ~/apps/social-factory/channels/); do
  echo "=== $ch ===" && tail -2 ~/apps/social-factory/channels/$ch/state/pipeline.log
done

# Check trading bot
tmux ls && tmux attach -t persistent-agent

# Leave a note for the next agent
note "finished X — next agent should do Y"

# Check GitHub backup status
tail -10 ~/documents/sync.log
```
