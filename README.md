# aix

aix is a tmux-based manager for AI coding harnesses. Each project's agent
runs as a full harness (Claude Code today) in its own tmux window.

You can work with the agents in two ways:

- **Through the lead.** aix has its own master session, the lead. You tell
  it what you want ("tell @yaml2 to ...", "stop @imm, is it going to
  OOM?") and it coordinates the other agents using aix's control tools.
- **Directly.** Jump into any agent's window and talk to it yourself.

What sets aix apart from other tmux agent managers is how agents talk to
each other. Others type messages into each other's panes. In aix, agents
send each other mail, using the [dot-ai](https://github.com/trans/dot-ai)
`.ai/` convention: messages have a sender, an id and replies, and are kept
in git. aix only rings the doorbell, telling an idle agent that mail is
waiting.

## How it finds projects

A project is any directory with a `.ai/` directory in it. aix scans the
root directories you give it (`~/.config/aix/config.json`: `roots`, and
`depth`, default 1). A project inside another project sits below it in the
tree. Each project is named by its agent's handle (`handle` in
`.ai/config.yml`, else the directory's name), so mail to `@name` and the
tmux window `name` match.

## Running it

| Command | What it does |
|---|---|
| `aix` | The TUI: the projects, starting and stopping agents, switching to one |
| `aix --repl` | A line-based console with the same controls |
| `aix --web` | A web dashboard (`--host`, `--port`; default `127.0.0.1:9292`) |
| `aix --mcp` | The control tools over MCP (stdio), for the lead |
| `aix --bridge` | The bus bridge: wakes agents on Arcana bus messages |

All modes share one tmux session, `aix`. `F12` detaches, and `F9` jumps
back to the lead's window.

To give the lead aix's control tools in Claude Code:

```sh
claude mcp add aix-control -- /path/to/aix --mcp
```

The tools are `list_projects`, `status`, `start`, `stop`, `send`, `peek`,
`focus`, `set_leader`, `get_leader`, `list_roots`, `add_root` and
`refresh`.

## Building

Requires Crystal 1.19.1 or later and tmux.

```sh
shards install
shards build --release   # bin/aix
```

An Arch Linux `PKGBUILD` is in `pkg/`.

## Status

Early, and changing. Work in progress is listed in `TODO.md`. The next step
is making aix the **runner** for the sessions it starts, under dot-ai's
spec. It will keep a session record for each one and answer
`aix tell <id>`, so it can push "you have mail" into an idle session
(Claude Code's channels, `codex queue`) instead of typing into it.

## License

MIT. See `LICENSE`.
