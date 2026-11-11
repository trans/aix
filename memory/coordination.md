# Coordination

*Updated 2026-11-11*

The projects Aix depends on or works with, and what's pending with each.

## @arcana (the bus)

- **Push nudges for the bridge.** On 2026-07-25 we agreed a contract with
  @arcana. Every delivery would be published to the system topic
  `sys.message.sent`, with payload `{recipient, sender, ordering,
  correlation_id, subject, timestamp}`. It's gated by `ARCANA_SYSTEM_TOPICS=1`.
  The `aix` service would subscribe to it and long-poll its own mailbox,
  replacing the `/events` poll (`TODO(pubsub)` in `src/aix/bus_bridge.cr`).
  - **Changed since then:** Arcana's note `.ai/memory/topics.md` (dated
    2026-10-13) says `sys.message.sent` "is still the old fan-out". It
    will become a `#` topic, under a new name, in Arcana's event-log
    cleanup, so Aix makes one change instead of two. **Open:** wait for
    that, then write the subscription against the new topic.
  - Exactly one process may consume the `aix` mailbox. Consumers of one
    mailbox compete for each message (confirmed with @arcana, 2026-07).
  - We may also ask for `sys.listing.registered` later, so agents that
    join get mapped automatically.
- Arcana has had shared-log `#topics` since arcana-core 0.19.0 / arcana
  0.35.2 (per Arcana's `topics.md`).

## @lead (the Leader)

The `lead` project's SessionStart hook calls `set_leader` for `lead` when it
starts inside Aix's tmux session (2026-10-10, per `TODO.md`). It's the only
Leader for now.

## Mail

The `aix` service (the bridge) is separate from `@aix` (this project's
agent; see `decisions.md`). Mail to `@aix` comes in through dot-ai like any
project's.
