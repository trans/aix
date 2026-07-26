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
- [ ] Leader role/system prompt: instruct the Leader to call `set_leader` on
      itself at startup (so F9 is always bound) and to report/route via its
      tools. (Part of `aix setup`? or the launch config.)
- [ ] Rebind F9 from config.leader on session (re)creation, so it survives a
      tmux server restart even before the Leader self-designates.
- [ ] Keybinds: return-to-Leader (F9, done), detach, quit. Tentative rule:
      exit-to-shell only from the console/top-level, not from inside an agent
      pane.
- [ ] TUI stays as a read-only dashboard (glance-able all-agents view); web UI
      as read-only monitor later.

## Housekeeping

- [ ] `crystal spec` is unrunnable: `spec/spec_helper.cr` requires
      `../src/aix`, whose last line is `Aix.run` (launches the TUI). Guard the
      entry point before adding real specs.
- [ ] README is still boilerplate.
