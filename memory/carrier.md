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
