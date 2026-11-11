# Decisions

*Updated 2026-11-11*

The design decisions behind Aix: who made each one, when, and why. They
belong in the project's own docs, but the README is still boilerplate, so
they stay here until it's written. Move them there then, and leave a
pointer.

**Things have changed since 2026-07** (the user, 2026-11-11). Some of the
sections below came from an earlier agent's notes from 2026-07, not
straight from the user. Where they disagree with "What Aix is", that
section wins. Check with the user before relying on them.

## What Aix is (user, 2026-11-11)

Aix is a tmux-based manager for AI harnesses, like `amux` and others.
What sets it apart: as far as the user knows, the others pass messages
between agents by typing into their panes, while Aix uses mail (dot-ai).
The agents are full harnesses (Claude Code, Codex, ...), and with Aix the
user jumps between them and talks to each one directly. Aix manages them
and helps them communicate: it rings the mail bell (see `runner.md`).

**Aix has its own master session, the lead** (the user, 2026-11-11). The
user can jump between agents but often doesn't need to: the master
session coordinates for them ("tell @yaml2 to ...", "stop @imm, is it
going to OOM?"). It does that through Aix's control tools (`aix --mcp`).
Aix's lead is more detached than T.O.M.'s: Aix is a tmux-based system of
independent harnesses, while T.O.M. is fully integrated, with its own
harness (Copious) and memory system. T.O.M. runs other projects' agents
through its own runners (the user, 2026-11-11, per @tom's notes).

## Layering (2026-03; partly outdated)

- **Arcana**: messaging, discovery and routing (the bus).
- **Copious**: orchestration, context windowing and event sourcing. A
  separate shard, now inside T.O.M.
- **Aix**: the multi-agent leader's machinery. That still holds for its
  own, tmux-based fleet (see "What Aix is").

Aix doesn't duplicate what Arcana provides.

## The Leader is a harness (2026-07, from an earlier agent's notes)

There are two roles. The managed agents are tmux harnesses, which is Aix's
core. The Leader is just another harness (Claude Code) that drives Aix
through tools. Aix exposes those tools through `Aix::Control` +
`Aix::MCPServer` (`aix --mcp`, `f091df0`), so any Leader can drive it.
State lives in tmux and the filesystem, so the MCP server and the TUI share
one `aix` tmux session. T.O.M.'s notes suggest T.O.M. as aix's Leader
later. **Not decided.**

## The lead as the usual way in (2026-07-25; confirmed in substance 2026-11-11)

The person tmux-attaches to the lead and works in natural language. The
lead uses Aix's control tools: `focus` switches the person's view with
`select-window`. The user confirmed the core of this on 2026-11-11 (see
"What Aix is"). Built so far: `focus`, `set_leader`, the F9
return-to-lead keybind (`7b41a71`), and meta-console routing in the REPL
(`d596a95`). `@lead` was the only Leader as of 2026-10-10.

- **Wrong, corrected 2026-11-11:** the 2026-07 notes (and `TODO.md`,
  `d457742`) said "the TUI stays a read-only dashboard". The user never
  said so. What part the TUI plays is **open**.
- **Decided (user, 2026-11-11): the lead passes things on by mail.**
  "tell @yaml2 to ..." means the lead sends @yaml2 mail, and then @yaml2
  is told "you have mail". Typing straight into an agent's pane (`send`)
  is only for emergencies, such as "OOM is imminent, stop what you are
  doing now!".
  - **Emergencies come in degrees (user, 2026-11-11).** `send` types the
    text and presses Enter (`Tmux.send_keys`), and a busy agent sees it
    only the next time it "looks up" (when its running tool returns, or
    its turn ends). Often that's soon enough. When it isn't, the lead
    kills the offending process itself and tells the agent afterwards. So
    `send` doesn't need to interrupt with Escape.
  - **What the lead needs for that:** a way to see what's running under an
    agent's pane, with memory use ("is it going to OOM?"), and to kill
    one process. Today's tools can't do either: `status` reports no
    resources, and `peek` only reads the screen. **Open**, not yet built.
  - **Found 2026-11-11:** aix starts plain `claude`
    (`tmux new-window -- claude`, `src/aix/tmux.cr`), without dot-ai's
    channel option. The user's shell alias doesn't apply there, so
    sessions aix starts get no mail push. They hear of mail only at
    session start, at Stop or at a prompt. Until `aix tell` exists, aix
    could launch with the channel option.

## Addressing: `@` for agents, bare names for services (user, 2026-07-25)

`@aix` is this project's agent. `aix` (kind: service, unlisted) is the
bridge. They have separate mailboxes. The bridge wakes `@beta` by sending
keys to the tmux window `beta`. That's why projects are named by their
handle (see `status.md`).

## Two planes: wake and data (agreed 2026-07)

- **Wake plane:** delivery metadata (`recipient`, `sender`, ...) goes to
  the `aix` service. The bridge uses it only to choose which pane to wake.
  It never reaches the Leader.
- **Data plane:** agents send short summaries to the Leader as ordinary
  messages. The Leader reads those summaries, not raw output. `peek` is the
  escape hatch.

## Aix is a runner, not a mail carrier (user, 2026-11-11)

The carriers are `local` and `arcana`. Aix tells the sessions it runs
about their mail and pushes only to idle ones; the hooks inside each
session keep the start/Stop notices. This replaces the same day's choice
of `ai.carrier aix`. See `runner.md`.

## Crystal and crt, or Rust? (open, 2026-11-11)

**Not decided.** The user asked whether to stay with Crystal and their own
TUI library, crt (still beta), or move to Rust and its mature TUI
libraries.

- **Aix's agent recommends Crystal and crt**, less firmly since the TUI
  turned out to matter more than a read-only dashboard would. The reasons:
  - Arcana and T.O.M. are Crystal, so aix can share code with them.
  - The work coming next (runner, tmux, processes) is plumbing with no
    TUI in it.
  - The agents' own screens are the harnesses in tmux, not aix's TUI.
- **The user's point:** staying means fixing crt now and then. The
  downside is that we handle that ourselves; the upside is that we
  control it. T.O.M. also uses crt, so its fixes help both.

## Known limit

`send` and `peek` scrape the screen (`capture_pane`). That's fine for
interactive harnesses. Structured results would need a headless or JSON
mode for the harness. **Open**, nothing planned.
