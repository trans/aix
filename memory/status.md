# Status

*Updated 2026-11-14*

Where Aix stands. The backlog, item by item, is `TODO.md` in the code repo;
this note is the handoff, not a copy of it.

## On main, pushed

Last tag: `v0.3.2` (`84b9d73`, 2026-11-14). `v0.3.1` was `3672845`,
`v0.3.0` `7e9f693`.
Since `v0.2.0` (2026-04-15):

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

- `74cd14e` (2026-11-14): Codex as well as Claude Code. A project with an
  `AGENTS.md` and no `CLAUDE.md` runs Codex; `h` in the TUI (or `start`'s
  `harness`) switches one, kept in the config by directory. Codex starts
  as `codex --no-daemon`, resumes with `resume --last`. The bell rings it
  from the dot-ai record naming its pane's process, at an input line with
  only dim placeholder text after `›`. aix registers as the runner only
  when the program is named `aix` (a `crystal eval` test once took its
  place for a minute). 64 specs pass.
- 0.3.1 (2026-11-14): `cfc9049` fixes the bell while any window has
  exited (`Tmux.window_pids` failed on a dead pane's empty pid, so `aix
  tell <id>` found no window and answered 4; 0.3.0 has the bug).
  `35b1062`: conversations open in other programs (`Conversations`:
  Claude Code's `~/.claude/sessions/`, Codex's per-conversation locks
  read through `/proc/locks`), marked `◐` in the TUI with where; aix
  doesn't resume one another program holds (dot-ai's one runner per
  session). The Resume box is gone, the user's design: Enter resumes, `n`
  starts a new conversation. 72 specs pass.
- 0.3.2 (2026-11-14), `f9e86bf`: the web dashboard (Start, New) and the
  lead's `start` (`resume`, default true) resume by default too. The
  user wondered whether the lead's default should be the lead's to pick;
  resume was agreed, for one meaning of "start" everywhere, with
  `resume: false` for a task that needs no history. 73 specs pass. The
  user expects a pause after this ("we might be good for a little bit").

Tested live: the bell and `aix tell` (@arcana and @chantest, both in aix,
woke each other); Codex's bell in a scratch project in a separate tmux
server; the user opened onboard with the fixes in their own session ("it
mostly works", the rest being Codex). With 0.3.0 onboard opened in Codex
in the user's own session (2026-11-14), as `codex --no-daemon resume
--last`, and resumed its conversation from VS Code (`01a13023…`, the
newest of its two, both VS Code's): `--last` finds those.

## Next

From `TODO.md`:

1. Codex's open ends (`TODO.md`): no ring before its first prompt (no
   record yet), and an interrupted turn leaves its record `busy`, a
   question for @tom.
2. The preview: colour, and the list's ●/○ refreshed while the TUI is
   open. The Resume box may belong to the selected project.
3. The lead's tools: processes under an agent's pane with their memory
   use, and killing one.
4. Rebind F9 from `config.leader` whenever the session is created again.
5. The sidebar file browser.
