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

**Partly built (2026-11-11):** `aix tell` and `DOT_AI_BY` (items 2 and 3, and the bell for 4). Records are still to do. The contract is spec draft 0.4, merged into
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
5. **The bell is tmux, the channel is the fallback** (user, 2026-11-11).
   Aix types the fixed notice into an idle session's pane, guarded (see
   `decisions.md`, "The mail bell"). dot-ai's Claude Code channel is the
   fallback (`"mail": {"channel": true}` in aix's `config.json`). This reverses the earlier note here
   that keystrokes were only a fallback. **Built, not yet committed**
   (2026-11-11): `Bell`, `MailBell`, `aix tell`, and `DOT_AI_BY=aix` for
   sessions started without the channel.
6. **A wake-up never carries the message** (the user, 2026-11-10, per
   @tom). A push, a keystroke doorbell or a `wake` prompt says only that
   mail is waiting ("You have mail in .ai/mail/inbox/."). Another agent's
   words placed there would borrow the authority of what an agent is
   told directly.

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
sessions. **Told @tom**
(`mail/sent/20261111-212257Z-@tom--does-aix-s-wake-cover-copious-no.md`):
aix never tells, wakes or resumes a `by=tom` session, and sets no
`DOT_AI_BY` when it runs T.O.M. in a pane. **@tom agreed and gave the same
rule from its side**
(`mail/received/20261111-212339Z-@tom--wake-and-copious-and-arcana-s-advice-for-aix-73619b91.md`):
T.O.M. never tells, wakes or resumes a `by=aix` session. It builds its
side once @arcana's script and tests land, and will write when it has.

## Draft 0.5 proposal: no default runner (@tom, 2026-11-12; not agreed yet)

The user spotted that `ai.runner`'s first value, the default runner for
sessions started without `DOT_AI_BY`, can't be right with aix and T.O.M.
both in use. @tom proposes: no default (such a session is `by=dot-ai`); a
runner whose sessions' hooks can't see `DOT_AI_BY` claims the record;
runners register by writing `runners/<name>` (absolute path) beside
`sessions/`; `ai.runner` goes. Asked
(`mail/received/20261112-025057Z-@tom--runners-without-a-global-default-your-view-0f8f443f.md`),
answered (`mail/sent/20261112-025550Z-@tom--runners-without-a-default-aix-s-view.md`):

- **Codex's daemon** (tested 2026-11-12, Codex 0.166.0): a plain `codex`
  uses one shared app-server daemon, so hooks get the daemon's
  environment. `codex --no-daemon` runs the app server in the TUI's own
  process (its MCP servers are the TUI's children; Codex's log says
  `rpc.transport="in-process"`). **Tested after the user trusted the
  hooks (2026-11-12): its hooks see `DOT_AI_BY`.** The record got
  `by=aix` with `ai.runner` unset. It had no `pid` (0.9.0 gives Codex
  none), appeared only at the first prompt, and was `ended` after a clean
  quit. Rerun on Codex 0.167.2 after the user upgraded and trusted the
  hooks again: the same, and no hook failed (on 0.166.0 two had failed
  with "plugin contents changed; hook approval required", trusted through
  the 0.167.2 daemon). So aix starts Codex as `codex --no-daemon` with `DOT_AI_BY=aix`,
  and no claims are needed. Sent:
  `mail/sent/20261112-060504Z-@tom--codex-test-hooks-see-dot-ai-by-under-no-daemon.md`.
- **Registration** suits aix, and the absolute path fixes the old
  `/usr/bin/aix` (no `tell`) being first on PATH.
- **Misses raised:** the hook rewrites `by` at every SessionStart,
  including `/clear` and compaction, and a claim races the hook's rewrite.
  Suggested: a claim in its own file beside the record, which hooks never
  write. And `DOT_AI_BY=aix` is inherited by sessions an aix session
  starts (`claude -p`), so `aix tell` must answer 4, not 3, for a live
  session that isn't in a pane.

**Where it stands (@tom, 2026-11-12,
`mail/received/20261112-044320Z-@tom--runners-where-it-stands-ac00fef0.md`):**
@tom, @arcana and aix agree on no default runner and on registering under
`runners/` (mode 700; one line, an absolute path, written under a hidden
name and renamed into place; run only if absolute and executable; skipped,
not failed, otherwise). Draft 0.5 takes aix's line: a runner asked about a
session it can't push to, but that's still running, answers 4. If claims
had been needed, the user chose aix's claim file.

## Open

- The bus bridge: for mail, `aix tell` replaces its keystroke nudge on
  Arcana's `message.sent`. What's left for the bridge is bus traffic
  that isn't mail. Whether that still needs the `sys.message.sent` push
  (`TODO.md`, `coordination.md`) is undecided.
- **What `wake` looks like.** One input is "turns on demand", an idea of
  the user's that's **being weighed, not decided** (via @arcana and @tom,
  2026-11-11). When there's work for a project, resume its saved session
  headless, or fork it:
  - fork or skip a session that's open or busy;
  - allow a headless turn's tools up front, and send what needs the user
    back as a held draft;
  - make the prompt only "process your inbox", and send the request
    itself as mail;
  - a resumed turn sends the whole session again, so long sessions cost
    more;
  - give parallel turns that change code a git worktree each.
- `TODO.md` in the code repo doesn't list this work yet.
