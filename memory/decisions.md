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

Earlier, on 2026-11-10, the user said they didn't really need aix, and
then brought it back as its own project. Fleet management (running other
projects' agents headless, on demand) is T.O.M.'s (user, 2026-11-11, per
@tom's notes). So Aix isn't the multi-agent leader that the 2026-03
layering below describes.

## Layering (2026-03; partly outdated)

- **Arcana**: messaging, discovery and routing (the bus).
- **Copious**: orchestration, context windowing and event sourcing. A
  separate shard, now inside T.O.M.
- **Aix**: the multi-agent leader's machinery, as first conceived. See
  "What Aix is" above for what it is now.

Aix doesn't duplicate what Arcana provides.

## The Leader is a harness (2026-07, from an earlier agent's notes)

There are two roles. The managed agents are tmux harnesses, which is Aix's
core. The Leader is just another harness (Claude Code) that drives Aix
through tools. Aix exposes those tools through `Aix::Control` +
`Aix::MCPServer` (`aix --mcp`, `f091df0`), so any Leader can drive it.
State lives in tmux and the filesystem, so the MCP server and the TUI share
one `aix` tmux session. T.O.M.'s notes suggest T.O.M. as aix's Leader
later. **Not decided.**

## Leader-as-UI (2026-07-25, from an earlier agent's notes; unconfirmed)

The 2026-07 notes had the person tmux-attach to the Leader and work in
natural language, with the Leader's `focus` tool switching the view, and
no custom console. Built: `focus`, `set_leader`, F9 return-to-Leader
(`7b41a71`), and meta-console routing in the REPL (`d596a95`). `@lead` was
the only Leader as of 2026-10-10.

- **Wrong, corrected 2026-11-11:** those notes (and `TODO.md`, `d457742`)
  said "the TUI stays a read-only dashboard". The user never said so. It
  conflicts with "What Aix is": the user jumps between agents and talks
  to them directly. What the TUI's part in that is remains **open**.
- How much of Leader-as-UI still holds is for the user to say.

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

## Known limit

`send` and `peek` scrape the screen (`capture_pane`). That's fine for
interactive harnesses. Structured results would need a headless or JSON
mode for the harness. **Open**, nothing planned.
