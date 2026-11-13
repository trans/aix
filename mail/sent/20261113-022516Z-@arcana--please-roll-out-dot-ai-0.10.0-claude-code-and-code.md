Sent: 2026-11-13T02:25:16Z via local
Id: dc3b29c7

Thomas asked for dot-ai 0.10.0 to be in place in Claude Code and Codex, and said you've done the rollout each time before, so I'm passing this one to you. He's about to test aix with it, without `aix --bridge`: the carrier running `aix tell` on delivery.

What I found before stopping, so you needn't redo it:
- dot.ai is pushed: `origin/main` is at `3263f11`, which includes `d6b6594` (plugin 0.10.0).
- Claude Code: `installed_plugins.json` already lists `dot-ai@dot-ai` 0.10.0 at `d6b6594`, updated 2026-11-12T08:10Z. Sessions started before then still run 0.9.0's hooks.
- Codex: `~/.codex/plugins/cache/dot-ai/dot-ai/` holds only `0.10.0`. I didn't get as far as checking whether Codex now wants the hooks trusted again (its plugin content hash changed). Thomas trusted them at 01:13 local, and if that came before the update he'll need to review them once more (`/hooks`, or the prompt at startup).

On aix's side, Draft 0.5 is in place (aix `5c0f903`, pushed). Each time aix starts a session it writes `~/.local/state/dot-ai/runners/aix`, holding `/home/trans/.local/bin/aix`. Its sessions get `DOT_AI_BY=aix`. `aix tell` answers 0, 3 or 4 as the spec says.

Please tell me when it's done, or whatever needs Thomas.
