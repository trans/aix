# Decisions

*Updated 2026-11-11*

The design decisions behind Aix: who made each one, when, and why. All of
them are **settled**, so don't reopen them. They belong in the project's own
docs, but the README is still boilerplate, so they stay here until it's
written. Move them there then, and leave a pointer.

## Layering (user, 2026-03)

- **Arcana**: messaging, discovery and routing (the bus).
- **Copious**: orchestration, context windowing and event sourcing. A
  separate shard.
- **Aix**: the multi-agent leader's machinery. It runs harnesses in tmux,
  bridges the bus to them, and exposes a control plane.

Aix doesn't duplicate what Arcana provides.

## The Leader is a harness, not Copious (user, 2026-07)

There are two roles. The managed agents are tmux harnesses, which is Aix's
core. The Leader is just another harness (Claude Code) that drives Aix
through tools. This gives the Leader a full agentic loop for free. Move to
Copious only when something like durable, event-sourced context can't be
built as tools the harness Leader calls. The Leader can be swapped out
behind `Aix::Control` + `Aix::MCPServer` (`aix --mcp`, `f091df0`). Any
Leader can drive Aix through it: a harness, Copious, or a remote agent.
State lives in tmux and the filesystem, so the MCP server and the TUI share
one `aix` tmux session.

## The Leader is the UI (user, 2026-07-25)

The person tmux-attaches to the Leader and works in natural language. The
Leader uses the aix-control MCP tools (`focus` switches the person's view
with `select-window`). Aix doesn't build a custom console.

- The REPL's meta-console routing (`d596a95`) is a fallback when there's
  no Leader, not the main interface.
- The TUI stays as a read-only dashboard. The web UI becomes a read-only
  monitor later.
- Aix needs only a few keybinds: return-to-Leader (F9, done), detach, quit.
  Tentatively, exiting to the shell is allowed only from the top level,
  never from inside an agent's pane.
- `@lead` is the only Leader for now (user, 2026-10-10).

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

## Aix carries dot-ai mail; dot-ai keeps a reference carrier (user, 2026-11-11)

Aix becomes a mail carrier (`ai.carrier aix`). dot-ai keeps the commands
agents use and its simple `local` carrier as the reference. The design is
still open: see `carrier.md`.

## Known limit

`send` and `peek` scrape the screen (`capture_pane`). That's fine for
interactive harnesses. Structured results would need a headless or JSON
mode for the harness. **Open**, nothing planned.
