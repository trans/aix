require "./tmux"

module Aix
  enum SessionState
    Cold    # Registered but no tmux window yet
    Running # Claude Code running in a tmux window
    Stopped # Window closed / process exited
  end

  class Session
    property name : String
    getter directory : String

    def initialize(@name : String, @directory : String)
    end

    def state : SessionState
      if Tmux.window_exists?(@name)
        SessionState::Running
      else
        @started ? SessionState::Stopped : SessionState::Cold
      end
    end

    def running? : Bool
      state == SessionState::Running
    end

    def cold? : Bool
      state == SessionState::Cold
    end

    # Start Claude Code in a tmux window.
    def start(args : Array(String) = [] of String)
      raise "Session '#{@name}' is already running" if running?
      Tmux.new_window(@name, @directory, args)
      @started = true
    end

    # Stop the session by killing the tmux window.
    def stop
      Tmux.kill_window(@name) if running?
    end

    @started = false
  end
end
