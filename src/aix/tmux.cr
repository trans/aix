module Aix
  # Thin wrapper around tmux CLI commands.
  module Tmux
    SESSION = "aix"

    # The session, as a tmux target: exactly it (`=`, where bare `aix`
    # would match a session `aixtest` when there's no `aix`), and as a
    # session (`:`, where bare `aix` would be taken first for a window
    # named `aix`, this project's). A window in it is `TARGET` + `=name`.
    TARGET = "=#{SESSION}:"
    PLACEHOLDER_WINDOW = "__aix_placeholder__"

    # A user option on the pane an agent runs in, so aix finds it however
    # the window's panes are arranged: a pane added above it (`split-window
    # -b`, `new-pane`) comes first.
    AGENT_MARK = "@aix-agent"

    # A session option naming the lead's window, for the status line.
    LEAD_OPTION = "@aix-lead"

    # A user option on an agent window's file pane (`Files`), and the key
    # that opens it.
    FILES_MARK   = "@aix-files"
    FILES_CLIENT = "@aix-files-client"
    FILES_KEY    = "F8"

    # Ensure the aix tmux session exists, creating it if not (with a
    # placeholder window that new_window replaces), and set it up.
    def self.ensure_session
      unless session_exists?
        # Start tmux server with clean env (no Claude nesting vars)
        result = Process.run("env", ["-u", "CLAUDECODE", "-u", "CLAUDE_CODE_ENTRYPOINT",
                                     "tmux", "new-session", "-d", "-s", SESSION,
                                     "-n", PLACEHOLDER_WINDOW,
                                     "-x", "#{cols}", "-y", "#{rows}"],
          error: Process::Redirect::Pipe)
        raise "tmux new-session: failed" unless result.success?
      end
      configure_session
    end

    # The aix session's own settings, set each time, so a session made by
    # an older aix gets them too. Only the aix session's: the person's
    # other tmux sessions are left alone.
    def self.configure_session
      # Bind F12 to detach (prefix-free)
      run("bind-key", "-n", "F12", "detach-client")
      run("set-option", "-t", TARGET, "mouse", "on")
      # Scrollback is the person's own (`history-limit` in their tmux.conf).
      Process.run("tmux", ["set-option", "-u", "-t", TARGET, "history-limit"], error: Process::Redirect::Close)
      # A pane closes when its program exits, but for an agent's (`new_window`).
      run("set-option", "-t", TARGET, "remain-on-exit", "off")
      bind_files_key
      bind_typing_in_copy_mode
      status_line
      mark_agent_panes
    end

    # The keys that, typed in copy mode in the aix session, leave it and go
    # to the program: the printable characters, Space, Backspace and Enter.
    # Arrows, Page Up and Down, Ctrl-keys and the mouse keep scrolling and
    # selecting, and Esc leaves without typing.
    TYPING_KEYS = (33..126).map(&.chr.to_s) + ["Space", "BSpace", "Enter"]

    # A server option saying copy mode's keys are bound as below, and how
    # (COPY_TYPING_VERSION), so they're bound once per tmux server.
    COPY_TYPING_MARK    = "@aix-copy-typing"
    COPY_TYPING_VERSION = "1"

    # Make typing in copy mode reach the program, in the aix session (the
    # user, 2026-11-24: scrolling back with the mouse wheel, or dragging,
    # puts a pane in copy mode, where keys did nothing until Esc). A key
    # binding holds for the whole tmux server, so each key keeps its own
    # meaning in the person's other sessions. Only copy mode's emacs keys
    # (tmux's default): with `mode-keys vi`, letters are how one moves.
    private def self.bind_typing_in_copy_mode
      mark = capture("show-options", "-sqv", COPY_TYPING_MARK).strip rescue ""
      return if mark == COPY_TYPING_VERSION
      config = copy_typing_config(copy_mode_bindings)
      path = File.tempname("aix-copy-typing", ".conf")
      File.write(path, config)
      begin
        run("source-file", path)
      ensure
        File.delete?(path)
      end
      run("set-option", "-s", COPY_TYPING_MARK, COPY_TYPING_VERSION)
    rescue
      # Copy mode stays as tmux has it.
    end

    # Copy mode's key bindings (emacs keys): each key's command.
    def self.copy_mode_bindings : Hash(String, String)
      capture("list-keys", "-T", "copy-mode", "-F", "\#{key_string}\t\#{key_command}").lines.compact_map do |line|
        key, _, command = line.partition('\t')
        {key, command.strip} unless key.empty?
      end.to_h
    rescue
      {} of String => String
    end

    # The tmux configuration binding TYPING_KEYS in copy mode: in the aix
    # session, leave copy mode and type the key; elsewhere, what the key
    # did before (`bindings`), if anything. A key already bound by aix is
    # left as it is.
    def self.copy_typing_config(bindings : Hash(String, String)) : String
      condition = "\#{==:\#{session_name},#{SESSION}}"
      TYPING_KEYS.compact_map do |key|
        before = bindings[key]?
        next if before.try(&.includes?(condition))
        quoted = key == "'" ? %("'") : "'#{key}'"
        typed = key.size == 1 ? "send-keys -l #{quoted}" : "send-keys #{quoted}"
        otherwise = before ? " { #{before} }" : ""
        "bind-key -T copy-mode #{quoted} if-shell -F '#{condition}' { send-keys -X cancel ; #{typed} }#{otherwise}"
      end.join("\n") + "\n"
    end

    # Bind FILES_KEY to `aix files <window>` (`Files.toggle`), in the aix
    # session; anywhere else the key goes to the program as usual, since
    # a binding holds for the whole tmux server. Only a program named
    # `aix` binds it: aix's code run some other way (`crystal eval`, a
    # spec) isn't one to run later.
    private def self.bind_files_key
      program = Process.executable_path || return
      return unless File.basename(program) == "aix"
      run("bind-key", "-n", FILES_KEY, "if-shell", "-F", "\#{==:\#{session_name},#{SESSION}}",
        "run-shell -b \"'#{program}' files '\#{window_id}'\"", "send-keys #{FILES_KEY}")
    end

    # The status line: which agent this is and the title its harness gives
    # its pane (what the conversation is about, and whether it's working),
    # then the keys and the time (the user's layout, 2026-11-17). The title
    # is the agent pane's, whichever pane is in front, and left out while
    # it's tmux's default, the machine's name. tmux's numbered list of
    # windows is left out: the TUI is where to switch.
    STATUS_LEFT = " aix · @\#{=/40/…:window_name}" \
                  "\#{P:\#{?\#{#{AGENT_MARK}},\#{?\#{==:\#{pane_title},\#{host}},, · \#{=/50/…:pane_title}},}} "
    # While the pane in front is in a tmux mode (copy mode, entered by
    # scrolling back with the mouse wheel or dragging to select), it says
    # so, and how to leave: in copy mode with emacs keys, typing leaves it
    # too (`bind_typing_in_copy_mode`).
    STATUS_RIGHT = "\#{?pane_in_mode,\#[reverse] " \
                   "\#{?\#{&&:\#{==:\#{pane_mode},copy-mode},\#{==:\#{mode-keys},emacs}}," \
                   "copy mode: type or Esc to leave,\#{s/-/ /:pane_mode}: Esc leaves} \#[noreverse]  ,}" \
                   "F12: back to aix · " \
                   "\#{?\#{P:\#{?\#{#{FILES_MARK}},1,}},#{FILES_KEY}: close files,#{FILES_KEY}: files}" \
                   "\#{?#{LEAD_OPTION}, · F9: @\#{#{LEAD_OPTION}},}  %H:%M %d-%b-%y "
    STATUS_FORMAT = "\#[align=left range=left \#{E:status-left-style}]\#[push-default]" \
                    "\#{T;=/\#{status-left-length}:status-left}\#[pop-default]\#[norange default]" \
                    "\#[nolist align=right range=right \#{E:status-right-style}]\#[push-default]" \
                    "\#{T;=/\#{status-right-length}:status-right}\#[pop-default]\#[norange default]"

    private def self.status_line
      run("set-option", "-t", TARGET, "status-left-length", "110")
      run("set-option", "-t", TARGET, "status-left", STATUS_LEFT)
      run("set-option", "-t", TARGET, "status-right-length", "80")
      run("set-option", "-t", TARGET, "status-right", STATUS_RIGHT)
      run("set-option", "-t", TARGET, "status-format[0]", STATUS_FORMAT)
    end

    # A pane of a window, as aix reads it.
    record PaneRow, window : String, id : String, index : Int32, pid : Int64?, dead : Bool,
      marked : Bool, start : String

    # The panes of the aix session's windows.
    def self.panes : Array(PaneRow)
      format = "\#{window_name}\t\#{pane_id}\t\#{pane_index}\t\#{pane_pid}\t\#{pane_dead}\t" \
               "\#{#{AGENT_MARK}}\t\#{pane_start_command}"
      capture("list-panes", "-s", "-t", TARGET, "-F", format).lines.compact_map do |line|
        fields = line.split('\t', 7)
        next unless fields.size == 7
        window, id, index, pid, dead, mark, start = fields
        PaneRow.new(window, id, index.to_i? || 0, pid.to_i64?, dead == "1", mark == "1", start.strip)
      end
    rescue
      [] of PaneRow
    end

    # Each window's agent pane: the one aix marked, else (a window from an
    # aix before the mark) the one started as a harness, else the first.
    def self.agent_panes : Hash(String, PaneRow)
      panes.group_by(&.window).transform_values do |rows|
        rows.find(&.marked) || rows.find { |row| harness_command?(row.start) } || rows.min_by(&.index)
      end
    end

    # Window `name`'s agent pane.
    def self.agent_pane(name : String) : PaneRow?
      agent_panes[name]?
    end

    # Each window's agent title: the one its harness gave its pane (what
    # the conversation is about, and whether it's working), unless it's
    # still tmux's default, the machine's name.
    def self.agent_titles : Hash(String, String)
      format = "\#{window_name}\t\#{#{AGENT_MARK}}\t\#{pane_index}\t\#{host}\t\#{pane_title}"
      rows = capture("list-panes", "-s", "-t", TARGET, "-F", format).lines.compact_map do |line|
        fields = line.split('\t', 5)
        fields.size == 5 ? fields : nil
      end
      rows.group_by(&.[0]).compact_map do |window, panes|
        pane = panes.find { |fields| fields[1] == "1" } || panes.min_by { |fields| fields[2].to_i? || 0 }
        title = pane[4].strip
        {window, title} unless title.empty? || title == pane[3]
      end.to_h
    rescue
      {} of String => String
    end

    private def self.harness_command?(command : String) : Bool
      program = command.lstrip('"').split(' ', 2).first? || return false
      {"claude", "codex"}.includes?(File.basename(program))
    end

    # Mark, in windows an older aix made, the agent's pane, and move
    # `remain-on-exit` from the window, where it kept any pane added to it
    # (`new-pane`, a split) after its shell exited, to that pane alone.
    private def self.mark_agent_panes
      agent_panes.each do |window, pane|
        next if pane.marked || window == PLACEHOLDER_WINDOW
        Process.run("tmux", ["set-option", "-w", "-u", "-t", pane.id, "remain-on-exit"], error: Process::Redirect::Close)
        Process.run("tmux", ["set-option", "-w", "-u", "-t", pane.id, "remain-on-exit-format"], error: Process::Redirect::Close)
        program = File.basename(pane.start.lstrip('"').split(' ', 2).first? || "")
        mark_agent(pane.id, program.empty? ? "its program" : program)
      end
    rescue
      # Not marked: the first pane is taken as the agent's, as before.
    end

    # Make `pane` an agent's: marked, and kept with its last screen and a
    # notice when `program` exits.
    private def self.mark_agent(pane : String, program : String)
      run("set-option", "-p", "-t", pane, AGENT_MARK, "1")
      run("set-option", "-p", "-t", pane, "remain-on-exit", "on")
      run("set-option", "-p", "-t", pane, "remain-on-exit-format", exited_notice(program))
    end

    # A pane of one window, as the file pane needs it.
    record WindowPane, window : String, id : String, active : Bool, agent : Bool, files : Bool, path : String,
      client : String = ""

    # The panes of window `window`: its id (`@3`, as a key binding gives
    # it) or its name in the aix session.
    def self.window_panes(window : String) : Array(WindowPane)
      target = window.starts_with?('@') ? window : "#{TARGET}=#{window}"
      format = "\#{window_name}\t\#{pane_id}\t\#{pane_active}\t\#{#{AGENT_MARK}}\t\#{#{FILES_MARK}}\t" \
               "\#{#{FILES_CLIENT}}\t\#{pane_current_path}"
      capture("list-panes", "-t", target, "-F", format).lines.compact_map do |line|
        fields = line.split('\t', 7)
        next unless fields.size == 7
        name, id, active, agent, files, client, path = fields
        WindowPane.new(name, id, active == "1", agent == "1", files == "1", path.strip, client)
      end
    rescue
      [] of WindowPane
    end

    def self.select_pane(pane : String)
      run("select-pane", "-t", pane)
    end

    # Open a file pane beside `agent_pane`: `command` in `directory`, with
    # `env`, to its right, half the window, marked as the window's file
    # pane, with the browser's id (`client`) for closing it. It's where the
    # keys go next. Images pass through to the terminal, for the browser's
    # previews.
    def self.open_files_pane(agent_pane : String, directory : String, command : Array(String),
                             env : Hash(String, String), client : String) : String
      err = IO::Memory.new
      created = IO::Memory.new
      args = ["split-window", "-h", "-l", "50%", "-t", agent_pane, "-c", directory, "-P", "-F", "\#{pane_id}"]
      env.each { |key, value| args.concat(["-e", "#{key}=#{value}"]) }
      args << "--"
      args.concat(command)
      result = Process.run("tmux", args, output: created, error: err)
      raise "tmux split-window: #{err.to_s.strip}" unless result.success?
      pane = created.to_s.strip
      run("set-option", "-p", "-t", pane, FILES_MARK, "1")
      run("set-option", "-p", "-t", pane, FILES_CLIENT, client)
      Process.run("tmux", ["set-option", "-p", "-t", pane, "allow-passthrough", "on"], error: Process::Redirect::Close)
      pane
    end

    # Quit a browser in `pane` by its keys: Escape out of whatever it's
    # doing, then `q`.
    def self.quit_by_keys(pane : String)
      run("send-keys", "-t", pane, "Escape")
      sleep 200.milliseconds
      run("send-keys", "-t", pane, "q")
    rescue
      # Gone already.
    end

    def self.pane_exists?(pane : String) : Bool
      Process.run("tmux", ["display-message", "-p", "-t", pane, "\#{pane_id}"],
        output: Process::Redirect::Close, error: Process::Redirect::Close).success?
    end

    def self.kill_pane(pane : String)
      Process.run("tmux", ["kill-pane", "-t", pane], error: Process::Redirect::Close)
    end

    # The target for window `name`'s agent pane: its id, or the window
    # itself if it can't be read.
    private def self.agent_target(name : String) : String
      agent_pane(name).try(&.id) || "#{TARGET}=#{name}"
    end

    def self.session_exists? : Bool
      Process.run("tmux", ["has-session", "-t", TARGET],
        error: Process::Redirect::Close).success?
    end

    # Whether window `name` is open with its program still running. A
    # window whose program has exited stays (`remain-on-exit`), showing its
    # last screen, but doesn't count.
    def self.window_exists?(name : String) : Bool
      window_state(name) == :running
    end

    # Whether window `name` is there with its program exited.
    def self.window_dead?(name : String) : Bool
      window_state(name) == :dead
    end

    private def self.window_state(name : String) : Symbol?
      pane = agent_pane(name) || return nil
      pane.dead ? :dead : :running
    end

    # What a window shows under its program's last screen when the program
    # has exited.
    def self.exited_notice(program : String) : String
      "#{program} exited (\#{?pane_dead_signal,signal \#{pane_dead_signal},status \#{pane_dead_status}}). " \
      "F12: back to aix, where Enter starts it again."
    end

    # Create a new window running `command` (a program and its arguments),
    # with `env` set in its environment. The window stays when the program
    # exits (`remain-on-exit`), so its last screen, an error included, is
    # still there to see, rather than tmux moving the user to another
    # agent's window.
    def self.new_window(name : String, directory : String, command : Array(String),
                        env : Hash(String, String) = {} of String => String)
      ensure_session
      # A window left by an exited program is reused (killing it could
      # close the session, were it the last). A new one starts on a
      # placeholder, so `remain-on-exit` is on before the program starts,
      # however soon it exits.
      pane = agent_pane(name).try { |row| row.dead ? row.id : nil }
      unless pane
        err = IO::Memory.new
        created = IO::Memory.new
        result = Process.run("tmux", ["new-window", "-P", "-F", "\#{pane_id}", "-t", TARGET,
                                      "-n", name, "-c", directory, "--", "sleep", "60"],
          output: created, error: err)
        raise "tmux new-window: #{err.to_s.strip}" unless result.success?
        pane = created.to_s.strip
      end
      mark_agent(pane, command.first)
      respawn = ["respawn-pane", "-k", "-t", pane, "-c", directory]
      env.each { |key, value| respawn.concat(["-e", "#{key}=#{value}"]) }
      respawn << "--"
      respawn.concat(command)
      err = IO::Memory.new
      result = Process.run("tmux", respawn, error: err)
      raise "tmux respawn-pane: #{err.to_s.strip}" unless result.success?
      # Remove the bootstrap window created with the session.
      kill_placeholder_window
      # Give the window a moment to initialize
      sleep 500.milliseconds
    end

    # Kill the bootstrap window created by ensure_session.
    private def self.kill_placeholder_window
      return unless window_exists?(PLACEHOLDER_WINDOW)
      Process.run("tmux", ["kill-window", "-t", "#{TARGET}=#{PLACEHOLDER_WINDOW}"],
        error: Process::Redirect::Close)
    end

    # Kill a window.
    def self.kill_window(name : String)
      run("kill-window", "-t", "#{TARGET}=#{name}")
    end

    # Prefix-free key that jumps the attached client back to the Leader window.
    RETURN_TO_LEADER_KEY = "F9"

    # Select a window (make it active). Moves the view of any attached client.
    def self.select_window(name : String)
      run("select-window", "-t", "#{TARGET}=#{name}")
    end

    # Bind a prefix-free key (root table) to a tmux command.
    def self.bind_key(key : String, *command : String)
      run("bind-key", "-n", key, *command)
    end

    # (Re)bind RETURN_TO_LEADER_KEY to jump straight to the Leader's window,
    # and name it on the status line.
    def self.bind_return_to_leader(leader_window : String)
      bind_key(RETURN_TO_LEADER_KEY, "select-window", "-t", "#{TARGET}=#{leader_window}")
      run("set-option", "-t", TARGET, LEAD_OPTION, leader_window)
    end

    # Attach to the aix session. Blocks until the user detaches.
    def self.attach
      Process.run("tmux", ["attach", "-t", TARGET],
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
    end

    # Rename a window.
    def self.rename_window(old_name : String, new_name : String)
      run("rename-window", "-t", "#{TARGET}=#{old_name}", new_name)
    end

    # List window names in the aix session.
    def self.list_windows : Array(String)
      output = capture("list-windows", "-t", TARGET, "-F", "#W")
      output.split('\n').reject(&.empty?)
    rescue
      [] of String
    end

    # Send keystrokes to a window's pane.
    def self.send_keys(name : String, keys : String)
      run("send-keys", "-t", agent_target(name), keys, "Enter")
    end

    # Send literal text to a window without pressing Enter.
    def self.send_literal(name : String, text : String)
      run("send-keys", "-t", agent_target(name), "-l", text)
    end

    # Send a named tmux key to a window.
    def self.send_key(name : String, key : String)
      run("send-keys", "-t", agent_target(name), key)
    end

    # Capture visible pane content. Optional line count scrolls back.
    def self.capture_pane(name : String, lines : Int32? = nil) : String
      args = ["capture-pane", "-t", agent_target(name), "-p"]
      if n = lines
        args += ["-S", "-#{n}"]
      end
      output = IO::Memory.new
      result = Process.run("tmux", args,
        output: output,
        error: Process::Redirect::Close)
      raise "tmux capture-pane: failed" unless result.success?
      output.to_s
    end

    # The visible screen of window `name` (exactly that name), as text. Nil
    # if there's no such window. When its program has exited, tmux puts
    # `exited_notice` on the bottom line, and its last output may have gone
    # up into the history, so a screen's worth of history comes too, with
    # the blank lines between the output and the notice taken out.
    def self.capture_screen(name : String) : String?
      target = agent_pane(name).try(&.id) || return nil
      dead, _, height = capture("display-message", "-p", "-t", target, "\#{pane_dead}\t\#{pane_height}")
        .strip.partition('\t')
      return capture("capture-pane", "-p", "-t", target) unless dead == "1"
      lines = capture("capture-pane", "-p", "-t", target, "-S", "-#{height}").lines.map(&.rstrip)
      while lines.last?.try(&.empty?)
        lines.pop
      end
      notice = lines.pop? || return ""
      while lines.last?.try(&.empty?)
        lines.pop
      end
      (lines << notice).join("\n") + "\n"
    rescue
      nil
    end

    # Resize a window to better fit a browser client.
    def self.resize_window(name : String, cols : Int32, rows : Int32)
      run("resize-window", "-t", "#{TARGET}=#{name}", "-x", cols.to_s, "-y", rows.to_s)
    end

    # A pane's state, as the bell needs it: which pane, its process, whether
    # it has the user's keys (the active pane of the active window of a
    # session someone is attached to), and where its cursor is.
    # A pane as the bell reads it. `cursor_x` and `cursor_y` are its
    # program's cursor, and `mode` the tmux mode it's in (`copy-mode` while
    # scrolled back, or none, ""), which leaves those as they are.
    record PaneInfo, id : String, pid : Int64, focused : Bool, cursor_x : Int32, cursor_y : Int32,
      mode : String = ""

    # The agent's pane in a window of the aix session (`agent_pane`), or nil
    # if there's no window by that exact name, or its program has exited.
    def self.pane_info(window : String) : PaneInfo?
      pane = agent_pane(window) || return nil
      return nil if pane.dead
      format = "\#{pane_id}\t\#{pane_pid}\t\#{pane_active}\t\#{window_active}\t" \
               "\#{session_attached}\t\#{cursor_x}\t\#{cursor_y}\t\#{?pane_in_mode,\#{pane_mode},}"
      line = capture("display-message", "-p", "-t", pane.id, format).lines.first?
      return nil unless line
      id, pid, pane_active, window_active, attached, x, y, mode = line.split('\t', 8)
      focused = pane_active == "1" && window_active == "1" && attached.to_i > 0
      PaneInfo.new(id, pid.to_i64, focused, x.to_i, y.to_i, mode.strip)
    rescue
      nil
    end

    # Take `pane` out of the tmux mode it's in (copy mode, say), as Esc
    # would. Whether it's out.
    def self.leave_mode(pane : String) : Bool
      Process.run("tmux", ["send-keys", "-t", pane, "-X", "cancel"], error: Process::Redirect::Close)
      capture("display-message", "-p", "-t", pane, "\#{pane_in_mode}").strip == "0"
    rescue
      false
    end

    # The windows of the aix session, with their agent pane's process. A
    # window whose program has exited has none, and isn't listed.
    def self.window_pids : Array({String, Int64})
      agent_panes.compact_map do |name, pane|
        next if pane.dead
        pane.pid.try { |pid| {name, pid} }
      end
    end

    # When a client attached to the aix session last had a key from the
    # user, or nil if none is attached.
    def self.last_client_activity : Time?
      capture("list-clients", "-t", TARGET, "-F", "\#{client_activity}")
        .lines.compact_map(&.strip.to_i64?).max?.try { |secs| Time.unix(secs) }
    rescue
      nil
    end

    # Visible line `y` of a pane (0 is the top line) with its colours and
    # attributes, as escape sequences.
    def self.pane_line_styled(pane_id : String, y : Int32) : String
      capture("capture-pane", "-p", "-e", "-t", pane_id, "-S", y.to_s, "-E", y.to_s).chomp
    end

    # Visible lines `from` to `to` of a pane (0 is the top line). A line
    # outside the pane comes back empty.
    def self.pane_lines(pane_id : String, from : Int32, to : Int32) : Array(String)
      lines = (from..to).map { "" }
      first = {from, 0}.max
      return lines if to < first
      captured = capture("capture-pane", "-p", "-t", pane_id, "-S", first.to_s, "-E", to.to_s).lines
      captured.each_with_index { |text, i| lines[first - from + i] = text if first - from + i < lines.size }
      lines
    end

    # Type `text` into a pane, then press Enter. The text goes literally, so
    # nothing in it is read as a key name; Enter follows a moment later so
    # the harness doesn't take it as part of a paste.
    # Paste `text` into `pane_id` as a terminal would: marked as a paste
    # (bracketed paste, `-p`) when the program asked for that, as Claude
    # Code and Codex do, so its newlines are part of the text rather than
    # Enter. Through a buffer of its own, deleted after (`-d`).
    def self.paste(pane_id : String, text : String)
      buffer = "aix-paste-#{Random::Secure.hex(6)}"
      error = IO::Memory.new
      loaded = Process.run("tmux", ["load-buffer", "-b", buffer, "-"], input: IO::Memory.new(text), error: error)
      raise "tmux load-buffer: #{error.to_s.strip}" unless loaded.success?
      run("paste-buffer", "-p", "-d", "-b", buffer, "-t", pane_id)
    end

    def self.type_line(pane_id : String, text : String)
      run("send-keys", "-t", pane_id, "-l", text)
      sleep 150.milliseconds
      run("send-keys", "-t", pane_id, "Enter")
    end

    # Show a message on every client attached to the aix session.
    def self.display_message(text : String, duration : Time::Span = 5.seconds)
      capture("list-clients", "-t", TARGET, "-F", "\#{client_name}").lines.each do |client|
        next if client.strip.empty?
        run("display-message", "-c", client.strip, "-d", duration.total_milliseconds.to_i.to_s, text)
      end
    rescue
      # No clients, or the session is gone: nobody to show it to.
    end

    # Clean up — kill the whole session.
    def self.kill_session
      run("kill-session", "-t", TARGET) if session_exists?
    end

    private def self.rows : Int32
      `tput lines`.strip.to_i rescue 24
    end

    private def self.cols : Int32
      `tput cols`.strip.to_i rescue 80
    end

    private def self.run(*args : String)
      result = Process.run("tmux", args.to_a,
        error: Process::Redirect::Pipe)
      unless result.success?
        raise "tmux #{args.first}: failed"
      end
    end

    private def self.capture(*args : String) : String
      output = IO::Memory.new
      result = Process.run("tmux", args.to_a,
        output: output,
        error: Process::Redirect::Close)
      raise "tmux #{args.first}: failed" unless result.success?
      output.to_s
    end
  end
end
