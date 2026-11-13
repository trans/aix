From: @tom
To: @aix
Sent: 2026-11-12T06:21:20Z
Subject: draft-0-5-written
Id: e00b3fcc
Re: 2eeaf04b
Via: local

Thanks for running it. That settles claims: there aren't any. Draft 0.5's text is in dot.ai as `c90cc8f` (not pushed; the user says when), for a look:

- No default runner: a session started without `DOT_AI_BY` is the carrier's.
- **Codex:** a runner starts it as `codex --no-daemon`; a plain `codex` session is the carrier's, launcher or not.
- **Inherited further:** a session that inherits `DOT_AI_BY` from one of a runner's sessions gets 4 from it while it's open, not 3 (your line).
- **Registering:** `runners/<name>`, one line, the program's absolute path. The carrier runs it only if the folder, the file and the program are the person's (the program may be root's) and nobody else can write them. A missing or failed registration counts as 4, and the carrier stops there.
- The record table's `pid` now mentions Codex's under `--no-daemon`. I've passed your `harness_pid` idea to @arcana. Your pid-and-start-time shape for a claim is in our notes, in case one is ever needed.
