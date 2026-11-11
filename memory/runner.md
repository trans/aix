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

**Open, nothing built yet.** The contract is spec draft 0.4, merged into
dot.ai's `main` as `5750a1a` (not pushed as of 2026-11-11), in
`spec/mail.md`, "Runners" and "Session records". @arcana is changing the
reference script, the tests and Arcana to match.

- **The reference doesn't push.** `dot-ai tell` always exits 4 (or 3). The
  user moved the push to aix ("we can move the push stuff to aix"). It
  keeps pushing today, and nothing leaves it until aix pushes (@arcana's
  condition), so aix's push is on the critical path.
- **`ai.runner`** (the person's git config, one value per runner) lists
  the runners the carrier is allowed to call. The first one is the default
  for sessions started without `DOT_AI_BY`, such as Codex's, whose hooks
  no launcher reaches. Aix has to be in that list.

1. **Session records** for every session aix runs, with `by=aix`. They live
   in `$XDG_STATE_HOME/dot-ai/sessions/<key>.session`, one `field=value`
   per line: `root`, `agent`, `id`, `by`, `pid`, and `state`
   (`idle`/`busy`/`ended`). Each is written under a hidden name, then
   renamed into place.
2. **`DOT_AI_BY=aix`** in the environment of every session aix starts.
   The session's hooks then write `by=aix` and leave pushing, waking and
   resuming to aix.
3. **`aix tell <id>`**, which exits with one of these:
   - 0: the session was told, or will be at the end of its turn.
   - 3: the session isn't open, and aix has marked its record `ended`.
     The carrier then tries the project's next-newest session.
   - 4: aix can't push to the session. It hears at its next start or
     Stop.
   Checking that a session is still open is the runner's job; for its
   own panes, aix knows.
4. **The glue moves to aix:** the channel server (Claude Code), `codex
   queue` (Codex) and `wake`. Nothing leaves the reference until aix
   pushes.
5. **Keystrokes only as a fallback,** for a harness with no push path.
   Never into a pane waiting on a prompt, where keys could answer it.

## T.O.M.'s sessions are T.O.M.'s (user, 2026-11-11)

T.O.M. starts its sessions and controls them completely. They're Copious
sessions; it allows Claude Code sessions too, but only for now, while
Copious is unfinished. Copious reads its own project's `.ai/`, so its
sessions need neither hooks nor aix. T.O.M. starts the Claude Code
sessions it runs with `DOT_AI_BY=tom`.

Aix and T.O.M. touch in only two places, and the session records cover
both. A project with a session open in each world is told once, through
its newest session. T.O.M.'s fleet doesn't resume a session that's open
in an aix pane: it forks it or skips it.

T.O.M.'s notes leave one question for aix: whether `wake` covers Copious.
From the user's point above, the answer is no: T.O.M. wakes its own
sessions. **Told @tom** (`mail/sent/20261111-212257Z-@tom--does-aix-s-wake-cover-copious-no.md`): aix never tells, wakes or resumes a `by=tom` session, and sets no `DOT_AI_BY` when it runs T.O.M. in a pane.

## Open

- The bus bridge: for mail, `aix tell` replaces its keystroke nudge on
  Arcana's `message.sent`. What's left for the bridge is bus traffic
  that isn't mail. Whether that still needs the `sys.message.sent` push
  (`TODO.md`, `coordination.md`) is undecided.
- `TODO.md` in the code repo doesn't list this work yet.
