require "json"
require "./tmux"
require "./harness"
require "./runner"
require "./screens"
require "./conversations"

module Aix
  enum SessionState
    Cold    # Registered but no tmux window yet
    Running # Its harness running in a tmux window
    Stopped # Window closed / process exited
  end

  class Session
    property name : String
    getter directory : String
    property claude_session_id : String?
    # The project above this one in the tree of responsibility, if any, and
    # how many projects are above it.
    property parent : String?
    property level : Int32 = 0
    # Whether to start Claude Code with dot-ai's mail channel, the bell's
    # fallback (`Harness`), from the config's `mail.channel`.
    property mail_channel : Bool = false
    # The harness its agent runs in: the person's choice, else what the
    # project is set up for (`Harness.detect`).
    property harness : Harness::Kind = Harness::Kind::Claude

    def initialize(@name : String, @directory : String, @claude_session_id : String? = nil)
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

    # Start its harness in a tmux window, `args` after the program's own.
    # aix's bell tells it of mail (`Bell`), or, for Claude Code, dot-ai's
    # mail channel does when the config's `mail.channel` is on
    # (`Harness.claude_args`). A session aix runs registers aix as a runner
    # first, so dot-ai's carrier can find it (`Runner.register`).
    def start(args : Array(String) = [] of String)
      raise "Session '#{@name}' is already running" if running?
      command = Harness.command(@harness, args, @mail_channel)
      env = Harness.session_env(command)
      Runner.register if env["DOT_AI_BY"]? == Runner::NAME
      Tmux.new_window(@name, @directory, command, env)
      @started = true
      capture_claude_session_id if @harness.claude?
    end

    # The arguments that resume its last conversation (`Harness.resume_args`).
    def resume_args : Array(String)
      Harness.resume_args(@harness, @directory, @claude_session_id)
    end

    # The conversation, open in another program, that resuming would take
    # over, if any: `open` is the project's conversations open outside
    # aix (`Conversations`). aix doesn't resume one of those.
    def resume_blocker(open : Array(Conversations::Open)) : Conversations::Open?
      target = @harness.claude? ? Harness.claude_resume_target(@directory, @claude_session_id) : nil
      Conversations.blocking(open, @harness, target)
    end

    # Why it can't be resumed now, or nil if it can.
    def resume_refusal : String?
      blocker = resume_blocker(Conversations.in(Conversations.elsewhere, @directory)) || return nil
      "its conversation is open in #{blocker.where} (pid #{blocker.pid}). " \
      "Close it there to resume it here."
    end

    # Scan ~/.claude/sessions/ for the most recent session matching our directory.
    def capture_claude_session_id
      sessions_dir = File.join(Path.home, ".claude", "sessions")
      return unless Dir.exists?(sessions_dir)

      best_id : String? = nil
      best_time : Int64 = 0

      Dir.each_child(sessions_dir) do |file|
        next unless file.ends_with?(".json")
        path = File.join(sessions_dir, file)
        begin
          data = JSON.parse(File.read(path))
          cwd = data["cwd"]?.try(&.as_s)
          next unless cwd == @directory
          started_at = data["startedAt"]?.try(&.as_i64) || 0_i64
          if started_at > best_time
            best_time = started_at
            best_id = data["sessionId"]?.try(&.as_s)
          end
        rescue
          next
        end
      end

      @claude_session_id = best_id if best_id
    end

    # Stop the session by killing the tmux window, keeping its last screen
    # for the TUI's preview first.
    def stop
      return unless running? || Tmux.window_dead?(@name)
      Screens.capture(@name)
      Tmux.kill_window(@name)
    end

    @started = false
  end
end
