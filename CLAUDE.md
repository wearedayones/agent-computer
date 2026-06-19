# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Session Startup (do this every time you arrive)

```bash
boot        # quick orientation: pulse, inbox, last changes, command reference
```

Or manually:
```bash
cat ~/AGENT.md          # full computer guide
cat ~/README.md         # live state + alerts
check                   # full color health report
```

If README or `boot` shows any alerts — fix those first.

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
| **Root (`~/`)** | **NOTHING** — only the 3 `.md` files that already exist |

**Creating new sub-folders is allowed** — but only inside an existing zone, never at root.
Example: need screenshots? → `mkdir ~/media/screenshots` ✓ — not `mkdir ~/screenshots` ✗

### Never delete without archiving
Move to `~/archive/<name>/` first. Never `rm -rf` an app or project directly.

### Always update the map after changes
```bash
map
```

---

## Permission Mode
`bypassPermissions` — no confirmation prompts needed for normal operations.

---

## Quick Reference

| Command | Action |
|---------|--------|
| `boot` | Session startup: pulse + inbox + quick commands |
| `check` | Full color health report |
| `map` | Regenerate README.md |
| `update` | Pull latest from GitHub |
| `note "msg"` | Leave a message for next agent |
| `export` | Package for migration |
