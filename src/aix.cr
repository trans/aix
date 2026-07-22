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

module Aix
  VERSION = "0.2.0"

  def self.run
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

    # Cleanup
    manager.stop_all
    Tmux.kill_session if manager.sessions.all? { |s| !s.running? }
    puts "Goodbye."
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

    puts "AIX v#{VERSION} — Claude Code multiplexer"
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

Aix.run
