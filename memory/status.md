# Status

*Updated 2026-11-13*

Where Aix stands. The backlog, item by item, is `TODO.md` in the code repo;
this note is the handoff, not a copy of it.

## On main, pushed

Last tag: `v0.2.0` (2026-04-15). Since then:

- Control API and MCP server (`f091df0`), the meta console's Leader
  routing (`d596a95`), `focus` / `set_leader` and the F9 return-to-Leader
  key (`7b41a71`).
- Discovery as a tree of responsibility, projects named by their agent's
  handle (`e21b623`), then by dot-ai's search: git config `ai.path`, 4
  levels (`5c0f903`, `423785f`).
- The mail bell and `aix tell` (`5ef8b34`); aix as dot-ai's runner under
  Draft 0.5 (`5c0f903`, `runner.md`).
- `4053108` (2026-11-13): the TUI's screen preview (`Screens`); quitting
  the TUI leaves agents running; exited windows stay (`remain-on-exit`,
  respawned in place), after the user's report of opening onboard and
  landing in arcana's window; resume falls back from the session's
  transcript to `--continue` to a new conversation; `aix --bridge`, `aix
  update` and the inotify watcher retired. 51 specs pass.

Tested live: the bell and `aix tell` (@arcana and @chantest, both in aix,
woke each other). The preview and exited windows were tested in a separate
tmux server with a fake `claude`, not yet in the user's own session.

## Next

From `TODO.md`:

1. Codex in aix: `codex --no-daemon` with `DOT_AI_BY=aix`, and the bell
   for Codex from the dot-ai record's `state`.
2. The preview: colour, and the list's ●/○ refreshed while the TUI is
   open. The Resume box may belong to the selected project.
3. The lead's tools: processes under an agent's pane with their memory
   use, and killing one.
4. Rebind F9 from `config.leader` whenever the session is created again.
5. The sidebar file browser.
