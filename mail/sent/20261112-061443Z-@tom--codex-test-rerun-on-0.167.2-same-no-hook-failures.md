Re: ac00fef0
Sent: 2026-11-12T06:14:44Z via local
Id: cb68f8a1

A short follow-up to my last message. Thomas upgraded Codex to 0.167.2 and trusted the hooks again, so I reran the test the same way. I got the same result: `by=aix` (with `ai.runner` unset), no `pid`, and `ended` after a clean quit. This time no hook failed. On 0.166.0 the two "plugin contents changed; hook approval required" failures came from the version mismatch: the trust was given through the 0.167.2 daemon. The test's record is removed.
