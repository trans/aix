module Aix
  # Thin wrapper around tmux CLI commands.
  module Tmux
    SESSION = "aix"
    PLACEHOLDER_WINDOW = "__aix_placeholder__"

    # Ensure the aix tmux session exists. Creates it if not.
    # If no windows exist yet, creates a placeholder that new_window will replace.
    def self.ensure_session
      return if session_exists?
      # Start tmux server with clean env (no Claude nesting vars)
      result = Process.run("env", ["-u", "CLAUDECODE", "-u", "CLAUDE_CODE_ENTRYPOINT",
                                   "tmux", "new-session", "-d", "-s", SESSION,
                                   "-n", PLACEHOLDER_WINDOW,
                                   "-x", "#{cols}", "-y", "#{rows}"],
                           error: Process::Redirect::Pipe)
      raise "tmux new-session: failed" unless result.success?
      # Bind F12 to detach (prefix-free, aix session only)
      run("bind-key", "-n", "F12", "detach-client")
      # Enable mouse scrollback and generous history
      run("set-option", "-t", SESSION, "mouse", "on")
      run("set-option", "-t", SESSION, "history-limit", "10000")
      # Auto-close windows when process exits (no dead shell prompt)
      run("set-option", "-t", SESSION, "remain-on-exit", "off")
    end

    def self.session_exists? : Bool
      Process.run("tmux", ["has-session", "-t", SESSION],
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
      output = IO::Memory.new
      result = Process.run("tmux", ["list-windows", "-t", SESSION, "-F", "\#{window_name}\t\#{pane_dead}"],
        output: output, error: Process::Redirect::Close)
      return nil unless result.success?
      output.to_s.each_line do |line|
        window, _, dead = line.partition('\t')
        return dead.strip == "1" ? :dead : :running if window == name
      end
      nil
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
      pane = window_dead?(name) ? capture("list-panes", "-t", "#{SESSION}:=#{name}", "-F", "\#{pane_id}").lines.first.strip : nil
      unless pane
        err = IO::Memory.new
        created = IO::Memory.new
        result = Process.run("tmux", ["new-window", "-P", "-F", "\#{pane_id}", "-t", SESSION,
                                      "-n", name, "-c", directory, "--", "sleep", "60"],
          output: created, error: err)
        raise "tmux new-window: #{err.to_s.strip}" unless result.success?
        pane = created.to_s.strip
        run("set-option", "-w", "-t", pane, "remain-on-exit", "on")
      end
      run("set-option", "-w", "-t", pane, "remain-on-exit-format", exited_notice(command.first))
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
      Process.run("tmux", ["kill-window", "-t", "#{SESSION}:=#{PLACEHOLDER_WINDOW}"],
        error: Process::Redirect::Close)
    end

    # Kill a window.
    def self.kill_window(name : String)
      run("kill-window", "-t", "#{SESSION}:=#{name}")
    end

    # Prefix-free key that jumps the attached client back to the Leader window.
    RETURN_TO_LEADER_KEY = "F9"

    # Select a window (make it active). Moves the view of any attached client.
    def self.select_window(name : String)
      run("select-window", "-t", "#{SESSION}:=#{name}")
    end

    # Bind a prefix-free key (root table) to a tmux command.
    def self.bind_key(key : String, *command : String)
      run("bind-key", "-n", key, *command)
    end

    # (Re)bind RETURN_TO_LEADER_KEY to jump straight to the Leader's window.
    def self.bind_return_to_leader(leader_window : String)
      bind_key(RETURN_TO_LEADER_KEY, "select-window", "-t", "#{SESSION}:=#{leader_window}")
    end

    # Attach to the aix session. Blocks until the user detaches.
    def self.attach
      Process.run("tmux", ["attach", "-t", SESSION],
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
    end

    # Rename a window.
    def self.rename_window(old_name : String, new_name : String)
      run("rename-window", "-t", "#{SESSION}:=#{old_name}", new_name)
    end

    # List window names in the aix session.
    def self.list_windows : Array(String)
      output = capture("list-windows", "-t", SESSION, "-F", "#W")
      output.split('\n').reject(&.empty?)
    rescue
      [] of String
    end

    # Send keystrokes to a window's pane.
    def self.send_keys(name : String, keys : String)
      run("send-keys", "-t", "#{SESSION}:=#{name}", keys, "Enter")
    end

    # Send literal text to a window without pressing Enter.
    def self.send_literal(name : String, text : String)
      run("send-keys", "-t", "#{SESSION}:=#{name}", "-l", text)
    end

    # Send a named tmux key to a window.
    def self.send_key(name : String, key : String)
      run("send-keys", "-t", "#{SESSION}:=#{name}", key)
    end

    # Capture visible pane content. Optional line count scrolls back.
    def self.capture_pane(name : String, lines : Int32? = nil) : String
      args = ["capture-pane", "-t", "#{SESSION}:=#{name}", "-p"]
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
      target = "#{SESSION}:=#{name}"
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
      run("resize-window", "-t", "#{SESSION}:=#{name}", "-x", cols.to_s, "-y", rows.to_s)
    end

    # A pane's state, as the bell needs it: which pane, its process, whether
    # it has the user's keys (the active pane of the active window of a
    # session someone is attached to), and where its cursor is.
    record PaneInfo, id : String, pid : Int64, focused : Bool, cursor_x : Int32, cursor_y : Int32

    # The agent's pane in a window of the aix session (its first pane), or
    # nil if there's no window by that exact name.
    def self.pane_info(window : String) : PaneInfo?
      format = "\#{pane_id}\t\#{pane_pid}\t\#{pane_active}\t\#{window_active}\t" \
               "\#{session_attached}\t\#{cursor_x}\t\#{cursor_y}"
      line = capture("list-panes", "-t", "#{SESSION}:=#{window}", "-F", format).lines.first?
      return nil unless line
      id, pid, pane_active, window_active, attached, x, y = line.split('\t')
      focused = pane_active == "1" && window_active == "1" && attached.to_i > 0
      PaneInfo.new(id, pid.to_i64, focused, x.to_i, y.to_i)
    rescue
      nil
    end

    # The windows of the aix session, with their first pane's process.
    def self.window_pids : Array({String, Int64})
      capture("list-panes", "-s", "-t", SESSION, "-F", "\#{window_name}\t\#{pane_index}\t\#{pane_pid}")
        .lines.compact_map do |line|
          name, index, pid = line.split('\t')
          index == "0" ? {name, pid.to_i64} : nil
        end
    rescue
      [] of {String, Int64}
    end

    # When a client attached to the aix session last had a key from the
    # user, or nil if none is attached.
    def self.last_client_activity : Time?
      capture("list-clients", "-t", SESSION, "-F", "\#{client_activity}")
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
    def self.type_line(pane_id : String, text : String)
      run("send-keys", "-t", pane_id, "-l", text)
      sleep 150.milliseconds
      run("send-keys", "-t", pane_id, "Enter")
    end

    # Show a message on every client attached to the aix session.
    def self.display_message(text : String, duration : Time::Span = 5.seconds)
      capture("list-clients", "-t", SESSION, "-F", "\#{client_name}").lines.each do |client|
        next if client.strip.empty?
        run("display-message", "-c", client.strip, "-d", duration.total_milliseconds.to_i.to_s, text)
      end
    rescue
      # No clients, or the session is gone: nobody to show it to.
    end

    # Clean up — kill the whole session.
    def self.kill_session
      run("kill-session", "-t", SESSION) if session_exists?
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
