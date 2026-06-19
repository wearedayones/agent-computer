# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Session Startup (every time you arrive)

```bash
boot
```

If `boot` shows any alerts — **fix those first before doing anything else.**

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
