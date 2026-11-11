# Status

*Updated 2026-11-11*

Where Aix stands. The backlog, item by item, is `TODO.md` in the code repo;
this note is the handoff, not a copy of it.

## Committed

Last code commit before `.ai/` was set up: `d457742` (2026-07-26). Built and
on `main`: the tmux multiplexer, TUI / REPL / web / MCP / bridge modes,
discovery of projects by `.ai/`, the Control API and MCP server (`f091df0`),
the bus bridge (`c727357`, registered as the `aix` service in `bab1d04`),
the meta console's Leader routing (`d596a95`), and the `focus` /
`set_leader` tools with the F9 return-to-Leader keybind (`7b41a71`).

## Not yet committed (in the working tree as of 2026-11-11)

**Done, not yet committed:** discovery as a tree of responsibility, and
projects named by their agent's handle. `TODO.md` dates both 2026-10-10.

- `src/aix/config.cr`: the scan goes on inside projects; `discover`
  returns `Config::Project` records with `parent` and `level`, in tree
  order. A project's name is `handle` from its `.ai/config.yml` (or the
  older `arcana.handle`), otherwise Arcana's fallback (the directory name,
  folded). This keeps the bridge's `@name` → window `name` mapping working.
- `control.cr`, `mcp_server.cr`, `session.cr`, `session_manager.cr`,
  `tui.cr`, `meta_console.cr`: these carry `parent` through, so
  `list_projects` reports it and the TUI and console indent.
- `TODO.md`: these items are marked done, and so is the Leader's
  self-designation (the `lead` project's SessionStart hook calls
  `set_leader`).

Before committing, check that it builds (`crystal build src/aix.cr`).
`crystal spec` doesn't work yet (see Next).

## Next

From `TODO.md`, roughly in order, plus the runner work decided on
2026-11-11 (`runner.md`: session records, `DOT_AI_BY`, `aix tell`, the
push glue), which `TODO.md` doesn't list yet:

1. **Open:** move the bridge's nudge from polling `/events` to push. The
   firehose is changing on Arcana's side (see `coordination.md`), so wait
   for that before writing it. For mail, `aix tell` replaces the nudge
   (`runner.md`), so only bus traffic that isn't mail might still need it.
2. **Open:** a launch config that brings agents up on the bus already
   registered, with tools pre-approved and the reporting instruction.
   First find out what the session hooks already handle. They now
   register each project as `@handle`. If Arcana's tools are also
   pre-approved globally, little is left to do. If not, `start` passes
   `--allowed-tools mcp__arcana__*`.
3. **Open:** don't nudge a busy (mid-turn) session.
4. **Open:** rebind F9 from `config.leader` whenever the session is
   created again.
5. **Open:** housekeeping. Guard the `Aix.run` entry point so
   `crystal spec` can run, and replace the boilerplate README.
