# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Session Startup (do this every time you arrive)

```bash
boot        # quick orientation: disk, sessions, inbox, last changes
```

Or manually:
```bash
cat ~/AGENT.md          # full operating guide
cat ~/README.md         # live state + alerts
check                   # full color health report
```

If `boot` or README shows any alerts — **fix those first**.

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

### Never delete without archiving
```bash
mv ~/apps/old-bot ~/archive/old-bot   # always archive first
```

### Always update the map after changes
```bash
map
```

---

## Protected Paths (customize for your setup)

Add paths that should never be modified here. Example:
```
- ~/keys/          — API credentials, read-only
- ~/some-app/data/ — live database, never touch
```

---

## Permission Mode
`bypassPermissions` — no confirmation prompts needed for normal operations.
**Real-money or destructive actions — always confirm with the owner first.**

---

## Quick Reference

| Command | Action |
|---------|--------|
| `boot` | Session startup |
| `check` | Full color health report |
| `map` | Regenerate README.md |
| `update` | Pull latest from GitHub |
| `note "msg"` | Leave a message for next agent |
| `export` | Package for migration |
