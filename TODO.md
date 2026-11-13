# AIX — TODO

## Mail: the bell, and aix as dot-ai's runner

The Arcana bus bridge is gone (2026-11-12): with dot-ai's local carrier,
Arcana refuses agent mail to dot-ai projects, and what it does deliver to
one it also writes into the inbox, where the bell sees it. So nothing polls
Arcana, and aix doesn't need it running.

- [x] The mail bell (2026-11-11): aix types the fixed notice into an
      agent's pane when it's idle at an empty prompt (`Bell`). `aix
      --bridge` watches inboxes with inotify and rings, retrying while
      held; `aix tell ID` rings once. dot-ai's Claude Code channel is the
      fallback, with `"mail": {"channel": true}`.
- [x] aix finds projects by dot-ai's search (user, 2026-11-12): git
      config's `ai.path`, 4 levels, no links, no hidden directories or
      `node_modules/`; adding or removing a root changes `ai.path`. aix's
      own `roots` only without `ai.path`. The bell searches at its start
      and on `aix update`; no timer searches.
- [x] Draft 0.5's runner duties (dot.ai `c90cc8f`, 2026-11-12): aix
      registers `~/.local/state/dot-ai/runners/aix` each time it starts a
      session (`Runner`); `aix tell` finds a session's pane by its record's
      pid too, answers 4 for one still running outside aix's panes (an
      inherited `DOT_AI_BY`, or no pid to check), and 3 otherwise, marking
      its own record `ended`.
- [ ] Retire `aix --bridge` once dot-ai 0.10.0 (the reference that runs
      `<runner> tell`) is installed in Claude Code and Codex. Check first
      that the carrier runs `aix tell` on delivery.
- [ ] Codex in aix: start `codex --no-daemon` with `DOT_AI_BY=aix`. Its
      app server runs in the pane's process, and its hooks see the
      variable (tested 2026-11-12). A plain `codex` uses the shared daemon
      and gets the daemon's environment instead.
- [ ] The bell for Codex: read the dot-ai record's `state` for idle (Codex
      has no status file), then type the notice as for Claude Code. `codex
      queue` may not reach a `--no-daemon` session.
- [ ] Bell, untested live: the "user is typing in that pane" guard needs
      an attached client.
- [ ] Bell, once the sidebar shares windows: `Tmux.pane_info` takes a
      window's first pane, which has to be the agent's.

## Leader-as-UI (the primary interface)

Decided: the human tmux-attaches to the Leader harness (Claude Code) and
drives everything via its aix-control MCP tools + natural language. No custom
console.

- [x] Leader host = harness-as-Leader (Copious deferred).
- [x] MetaConsole routing (step 3) — built, but SUPERSEDED as primary; kept
      as a no-Leader/headless fallback.
- [x] `focus(name)` MCP tool — "patch me over to @memo" (select-window).
- [x] `set_leader(name)` MCP tool + return-to-Leader keybind (F9); persists
      config.leader. `get_leader` reports it.
- [x] Leader self-designates at startup: the `lead` project's SessionStart
      hook calls `set_leader` for `lead` when it starts inside aix's tmux
      session (2026-10-10). @lead is the only Leader for now (Thomas).
- [x] Discovery is a tree of responsibility (2026-10-10): the scan goes on
      inside projects, and a project inside another's directory is below it.
      `list_projects` reports each one's `parent`; the TUI and console
      indent. (Before, `~/Projects/.ai` hid every project under it.)
- [x] Projects are named by their agent's Arcana handle (2026-10-10): the
      handle in `.ai/config.yml` without the `@`, or Arcana's fallback (the
      directory name, lower-cased and dashed). So the bell's `@name` →
      window `name` mapping holds even when they differ: `~/ai` is `lead`,
      `infocomics` is `overlore`, `Projects` is `projects`.
- [ ] Rebind F9 from config.leader on session (re)creation, so it survives a
      tmux server restart even before the Leader self-designates.
- [ ] Keybinds: return-to-Leader (F9, done), detach, quit. Tentative rule:
      exit-to-shell only from the console/top-level, not from inside an agent
      pane.
- [ ] Sidebar (user, 2026-11-11): the crt UI as a narrow tmux pane beside
      the agent's pane, in place of a full-screen attach. On a switch,
      `join-pane` the sidebar into the agent's window, so agents keep
      their windows and names. Target agent panes by id (`%N`), not
      `aix:name`, once windows have two panes.
- [ ] Sidebar file browser (user, 2026-11-11): get to the files agents
      mention without navigating, since CLI links often don't work. Open
      with `xdg-open`. List the files the agent touched first (from the
      harness's session log), then `git status`, then the tree.
- [ ] The lead passes things on by mail, then rings the bell (user,
      2026-11-11). `send` (typing into a pane) is only for emergencies,
      which a busy agent sees the next time it looks up. When that's too
      late, the lead kills the offending process and tells the agent
      afterwards.
- [ ] Control tools for that: list the processes under an agent's pane
      with their memory use ("is it going to OOM?"), and kill one of them.
      `status` reports no resources, and `peek` only reads the screen.

## Housekeeping

- [x] `crystal spec` runs (2026-11-11): the entry point moved to
      `src/main.cr`, so specs require `src/aix.cr` without launching the
      TUI. Specs cover discovery, handle naming, config and harness args.
- [x] README describes aix (2026-11-11).
