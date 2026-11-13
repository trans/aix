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

A project is any directory with a `.ai/` directory in it. aix finds them
as dot-ai does: under the directories in git config's `ai.path`
(`git config --global --add ai.path ~/Projects`), up to 4 levels down,
without following symbolic links or searching hidden directories and
`node_modules/`. So it lists exactly the projects dot-ai's mail reaches,
and follows when `ai.path` changes. Adding or removing a root in aix
changes `ai.path`. Without `ai.path`, aix searches its own `roots`
(`~/.config/aix/config.json`: `roots`, and `depth`, default 1). A project
inside another project sits below it in the tree. Each project is named by its agent's handle (`handle` in
`.ai/config.yml`, else the directory's name), so mail to `@name` and the
tmux window `name` match.

## Running it

| Command | What it does |
|---|---|
| `aix` | The TUI: the projects, starting and stopping agents, switching to one |
| `aix --repl` | A line-based console with the same controls |
| `aix --web` | A web dashboard (`--host`, `--port`; default `127.0.0.1:9292`) |
| `aix --mcp` | The control tools over MCP (stdio), for the lead |
| `aix tell ID` | Ring one agent's bell now, by window name or session id (what dot-ai's carrier runs) |

All modes share one tmux session, `aix`. `F12` detaches, and `F9` jumps
back to the lead's window.

In the TUI, the right side shows the selected project's screen as you move
through the list: live for an agent that's running, and otherwise as it
was when aix last saw it (when you left it, or when it was stopped). The
screens are kept in `~/.local/state/aix/screens/`. Quitting the TUI (`q`)
leaves the agents running in tmux, and `aix` picks them up again; `d`
stops one.

When an agent's harness exits (or fails to start), its window stays,
showing its last screen and a line saying it exited, rather than tmux
moving you to another agent's window. `F12` takes you back to the TUI,
where `Enter` starts it again. With the Resume box ticked, aix resumes the
project's last conversation, or starts a new one if it has none.

To give the lead aix's control tools in Claude Code:

```sh
claude mcp add aix-control -- /path/to/aix --mcp
```

The tools are `list_projects`, `status`, `start`, `stop`, `send`, `peek`,
`focus`, `set_leader`, `get_leader`, `list_roots`, `add_root` and
`refresh`.

## The mail bell

aix starts each agent as `claude` in its own tmux window, and tells it
when mail comes the way you would: it types `You have mail in
.ai/mail/inbox/.` into the agent's pane. The agent then reads the mail
itself. The notice never carries a message's text.

dot-ai's carrier rings the bell itself: when it delivers mail to a project
whose agent aix runs, it runs `aix tell` (below), so nothing of aix's runs
in the background. Typing into a pane is only safe at an empty prompt, so
the bell rings only when all of these hold:

- Claude Code's session file says the session is idle. A busy session is
  told by dot-ai's end-of-turn hook instead. During a startup dialog
  there's no session file, so the bell holds.
- You aren't typing in that pane right now.
- The cursor is in Claude Code's input box, and the box is empty. A draft
  of yours is never touched.

When ringing has to wait, aix flashes a tmux message (`aix: mail for
@name`), and the agent hears at the end of its next turn or when it
starts, from dot-ai's own hooks.

### aix as dot-ai's runner

Under dot-ai's spec (Draft 0.5, "Runners"), aix is the runner of the
sessions it starts, and dot-ai's carrier tells it of their mail:

- Sessions aix starts get `DOT_AI_BY=aix`, so dot-ai's hooks record
  `by=aix` for them.
- Each time aix starts one, it registers itself:
  `~/.local/state/dot-ai/runners/aix` holds its program's absolute path.
- When the carrier delivers mail to such a session's project, it runs
  `aix tell <id>`, which rings the bell once and exits with the spec's
  statuses: 0 told (or will be at the end of its turn); 3 not open (aix
  marks its record `ended`); 4 can't be told now. A session that isn't in
  an aix pane but is still running (one started from inside an aix
  session) gets 4.

This needs dot-ai 0.10.0 or later, in the session sending the mail as well
as the one receiving it.

The fallback is dot-ai's Claude Code channel. With `"mail": {"channel": true}`
in `config.json`, and the dot-ai plugin installed, aix starts Claude Code
with `--dangerously-load-development-channels plugin:dot-ai@dot-ai`
instead. The channel then tells the session, and the bell leaves it
alone. Claude Code warns about that option at every start.

## Building

Requires Crystal 1.19.1 or later and tmux.

```sh
shards install
shards build --release   # bin/aix
crystal spec
```

`just install` builds aix and installs it in `~/.local/bin` (`PREFIX=…`
for elsewhere), and `just uninstall` removes it. An Arch Linux `PKGBUILD`
is in `pkg/`.

## Status

Early, and changing. Work in progress is listed in `TODO.md`. Next:
starting Codex agents (`codex --no-daemon`, so their hooks see
`DOT_AI_BY`).

## License

MIT. See `LICENSE`.
