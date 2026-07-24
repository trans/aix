# AIX — TODO

## Bus bridge (in progress)

- [x] Native Arcana HTTP client (`src/aix/arcana.cr`)
- [x] Bridge: watch `message.sent` events → keystroke wake-up of the target
      session; park on `@aix` mailbox for sub-agent reports (`src/aix/bus_bridge.cr`)
- [ ] **Switch nudge trigger from polling to pub/sub push.** The bridge
      currently polls `GET /events`. Arcana already has topics
      (`POST /publish` + subscribe). Add a system firehose topic that Arcana
      tees every delivery to (e.g. `sys.message.sent`), subscribe `@aix`, and
      long-poll `/receive` on it — instant, poll-free, same mechanism as the
      inbox listener. **Requires an Arcana-side change** (we control Arcana).
      See `TODO(pubsub)` in `src/aix/bus_bridge.cr`.
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
