require "json"
require "./session_manager"
require "./tmux"

module Aix
  # Programmatic control surface over SessionManager. Unlike the REPL/TUI/web
  # front-ends, every method returns structured data (JSON-serializable) and
  # prints nothing — this is the interface a Leader/orchestrator drives Aix
  # through, whether over MCP, Arcana, or in-process.
  #
  # State lives in tmux (running windows) and the filesystem (config +
  # discovery), so a Control instance in a separate process still sees the
  # same sessions as the interactive UI.
  class Control
    getter manager : SessionManager

    def initialize(@manager : SessionManager = SessionManager.new)
      Tmux.ensure_session
    end

    # All discovered projects with their live state.
    def list
      @manager.refresh
      @manager.sessions.map { |s| info(s) }
    end

    # A single project's state.
    def status(name : String)
      info(require_session(name))
    end

    # Configured root paths and scan depth.
    def roots
      {roots: @manager.config.roots, depth: @manager.config.depth}
    end

    # Add a root path and re-discover. Returns whether it was newly added
    # and the resulting project count.
    def add_root(path : String)
      added = @manager.add_root(path)
      {added: added, count: @manager.sessions.size}
    end

    # Re-scan roots for projects.
    def refresh
      @manager.refresh
      {ok: true, count: @manager.sessions.size}
    end

    # Start the AI harness in a project's tmux window.
    def start(name : String, args : Array(String) = [] of String)
      @manager.refresh
      session = @manager.start(name, args)
      @manager.persist_sessions
      info(session)
    end

    # Stop a running session's window (the project stays discoverable).
    def stop(name : String)
      session = require_session(name)
      session.stop if session.running?
      info(session)
    end

    # Send a line of text (followed by Enter) to a running session.
    def send_text(name : String, text : String)
      session = require_session(name)
      raise "'#{name}' is not running" unless session.running?
      Tmux.send_keys(session.name, text)
      {ok: true, name: session.name}
    end

    # Capture a running session's visible pane. `lines` scrolls back that
    # many lines of history.
    def peek(name : String, lines : Int32? = nil) : String
      session = require_session(name)
      raise "'#{name}' is not running" unless session.running?
      Tmux.capture_pane(session.name, lines)
    end

    private def require_session(name : String) : Session
      @manager.refresh
      session = @manager.find(name)
      raise "No project named '#{name}'" unless session
      session
    end

    private def info(session : Session)
      {
        name:      session.name,
        directory: session.directory,
        state:     state_label(session),
        running:   session.running?,
      }
    end

    private def state_label(session : Session) : String
      case session.state
      when SessionState::Running then "running"
      when SessionState::Cold    then "cold"
      else                            "stopped"
      end
    end
  end
end
