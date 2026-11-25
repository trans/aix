# aix

aix is a tmux-based manager for AI coding harnesses. Each project's agent
runs as a full harness, Claude Code or Codex, in its own tmux window.

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
| `aix --web` | The web page (`--host`, `--port`; default `127.0.0.1:9292`), below |
| `aix --mcp` | The control tools over MCP (stdio), for the lead |
| `aix tell ID` | Ring one agent's bell now, by window name or session id (what dot-ai's carrier runs) |
| `aix --version` | aix's version (`--help` lists the options; aix refuses one it doesn't know) |

All modes share one tmux session, `aix`. `F12` detaches, and `F9` jumps
back to the lead's window. aix sets that session's status line to say
which agent you're in, with the title its harness gives the conversation
(Claude Code's starts with `✳` while it waits for you, and a spinner
while it works), and on the right those keys and the time (`aix · @name ·
✳ title … F12: back to aix · F8: files · F9: @lead 08:07 16-Nov-26`).
tmux's numbered window list is left out, since the TUI is
where to switch.

Scrolling up with the mouse wheel, or dragging to select text, puts a
pane in tmux's copy mode, where the cursor moves freely over the pane.
In the aix session, typing leaves it: a letter, digit, punctuation,
Space, Backspace or Enter goes to the agent as usual. Arrows, Page
Up/Down, Ctrl-keys and the mouse still scroll and select, and Esc leaves
without typing. The status line says `copy mode: type or Esc to leave`
meanwhile. In your other tmux sessions copy mode's keys are as they were
(with tmux's vi keys, `mode-keys vi`, aix leaves copy mode alone). The status line is the aix session's alone, and your
scrollback (`history-limit`) is your own. `F12` and `F9` are tmux key
bindings, though, so they work in any session on the same tmux server.

### The file pane

`F8` in an agent's window opens a file browser ([yazi](https://yazi-rs.github.io))
on the right half, in the project's directory, for getting to the files
an agent mentions when its links don't open. `F8` again closes it (so
does `q` in yazi), and the status line says which `F8` will do. To move
between the agent and its files with the pane open, click the one you
want, or press `Ctrl-b o`.

Each agent's window has its own file pane, so switching agents switches
browsers, and each agent keeps its browsing directory: yazi saves where
it was when it closes (`~/.local/state/aix/browse/`), and the next file
pane there starts from it. yazi opens files with your desktop's default
application. In other tmux sessions, `F8` goes to the program as usual.

The file pane's yazi reads aix's own settings,
`~/.config/aix/yazi/yazi.toml`, which aix writes once and leaves for you
to change: two columns, the current directory and a preview of the
selected file, without the parent directory's column yazi shows by
default. Your yazi elsewhere keeps `~/.config/yazi`.

An agent's pane is marked (`@aix-agent`), so aix finds it however the
window is arranged. A pane you add to an agent's window (`Ctrl-b *`, a
split) is an ordinary tmux pane, and closes when its shell exits.

In the TUI, `Enter` goes to the selected project's agent, starting it if
it isn't running: in its last conversation, or a new one if it has none
(for Codex, `codex resume --last`, which does that itself). `n` starts it
in a new conversation instead. The web dashboard's Start and New buttons,
and the lead's `start` tool, do the same.

The right side shows the selected project's screen as you move
through the list: live for an agent that's running, and otherwise as it
was when aix last saw it (when you left it, or when it was stopped). The
screens are kept in `~/.local/state/aix/screens/`. The list and its marks
are as they were when it was drawn; `r` looks again (the projects, which
agents run, which are open elsewhere, and the screen). Quitting the TUI
(`q`) leaves the agents running in tmux, and `aix` picks them up again;
`d` stops one.

Each project runs Claude Code, or Codex if it has an `AGENTS.md` and no
`CLAUDE.md`. `h` switches the selected project between the two, from its
next start, and aix remembers the choice (`harness` in
`~/.config/aix/config.json`, by directory).

When an agent's harness exits (or fails to start), its window stays,
showing its last screen and a line saying it exited, rather than tmux
moving you to another agent's window. `F12` takes you back to the TUI,
where `Enter` starts it again.

### In kitty, instead of tmux

aix can run each agent in a tab of [kitty](https://sw.kovidgoyal.net/kitty/)
instead of a tmux window, with the tabs listed down the side. Each agent
runs in an [abduco](https://github.com/martanne/abduco) session, which
keeps it going when its tab closes or kitty quits, the way tmux kept it
before. abduco draws nothing of its own, so there's no status line or copy
mode in the way, and kitty's own scrollback and selection work as usual.
It needs kitty 0.48 or later (for tabs on the side), abduco, and in
`~/.config/kitty/kitty.conf`:

```
allow_remote_control socket-only
listen_on unix:${XDG_RUNTIME_DIR}/kitty
tab_bar_edge left
tab_title_max_lines 2
```

Remote control lets aix open, label, read and type into tabs, over a
socket only you can use. Then, in `~/.config/aix/config.json`,
`"terminal": "kitty"`, and run `aix` in a kitty tab. `Enter` starts the
selected agent in a new tab, or brings its tab to the front, and aix
stays in its own tab. Each agent's tab is labelled with its handle above
the title its harness gives it (a small watcher aix writes,
`~/.config/aix/kitty/aix_watcher.py`). Close an agent's tab and the agent
goes on (its mark stays `●`); `Enter` opens a tab on it again, and has it
redraw its screen. `d` stops it. When an agent exits, its tab stays with
its last screen and a shell.

The mail bell works the same way, reading and typing through kitty, with
two differences: kitty doesn't say when you last pressed a key, so the
bell goes by the empty input box alone, and an agent with no tab open
isn't rung (there's no screen to check), so it hears at its next turn's
end. The file pane (`F8`) is tmux's alone for now.

### The web page

`aix --web` serves a page with three columns: the agents on the left,
with the TUI's marks and each running agent's title; the selected
agent's conversation in the middle; and its project's files on the
right, where a file opens in the middle (markdown rendered). The
conversation is read from the transcript Claude Code keeps
(`~/.claude/projects/`), so it shows the messages' own markdown rather
than the screen they were drawn on, and it follows the transcript as the
agent works. Tool calls fold away under a line saying what each does.
Codex conversations aren't shown yet. Start, New and Stop work as in the
TUI; Terminal opens the first dashboard's view of the agent's screen
(also at `/classic`), until the page has a terminal of its own.

Under the conversation is a box to write to the agent. Ctrl+Enter or
Send sends what's in it as one message, line breaks and all (pasted, as
a terminal pastes, then Enter), but only when the agent's input box is
empty: into a menu, a permission prompt or a half-written draft, the
text would do harm. Then the box shows the bottom of the agent's screen
and a row of keys (1–4, arrows, Enter, Esc, Tab), and what you write is
typed as keys, without Enter: pick an answer with its number or the
arrows, or type your own answer and press Enter.

The page can type into agents, so it's guarded. aix prints its address
when it starts, with a secret in it (`http://127.0.0.1:9292/?token=…`).
Opening that sets a cookie and moves on to the address without it; the
secret is kept in `~/.local/state/aix/web-token`, readable only by you,
so the address stays the same from start to start. Requests without the
cookie, from another site (`Origin`), or by another name for the address
(`Host`, which stops DNS rebinding) are refused, and the page runs no
script but its own.

### Open elsewhere

A project can also be open outside aix: in VS Code, the Codex app, or a
terminal. The list marks such a project `◐` (`●` is running in aix, `○`
not started), and its panel says where: "Also open: Codex in Codex's
shared app server (pid …)". aix won't resume a conversation another
program holds, following dot-ai's rule that only a session's runner
resumes it. `Enter` says where the conversation is open instead, and you
can close it there, or press `n` for a new one beside it.

aix sees Claude Code's sessions from the file Claude Code keeps for each
running one (`~/.claude/sessions/`), and Codex's from the lock Codex
holds on each open conversation (`~/.codex/thread-writer-locks/`, with the
holder from `/proc/locks`). Codex has no way of saying which conversation
`resume --last` will take, so for Codex any of the project's conversations
open elsewhere stops a resume. Codex refuses one that's locked anyway
("This conversation is open in another app"); Claude Code has no such
lock, which makes aix's check the only guard there.

To give the lead aix's control tools in Claude Code:

```sh
claude mcp add aix-control -- /path/to/aix --mcp
```

The tools are `list_projects`, `status`, `start`, `stop`, `send`, `peek`,
`focus`, `set_leader`, `get_leader`, `list_roots`, `add_root` and
`refresh`. `start` resumes the project's last conversation, as `Enter`
does, unless it's open elsewhere; `resume: false` starts a new one, for a
task that doesn't need what came before. It takes a `harness` (`claude` or
`codex`) to run a project in the other one. `status` and `list_projects`
list each project's conversations open elsewhere (`open_elsewhere`).

## The mail bell

aix starts each agent in its own tmux window, and tells it when mail
comes the way you would: it types `You have mail in .ai/mail/inbox/.`
into the agent's pane. The agent then reads the mail itself. The notice
never carries a message's text.

dot-ai's carrier rings the bell itself: when it delivers mail to a project
whose agent aix runs, it runs `aix tell` (below), so nothing of aix's runs
in the background. Typing into a pane is only safe at an empty prompt, so
the bell rings only when all of these hold:

- The session is idle: Claude Code's session file says so, or for Codex,
  dot-ai's record of the session. A busy session is told by dot-ai's
  end-of-turn hook instead. During Claude Code's startup dialogs there's
  no session file, and Codex's hooks write no record until its first
  prompt, so until then the bell holds.
- You aren't typing in that pane right now. A pane left scrolled back
  (in copy mode) is taken out of it first, as Esc would, since the
  notice would otherwise go to copy mode and never reach the agent.
- The cursor is in the input box, and the box is empty (Codex's grey
  placeholder counts as empty). A draft of yours is never touched.

When ringing has to wait, aix flashes a tmux message (`aix: mail for
@name`), and the agent hears at the end of its next turn or when it
starts, from dot-ai's own hooks.

### aix as dot-ai's runner

Under dot-ai's spec (Draft 0.5, "Runners"), aix is the runner of the
sessions it starts, and dot-ai's carrier tells it of their mail:

- Sessions aix starts get `DOT_AI_BY=aix`, so dot-ai's hooks record
  `by=aix` for them. Codex runs as `codex --no-daemon`, its app server in
  its own process, since only then do its hooks see that variable.
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

Requires Crystal 1.19.1 or later and tmux (or kitty and abduco, above),
and yazi for the file pane.

```sh
shards install
shards build --release   # bin/aix
crystal spec
```

`just install` builds aix and installs it in `~/.local/bin` (`PREFIX=…`
for elsewhere), and `just uninstall` removes it. An Arch Linux `PKGBUILD`
is in `pkg/`.

## Status

Early, and changing. Work in progress is listed in `TODO.md`.

## License

MIT. See `LICENSE`.
