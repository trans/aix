# AIX — TODO

## Mail: the bell, and aix as dot-ai's runner

`aix --bridge` is gone (2026-11-13). Its Arcana half went first: under
dot-ai's local carrier, Arcana refuses agent mail to dot-ai projects. Its
inbox watcher went once dot-ai 0.10.0's carrier ran `aix tell` on delivery
(@arcana's test with the user, 2026-11-13: each of @arcana and @chantest,
both in aix, woke the other within a second). Nothing of aix's runs in the
background for mail.

- [x] The mail bell (2026-11-11): aix types the fixed notice into an
      agent's pane when it's idle at an empty prompt (`Bell`); `aix tell
      ID` rings once, and flashes a message when it has to wait. dot-ai's
      Claude Code channel is the fallback, with `"mail": {"channel":
      true}`.
- [x] aix finds projects by dot-ai's search (user, 2026-11-12): git
      config's `ai.path`, 4 levels, no links, no hidden directories or
      `node_modules/`; adding or removing a root changes `ai.path`. aix's
      own `roots` only without `ai.path`.
- [x] Draft 0.5's runner duties (dot.ai `c90cc8f`, 2026-11-12): aix
      registers `~/.local/state/dot-ai/runners/aix` each time it starts a
      session (`Runner`); `aix tell` finds a session's pane by its record's
      pid too, answers 4 for one still running outside aix's panes (an
      inherited `DOT_AI_BY`, or no pid to check), and 3 otherwise, marking
      its own record `ended`.
- [x] Retired `aix --bridge`, `aix update` and the inotify watcher
      (2026-11-13), once the carrier was seen running `aix tell`.
- [x] Codex in aix (user, 2026-11-13): a project runs Codex if it has an
      `AGENTS.md` and no `CLAUDE.md`, or if the person switched it (`h` in
      the TUI, `start`'s `harness`; kept in the config by directory). aix
      starts `codex --no-daemon` with `DOT_AI_BY=aix`, and resumes with
      `resume --last`, which starts a new conversation where there's none.
- [x] The bell for Codex (2026-11-13, tested live on Codex 0.167.2): idle
      from the dot-ai record naming the pane's process; empty input from
      the cursor's line, where Codex's placeholder is dim and a draft
      isn't. The notice went in and Codex took it as a prompt.
- [ ] A Codex session isn't rung until its first prompt: Codex's hooks
      write its record only then.
- [ ] An interrupted Codex turn (Esc) leaves its record `busy`, since no
      Stop hook runs, so the bell answers "busy" until its next turn ends.
      dot-ai's to settle, if anyone's: ask @tom.
- [ ] Which harness a project last ran isn't a good default: trying a
      project in the wrong one leaves a transcript there too. Detection
      stays with `AGENTS.md`; the choice is the person's.
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
- [x] The list with a screen beside it (user, 2026-11-12, in place of the
      join-pane sidebar of 2026-11-11): the TUI's right side shows the
      selected project's screen, live if its agent runs, else as aix last
      saw it (`Screens`, saved on leaving an agent and on stopping one).
- [x] An exited harness keeps its window (user's report, 2026-11-12:
      opening onboard showed "Stopped" and landed in arcana's window).
      Windows get `remain-on-exit`, so the error stays on screen, and
      opening it again restarts it in the same window. Resume uses the
      session id's transcript, else `--continue`, else a new conversation.
- [ ] The preview, next: colour (`capture-pane -e` and a parser for crt);
      the list's running marks (●/○) refreshed while the TUI is open.
- [ ] The Resume box stays ticked from one project to the next; it may
      belong to the selected project instead.
- [x] Quitting the TUI leaves agents running (2026-11-12); it used to stop
      them all.
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
