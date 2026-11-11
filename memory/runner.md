# Aix as a runner

*Updated 2026-11-11*

## Decided (user, 2026-11-11, passed on by @arcana)

Aix is a **runner**, not a mail carrier. So is T.O.M. The carriers are
`local` (dot-ai's reference carrier) and `arcana` (the alternative, which
T.O.M. is expected to use). The user said it may still change as the work
goes on.

- **The carrier** moves and files mail, one per user.
- **A runner** tells the sessions it runs about their mail, and several
  runners can work side by side.
- **Inside every session**, the harness's hooks keep the notices at
  session start and at Stop.
- **The runner** pushes a notice only to a session that's idle.

The path here: earlier the same day the user chose `ai.carrier aix`. Aix's
agent then raised the runner model, @arcana preferred it, and the user
picked it. The record:
`mail/sent/20261111-204132Z-@arcana--aix-as-a-carrier-where-we-differ.md`,
`mail/received/20261111-204242Z-@arcana--re-aix-as-a-carrier-my-view-on-2-and-4-0d4ca962.md`,
`mail/received/20261111-204847Z-@arcana--re-aix-as-a-carrier-thomas-chose-runners-fa4aa072.md`.

## What aix has to build

**Open, nothing built yet.** The sources are @arcana's message `fa4aa072`
and @tom's spec draft 0.4 (dot.ai branch `spec-carriers`, `641fa32`:
`spec/mail.md`, "One runner per session" and "Session records"). @tom is
revising the draft: records become required, and the reference tells a
session by running `<by> tell <id>`. Check the final text before building.

1. **Session records** for every session aix runs, with `by=aix`. They live
   in `$XDG_STATE_HOME/dot-ai/sessions/<key>.session`, one `field=value`
   per line: `root`, `agent`, `id`, `by`, `pid`, and `state`
   (`idle`/`busy`/`ended`). Each is written under a hidden name, then
   renamed into place.
2. **`DOT_AI_BY=aix`** in the environment of every session aix starts.
   The session's hooks then write `by=aix` and leave pushing, waking and
   resuming to aix.
3. **`aix tell <id>`:** push the notice into the session while it's idle.
   If the session isn't open, say so and mark its record `ended`. The
   reference then tries the project's next-newest record. Checking that a
   session is open is the runner's job; for its own panes, aix knows.
4. **The glue moves to aix:** the channel server (Claude Code), `codex
   queue` (Codex) and `wake`. Nothing leaves the reference until aix
   pushes.
5. **Keystrokes only as a fallback,** for a harness with no push path.
   Never into a pane waiting on a prompt, where keys could answer it.

## Open

- The exact `tell` contract (its output and exit status for "not open"),
  once @tom's revision lands.
- The bus bridge: for mail, `aix tell` replaces its keystroke nudge on
  Arcana's `message.sent`. What's left for the bridge is bus traffic
  that isn't mail. Whether that still needs the `sys.message.sent` push
  (`TODO.md`, `coordination.md`) is undecided.
- `TODO.md` in the code repo doesn't list this work yet.
