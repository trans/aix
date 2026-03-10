require "./aix/terminal"
require "./aix/session"
require "./aix/session_manager"
require "./aix/meta_console"
require "./aix/passthrough"

module Aix
  VERSION = "0.1.0"

  def self.run
    manager = SessionManager.new
    console = MetaConsole.new(manager)
    passthrough = Passthrough.new

    # Save original terminal state
    Terminal.save

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
          session.reap
          if code = session.exit_status
            puts "Session '#{session.name}' exited (#{code})."
          else
            puts "Session '#{session.name}' ended."
          end
        end
      end
    end

    # Cleanup
    manager.stop_all
    Terminal.restore!
    puts "Goodbye."
  end
end

Aix.run
