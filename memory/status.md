# Status

*Updated 2026-11-25*

Where Aix stands. The backlog, item by item, is `TODO.md` in the code repo;
this note is the handoff, not a copy of it.

## On main, pushed

Last tag: `v0.5.0` (`88af26f`, 2026-11-25, the user's call): the web
page and message box, the web server guarded, copy mode, exact tmux
targets. `v0.4.0` was `34c7d01`, `v0.3.2`
`84b9d73`, `v0.3.1` `3672845`, `v0.3.0` `7e9f693`.
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
- In 0.4.0, after 0.3.2: `3e374e6` (`r` refreshes the TUI, the list keeps
  its place) and `8c6403b` (2026-11-16: the agent's pane is marked
  `@aix-agent`, so a pane added by `Ctrl-b *` or a split isn't taken for
  it, and only that pane stays after exiting; aix's own status line, no
  window numbers; `history-limit` left to the person). The user, on the
  bar: "Much better."
- `e4b43ce` (2026-11-17): the file pane, the user's design ("each agent
  session has an associated current browsing directory"). `F8` opens
  and closes yazi on the agent window's right half; each agent keeps the
  directory it was left in. The first build's issues, from the user:
  no way to close it, too squeezed, and yazi's parent directory column
  read as "a list of parent directories"; so `F8` closes, half width,
  and aix's own yazi settings drop that column. The agent's title moved
  to the bar's left, after the handle (the user's choice). Next: the
  files the agent touched first (TODO).
- After 0.4.0, untagged: `1b3f96e` (2026-11-18). The user's "loose
  cursor" was tmux's copy mode (entered by the mouse wheel or a drag,
  since Claude Code doesn't take the mouse); the bar now says so. It hid
  a bell bug: the bell rang a pane in copy mode and its keys went to the
  mode, so the notice was lost; it now leaves the mode first (tested in
  an isolated server: keys sent in copy mode never reached the program).
  Also `aix --version`, and unknown options refused. The user, after:
  "Aix is working well", "good work".
- `ad16257` (2026-11-24): typing leaves copy mode in the aix session
  (the user still stumbled into it); other sessions keep copy mode's
  keys. Untagged.
- `9d92e83` (2026-11-25): the web page, the user's idea (2026-11-24:
  "use tmux to route the console into html… a webui, or perhaps an
  actual gui application, with the agent/project selection [and] file
  tree both visible"). Three columns: agents | the conversation, from
  Claude Code's transcript (markdown rendered, followed live) | files.
  Also closed a hole found on the way: the old dashboard took typing
  into agents from any web page (no Origin check, no secret); now a
  secret cookie, Origin and Host checks. The user: "That's pretty
  awesome!" (then: centre the chat, larger file tree, done). Next
  stages, agreed: a live terminal in the page (tmux control mode to
  xterm.js, kept in aix) and typing from it; Codex conversations; a
  native window (webview). Untagged.
- `f285ddf` (2026-11-25): writing to an agent from the page (the user:
  "use a textarea, and then send it at once"). A message is pasted whole
  (bracketed paste), then Enter, only at an empty input box; otherwise
  the page shows the agent's screen and keys, and what's written is
  typed as keys (the user asked whether menus needed handling: no, "1",
  Enter does). Tested with real Claude Code (Haiku, scratch folder,
  isolated server, hooks off). Also fixed: tmux targets were bare `aix`,
  taken first for a window named `aix`, so new windows would fail once
  this project's window is in the session; now `=aix:`. Codex in the
  box untested. In 0.5.0.

## Open: the terminal as aix's face (2026-11-24)

The user's quirks with tmux: copy mode, its mouse menus, and the agent
list and file pane not staying visible. They asked whether a terminal
with vertical tabs and a file sidebar could replace tmux, leaving aix
smaller. Found: kitty has vertical tabs (0.48+, `tab_bar_edge`) and a
documented remote control (`kitten @`), but no file browser (yazi in a
split); Tabby has side tabs but is Electron and has no remote control of
its own; Ashy Terminal (Python, VTE) has a file panel but no vertical
tabs. Without tmux, aix loses agents outliving the terminal, running
with no window (web, the lead's `start`), attaching from elsewhere, the
bell's typing guard, and headless testing. abduco/dtach/shpool keep
agents running but keep no screen, so the bell's empty-prompt check and
the preview go. My suggestion: keep tmux as hidden plumbing (a session
per agent, its UI off), kitty as the face (a tab per agent, yazi split);
unknown: scrollback through tmux. **Undecided**: the user is thinking on
it ("kitty still doesn't have the file browser though").

2026-11-25: the user stopped the web page's development ("so many small
issues… would take a long time to perfect"); it stays as in 0.5.0, the
planned events/terminal/Codex/window stages dropped. Instead: a terminal
with a vertical tab list (labels aix sets) and ideally a file sidebar,
as the base for aix's extras. Looked at: Wave (side tabs since 0.14.4,
file pane, Electron, `wsh` can't type into a tab), Warp (side tabs, file
tree, closed, no control of open tabs), Konsole (side tabs since 2024,
D-Bus), kitty 0.49 (side tabs, full remote control, no files), Ghostty
(Zig; side tabs only in an archived fork). The user then proposed
forking COSMIC Terminal (Rust, ~9.7k lines, alacritty_terminal and
libcosmic, which has `tab_bar::vertical`; horizontal tabs only, no file
pane, no remote control) and upstreaming piece by piece. Blocked:
System76's contributor guide (pop-os/pop CONTRIBUTING.md) refuses LLM
content in issues and PRs, code, comments and descriptions, so nothing
of ours can go upstream. The user will file a request for vertical tabs
in their own words (no issue template; none existing found) "and see
what they say". **Open**: fork for ourselves, or kitty unmodified (my
recommendation, with yazi in a split).

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
