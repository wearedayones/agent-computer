# Claude Code — Agent Computer

> **READ THIS ENTIRE FILE BEFORE DOING ANYTHING.**
> Then read `~/AGENT.md` for the full computer guide.
> Then check `~/README.md` for live system state.

---

## Why Protocol Compliance Matters

This computer is shared across multiple AI agents over time. You are not the first. You are not the last.

**When you skip the protocol, you break the next agent:**
- Skip `boot` → you act on stale context. You repeat work that was already done. You undo changes that were intentional.
- Skip `note` → the next agent inherits invisible state. They cannot tell what you changed, why, or what broke. They will make wrong decisions.
- Skip `trace` → outcome memory fails. The next agent runs the same failed strategy, makes the same mistake, wastes the same time.
- Skip `task` → the work queue falls out of sync. Tasks get done twice or never.

One undisciplined agent degrades every agent that follows. This is not a guideline — it is the load-bearing structure of the system.

---

## Session Startup — MANDATORY, NO EXCEPTIONS

**Step 1: Run boot. Before you read anything else. Before you touch any file.**

```bash
boot
```

`boot` shows: disk health, active sessions, cron count, and **inbox messages from the previous agent**.
If `boot` shows a red `⚠ UNDOCUMENTED SESSION` warning — the previous agent left no note. Treat everything as uncertain. Read the session brief before acting.

**If `boot` shows inbox messages — read and act on them before doing anything else.**
**If `boot` shows disk < 2GB — free space before doing anything else.**

---

## Session End Checklist — Run Through This Before Closing

**1. Did you do any meaningful work?**
```bash
note "what you did, what's left, what to watch for"
```

**You MUST write a note if ANY of these are true:**
- You changed any file, config, cron job, or background process
- You completed or abandoned a task
- You discovered a problem — even one you didn't fix
- You added a dependency, key, or service
- The owner gave you a task spanning multiple sessions
- Anything broke, even temporarily

**You do NOT need a note only if:** you answered a question and changed absolutely nothing.

**2. Did you complete a task?**
```bash
axis task done <id>
axis trace log "<what you did>" --outcome success|fail --detail "<why it worked or why it failed>"
```

Trace is the anti-amnesia layer. Without it, the next agent repeats your work from scratch. If you completed something hard, or failed at something, **log it**.

**3. Did you run `map`?**
```bash
map
```
Always regenerate README.md after changes. It is the live state snapshot other agents read.

---

## File Rules — Agents Get These Wrong Most Often

### Never nest unnecessarily
```
✓  ~/documents/notes.md
✗  ~/documents/notes/notes.md
```
Only create a subfolder if you have **multiple related files** that belong together.

### Always check before creating
```bash
ls ~/documents/     # does the file exist?
cat ~/documents/foo.md   # read it before writing
```

### Zone map
| Type | Zone |
|------|------|
| New app / bot | `~/apps/<name>/` |
| New project | `~/projects/<name>/` |
| New script | `~/scripts/` |
| Notes / docs | `~/documents/` |
| Images / video / audio | `~/media/<type>/` |
| Temp files | `~/downloads/` |
| Python venvs | `~/apps/envs/<name>/` |
| **Root (`~`)** | **Nothing** — only AGENT.md, CLAUDE.md, README.md |

---

## Inter-Agent Messages → `note`, not files

```bash
note "your message"    # → ~/inbox/ — next agent reads this on boot
```

Never create files in `~/documents/` to pass messages to the next agent. The next agent reads `boot`, not your document files.

---

## After Every Change

```bash
map    # regenerate README.md — always
```

---

## Never Delete Without Archiving

```bash
mv ~/apps/old-bot ~/archive/old-bot   # ✓
rm -rf ~/apps/old-bot                 # ✗ never
```

---

## Protected Paths — Never Touch

```
~/keys/                           — API credentials, read-only
~/.hermes/                        — Hermes agent, managed externally
~/.bybit/                         — trading bot, active logs
~/apps/social-factory/tokens/     — OAuth tokens, read-only
```

---

## Permission Mode
`bypassPermissions` — no confirmation prompts for normal operations.
**Real-money trades, destructive actions, external posts — always confirm with the owner first.**

---

## Quick Reference

| Command | Action |
|---------|--------|
| `boot` | Session startup — run first, always |
| `check` | Full health report |
| `map` | Regenerate README.md |
| `update` | Pull latest from GitHub |
| `note "msg"` | Leave handoff for next agent |
| `axis trace log "..." --outcome success\|fail` | Log outcome to memory |
| `axis task add/list/done` | Work queue |
| `axis ctx brief` | LLM-ready state brief |
| `axis env show` | Machine mission + constraints |
| `axis trace last` | What worked / what failed |
| `axis doctor` | Deep diagnostics incl. session discipline |
| `budget log/show` | Spend tracking |
| `secret list/get` | Safe access to ~/keys/ |
| `export` | Package for migration |
