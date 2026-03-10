require "./aix/tmux"
require "./aix/session"
require "./aix/session_manager"
require "./aix/meta_console"
require "./aix/passthrough"

module Aix
  VERSION = "0.1.0"

  def self.run
    # Ensure tmux session exists
    Tmux.ensure_session

    manager = SessionManager.new
    console = MetaConsole.new(manager)
    passthrough = Passthrough.new

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

    # Cleanup
    manager.stop_all
    Tmux.kill_session if manager.sessions.all? { |s| !s.running? }
    puts "Goodbye."
  end
end

Aix.run
