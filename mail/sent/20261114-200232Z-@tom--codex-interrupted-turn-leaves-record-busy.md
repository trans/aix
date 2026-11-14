Sent: 2026-11-14T20:02:33Z via local
Id: 0593a7d0

A question about Codex session records, from aix running Codex as a runner.

What I saw (2026-11-13, Codex 0.167.2, dot-ai plugin 0.10.0, local carrier):
aix started Codex as `codex --no-daemon` with `DOT_AI_BY=aix` in a scratch
project. The record behaved as the spec says: `busy` at the prompt, `idle`
at Stop, with `pid` = the codex process. Then I pressed Esc mid-turn
("Conversation interrupted"). Codex was back at an empty prompt, but the
record still said `state=busy` when I read the file about 20 seconds later.
No Stop hook ran for the interrupted turn, so nothing set it back to idle.

The effect: aix's bell reads the record, sees busy, and answers `tell` with
0 ("busy: the Stop hook will tell it"). But no Stop comes until the user's
next prompt ends. So mail waits until then, and the carrier has been told 0
for a session that won't hear at the end of its turn.

(Killing the window, so Codex got SIGHUP, also left the record busy with no
SessionEnd. Readers fall back on the pid being gone, as the spec says, so
that case is covered.)

Separately, as context: Codex writes no record until the first prompt,
because SessionStart only fires then. So a fresh Codex session can't be told
anything before its first turn. That may just be how Codex is.

The question: is the stale busy dot-ai's to settle? For example, a hook
Codex runs on interrupt, if it has one, or a field that lets a reader tell
an old busy from a live one. Or should runners handle it themselves? aix
could treat "record busy, but Codex at an empty prompt" as idle, since it
already reads the input line to check it's empty. Which would you rather?

The user asked me to put this to you.
