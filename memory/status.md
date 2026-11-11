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

## Committed 2026-11-11

- `e21b623`: discovery as a tree of responsibility, with projects named
  by their agent's handle (the work `TODO.md` dates 2026-10-10). It
  type-checks (`crystal build --no-codegen src/aix.cr`), but hasn't been
  run against a live tmux session since.
- `7ab2062`: a real README, and `TODO.md` updated with the 2026-11-11
  decisions (`decisions.md`, `runner.md`).

## Not yet committed (2026-11-11)

- `crystal spec` runs: `Aix.run` moved to `src/main.cr` (`shard.yml`'s
  main). 35 specs cover discovery, naming, config, the harness, the bell
  and inotify.
- The mail bell (`decisions.md`, "The mail bell"): `src/aix/bell.cr`,
  `mail_bell.cr`, `inotify.cr`, `harness.cr`, and `aix tell`. Tested live
  in a throwaway Claude Code window: it rings an idle session, holds for a
  draft (leaving it alone), and gives exit 3 for an unknown window. It also
  finds a session by Claude session id, rings on delivery through the
  bridge, retries after a draft is cleared, and drops the ring once the
  mail is filed.

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
