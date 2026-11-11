# AIX — TODO

## Bus bridge (in progress)

- [x] Native Arcana HTTP client (`src/aix/arcana.cr`)
- [x] Bridge: watch `message.sent` events → keystroke wake-up of the target
      session; park on `@aix` mailbox for sub-agent reports (`src/aix/bus_bridge.cr`)
- [ ] **Switch nudge trigger from polling to pub/sub push.** Contract LOCKED
      with @arcana (2026-07-25); Arcana ships it as **arcana-core 0.13.0 +
      arcana 0.27.0** (a `Bus after_send` hook → publish). Then on our side:
      - Subscribe service `aix` to topic **`sys.message.sent`**.
      - Long-poll `POST /receive` on `aix` (firehose copies land in aix's own
        mailbox — confirmed distinct from `@aix`). Feed each envelope's
        `recipient` straight into `maybe_nudge`. Replaces the `/events` poll.
      - Payload: `{recipient, sender, ordering, correlation_id, subject,
        timestamp}`.
      - Gated server-side on `ARCANA_SYSTEM_TOPICS=1` (default OFF) — Thomas
        flips it on and restarts Arcana; verify push, then delete the poll.
      - Invariant (confirmed): one mailbox per address, competing consumers
        race per-message — exactly ONE process may consume `aix`.
      See `TODO(pubsub)` in `src/aix/bus_bridge.cr`.
      Later: ask for `sys.listing.registered` (auto-map newly-joined agents).
- [ ] Sub-agent launch config: bring agents up on the bus automatically —
      register as `@<name>`, pre-approve Arcana MCP tools (no permission
      prompts), inject the standing "report to @aix / check mail when nudged"
      instruction. (Kills the manual register/approve steps.)
- [ ] Don't nudge a session that is mid-turn (busy) — detect idle before
      injecting keystrokes, or debounce more intelligently than a flat cooldown.
- [ ] Gate nudges on discovered projects (not just any live window) once the
      Leader/orchestrator wiring lands.
- [ ] Surface/relay inbox messages to the Leader instead of just logging
      (`TODO(leader)` in `bus_bridge.cr`).

## Leader-as-UI (the primary interface)

Decided: the human tmux-attaches to the Leader harness (Claude Code) and
drives everything via its aix-control MCP tools + natural language. No custom
console. See memory `project_orchestrator`.

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
      directory name, lower-cased and dashed). So the bridge's `@name` →
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
- [ ] Launch Claude Code with dot-ai's channel option
      (`--dangerously-load-development-channels plugin:dot-ai@dot-ai`).
      `Tmux.new_window` runs plain `claude`, so sessions aix starts get no
      mail push until `aix tell` exists.

## Housekeeping

- [ ] `crystal spec` is unrunnable: `spec/spec_helper.cr` requires
      `../src/aix`, whose last line is `Aix.run` (launches the TUI). Guard the
      entry point before adding real specs.
- [ ] README is still boilerplate.
