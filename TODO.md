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

## Leader / orchestration (step 3)

- [ ] Decide Leader host (harness-as-Leader now vs Copious later) — see memory
      `project_orchestrator`. Bridge is a prerequisite either way.
- [ ] MetaConsole routing: bare text -> Leader, `name:` -> route to sub-agent,
      `\name` -> private passthrough channel.

## Housekeeping

- [ ] `crystal spec` is unrunnable: `spec/spec_helper.cr` requires
      `../src/aix`, whose last line is `Aix.run` (launches the TUI). Guard the
      entry point before adding real specs.
- [ ] README is still boilerplate.
