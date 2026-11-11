# Aix as the mail carrier

*Updated 2026-11-11*

## Decided (user, 2026-11-11)

Aix becomes a dot-ai mail **carrier**, a third value for `git config
ai.carrier` (`aix`) beside `local` and `arcana`. Mail between projects on
a machine that runs Aix goes through Aix. It's optional: without Aix, mail
still works.

dot-ai stays a standard, with two pieces of code:

- **The agent-facing commands** (`dot-ai mail send`, `draft`, `done`,
  `check`). They write only into the project's own `.ai/mail/` and hand
  the carrier's work to whichever carrier the machine has. Agents don't
  change and never need to know Aix exists.
- **`local`, a simple carrier that mainly serves as a reference.** It
  works where neither Aix nor Arcana runs, and it's what the spec is
  tested against.

We considered moving the carrier into Aix and leaving dot-ai as a spec
with no code, and rejected it. Mail would then need Aix (a Crystal binary
plus tmux) on every machine, so it would no longer be optional.

## @arcana's answer (2026-11-11): runners, not `ai.carrier aix`

**Waiting for the user to choose.** @arcana now thinks the runner model is
better than `ai.carrier aix`, which it had backed earlier
(`mail/received/20261111-204242Z-@arcana--re-aix-as-a-carrier-my-view-on-2-and-4-0d4ca962.md`):

- **Carrier vs runners:** the carrier moves files, one per user. Runners
  tell sessions, and several can run side by side (aix and T.O.M.). The
  general hand-off and the `--self` flag are no longer needed.
- **Who tells, settled between us:** the harness's hooks keep the
  start/Stop notices in every session. The session's manager (aix,
  T.O.M.'s fleet) only pushes while the session is idle.
- **Arcana's three conditions for the runner model:**
  1. A record names its runner by a plain name and an id. The reference
     tells a session by running `<runner> tell <id>`, never a command
     line read from a file.
  2. Checking that a session is still open is the runner's job. If
     `tell` says the session isn't open, the reference tries the next
     newest record and the runner marks that one `ended`. For its own
     panes, aix answers this.
  3. Records become required, so their format goes into the spec as part
     of mail. T.O.M. writes records as runner `tom`. A session no runner
     can push to (Claude Code without a channel) gets a record saying so,
     and is told at its next start or Stop.
- **What then moves to aix:** the channel server, `codex queue` and
  `wake`. The reference's own telling shrinks to the one `tell` call.
- **Timing:** @tom is drafting the spec round with `ai.carrier aix` in
  it. Arcana will tell the user that the hand-off and `--self` drop out
  if the user picks the runner model.

## Conferring with @arcana (2026-11-11)

The user asked for this before deciding: Arcana's ideas differ a little
from these. Arcana's side is in its `.ai/memory/mail-push.md` and its mail
to @tom (`aca49f26`, `7e24f6b1`). Our message is
`mail/sent/20261111-204132Z-@arcana--aix-as-a-carrier-where-we-differ.md`.
In short:

- **Arcana's conditions:** aix runs the reference's delivery
  (`dot-ai mail deliver --self`) and adds only the telling; and aix must
  push before the reference stops pushing. Aix's agent agrees with both.
  The user hasn't ruled.
- **Who tells:** Arcana agrees with @tom that telling belongs to whoever
  runs the session. We asked whether that covers the start/Stop notices
  too, or only the push to an idle session.
- **Raised by aix, for the user:** since the reference delivers and the
  runner tells, aix might not need to be a carrier at all. The carrier
  would stay `local`, aix and T.O.M. would be runners, and the shared
  session records would say how to tell each session.
- **@tom leads the standard.** Spec changes (the carrier list, what every
  carrier must do, the session records) are drafted by @tom.

## How carriers already stay out of each other's way

From the spec's "The carrier" section (`spec/mail.md` in the dot.ai repo):

- Each machine has one carrier. The others stay out of mail.
- Every carrier keeps the same files under the same directory locks
  (`outbox/.delivering`, `.receipts`, topic `.posting`). Two carriers
  running at once by mistake wait on each other rather than send a
  message twice.
- dot-ai hands work to the carrier in `hand_off()` (`scripts/dot-ai`).
  Aix needs an `aix)` case there, beside `arcana)`, which runs
  `aix mail CMD ...`.

## Open

- **Split noticing from waking.** The spec makes the carrier responsible
  for noticing (`spec/mail.md`, "Noticing mail"): telling the agent at
  session start and before a turn ends. Proposal: noticing stays with
  dot-ai's hooks whatever the carrier is, since it only reads local
  files. *Waking* an idle pane is Aix's job, because only Aix can do it.
  This also settles the TODO about not nudging a busy session: mail that
  arrives mid-turn is caught by the Stop hook, so Aix only wakes idle
  panes. It needs a change to the spec.
  - Today, with `ai.carrier` unset, dot-ai mail never touches the bus,
    so Aix's bridge can't see it. dot-ai's channel, which wakes an idle
    Claude Code session, is the only thing that does. Under `aix` it goes
    quiet: it's gated on `local` in `cmd_channel`. So Aix must wake every
    pane it owns.
- **Mail to other machines.** Aix reaches only this machine's disk.
  Proposal: Aix stays the machine's only carrier and passes addresses it
  can't find to Arcana for delivery elsewhere. Today Arcana refuses to
  send mail when it isn't the carrier, so this needs an agreement with
  @arcana.
- **The Arcana firehose.** As carrier, Aix knows each recipient when it
  delivers, so mail needs no `sys.message.sent` push. The bridge then
  needs the bus only for traffic that isn't mail (see `coordination.md`).
- **The carrier contract Aix implements:** delivery, with the
  `delivered:` / `left in the outbox:` lines; topics, numbering and
  `following`; receipts; and the procedure for changing carriers. The
  spec defines all of these; nothing is built yet.
