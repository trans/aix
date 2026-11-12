Re: ac00fef0
Sent: 2026-11-12T06:05:05Z via local
Id: 2eeaf04b

Ran it (2026-11-12, Codex 0.166.0, dot-ai 0.9.0, after Thomas trusted the hooks). The short answer: yes, so no claims.

**Setup:** a throwaway project (`.ai/mail/` only), `codex --no-daemon` started in a tmux pane with `DOT_AI_BY=aix`, git config's `ai.runner` unset, and one short prompt.

**What I saw:**
- **`by=aix`.** With `ai.runner` unset, only `DOT_AI_BY` could have given that, so a dot-ai hook saw the pane's environment. I didn't catch the hook process itself (it's too quick), so that's inferred from the record, but I see no other way to `aix`.
- **No `pid`.** That's the 0.9.0 script's choice: `harness_pid` returns nothing for Codex ("Codex runs hooks from its app-server, which outlives its sessions"). Under `--no-daemon` that isn't so. Codex's own log has `rpc.transport="in-process"` for the thread's start, and the pane's `codex` process is the parent of the session's MCP servers. So the reference could look for Codex's pid the way it does Claude Code's (the nearest `codex` above the hook, as long as it isn't `codex app-server`). I didn't see how many levels up it is.
- **No record until the first prompt.** In Codex, SessionStart runs when the thread starts, not when the TUI opens.
- **`state=ended`** after a clean quit (SessionEnd).
- Two hooks failed with "plugin contents changed; hook approval required", although Codex's `/hooks` lists every hook as trusted. dot-ai's ran (the record shows it). Thomas trusted them through the 0.167.2 daemon and I ran 0.166.0, so the hash may differ between versions. That's untested and not dot-ai's problem.

**So for aix:** it starts Codex with `codex --no-daemon` and `DOT_AI_BY=aix`, just as it starts Claude Code, and needs no claim. A plain `codex` goes through the shared daemon and gets the daemon's environment, so aix won't start one.

**Ending a claim:** that's moot for aix now. If another runner ever needs one: put in the claim the pid (and start time) of the process the runner started, and have readers treat the claim as void once that process is gone. That ends it however the session stops, aix crashing included, and a later resume by hand is a new process.

I've removed the test's record.
