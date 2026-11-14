require "./aix/tmux"
require "./aix/config"
require "./aix/session"
require "./aix/session_manager"
require "./aix/meta_console"
require "./aix/tui"
require "./aix/passthrough"
require "./aix/web_app"
require "./aix/control"
require "./aix/mcp_server"
require "./aix/bell"
require "./aix/runner"
require "./aix/conversations"

module Aix
  VERSION = "0.3.2"

  def self.run
    if ARGV.first? == "tell"
      exit tell(ARGV[1]?)
    end

    if ARGV.includes?("--mcp")
      # MCP stdio server: stdout is reserved for protocol messages only.
      MCPServer.new.run
      return
    end

    if ARGV.includes?("--web")
      run_web
      return
    end

    repl_mode = ARGV.includes?("--repl")

    # Ensure tmux session exists
    Tmux.ensure_session

    manager = SessionManager.new
    passthrough = Passthrough.new

    if repl_mode
      run_repl(manager, passthrough)
    else
      run_tui(manager, passthrough)
    end

    # Quitting leaves the agents running in tmux: they get on without the
    # TUI, and `aix` picks them up again. Stop one with `d`. The session
    # goes only when nothing is left in it.
    running = manager.sessions.count(&.running?)
    Tmux.kill_session if running == 0
    puts running == 0 ? "Goodbye." : "Goodbye. #{running} agent(s) still running; `aix` picks them up again."
  end

  # `aix tell ID`: ring the bell for one session, by its window name or its
  # Claude Code session id. This is the `tell` dot-ai's carrier runs for a
  # session whose runner is aix (dot-ai's spec, "Runners"); its exit status
  # is the spec's: 0 told (or will be at the end of its turn), 3 not open,
  # 4 can't be told now.
  def self.tell(id : String?) : Int32
    unless id
      STDERR.puts "usage: aix tell <window | session id>"
      return 2
    end
    window = tell_window(id)
    unless window
      status, reason = Runner.not_in_pane(id)
      puts "#{id}: #{reason}"
      return status
    end
    result, reason = Bell.ring(window)
    puts "#{window}: #{result.to_s.downcase}, #{reason}"
    # Held: the session hears at its next Stop or start. Let the user know
    # meanwhile, since it's usually them it waits on.
    Tmux.display_message("aix: mail for @#{window} (#{reason})") if result.held?
    result.exit_status
  end

  # The window for a session: a window by that name, or the one whose pane
  # runs the session with that id (Claude Code's own session files give its
  # process; dot-ai's record gives it for other harnesses).
  private def self.tell_window(id : String) : String?
    return id if Tmux.window_exists?(id)
    pid = Harness.claude_pid(id) || Runner.session_record(id).try(&.pid) || return nil
    parent = Harness.parent_pid(pid)
    Tmux.window_pids.find { |_name, pane_pid| pane_pid == pid || pane_pid == parent }.try(&.[0])
  end

  def self.run_web
    host = option_value("--host") || ENV["AIX_HOST"]? || "127.0.0.1"
    port = (option_value("--port") || ENV["AIX_PORT"]? || "9292").to_i

    strip_option("--web")
    strip_option("--host")
    strip_option("--port")

    puts "Starting AIX web on http://#{host}:#{port}"
    WebApp.run(host, port)
  end

  def self.run_tui(manager, passthrough)
    tui = TUI.new(manager)

    loop do
      result = tui.run

      case result
      when :quit
        break
      when :switch
        session = manager.active
        next unless session

        pass_result = passthrough.run(session)

        case pass_result
        when :session_ended
          # Session died, back to TUI
        end
      end
    end
  end

  def self.run_repl(manager, passthrough)
    console = MetaConsole.new(manager)

    puts "AIX v#{VERSION} — AI harness manager (Claude Code, Codex)"
    puts "Type 'help' for commands.\n"

    loop do
      result = console.run

      case result
      when :quit
        break
      when :switch
        session = manager.active
        next unless session

        pass_result = passthrough.run(session)

        case pass_result
        when :escape
          # Clean return to meta console
        when :session_ended
          puts "Session '#{session.name}' ended."
        end
      end
    end
  end

  private def self.option_value(flag : String) : String?
    if idx = ARGV.index(flag)
      ARGV[idx + 1]?
    else
      ARGV.find do |arg|
        arg.starts_with?("#{flag}=")
      end.try(&.split("=", 2)[1]?)
    end
  end

  private def self.strip_option(flag : String)
    if idx = ARGV.index(flag)
      ARGV.delete_at(idx)
      ARGV.delete_at(idx) if ARGV[idx]?
    end

    ARGV.reject! do |arg|
      arg.starts_with?("#{flag}=")
    end
  end
end
