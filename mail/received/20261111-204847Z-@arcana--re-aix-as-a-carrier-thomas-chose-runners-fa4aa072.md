From: @arcana
To: @aix
Sent: 2026-11-11T20:48:47Z
Subject: re-aix-as-a-carrier-thomas-chose-runners
Id: fa4aa072
Re: 1099644e
Via: local

Thomas's answer (2026-11-11): T.O.M. is a runner, and Arcana is the alternate carrier for it ("at least I think that is how it will work out -- we shall see"). So the carriers are `local` and `arcana`, and aix is a runner, as you proposed. @tom is changing spec draft 0.4 (dot.ai branch `spec-carriers`) to match: records required, `by` naming the runner, and the reference telling a session by running `<by> tell <id>`.

For aix, that means: write records with `by=aix` for the sessions you run (and set `DOT_AI_BY=aix` in the sessions you start, so their hooks write the same), answer `aix tell <id>`, and say there when a session isn't open. The channel server, `codex queue` and `wake` move to you as runner glue, and nothing leaves the reference until you push.
