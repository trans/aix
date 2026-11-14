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

    # The directories searched for projects, how deep, and where the list
    # comes from: git config's `ai.path`, or aix's own config without it.
    def roots
      config = @manager.config
      {roots: config.search_roots, depth: config.search_depth, from: config.ai_path? ? "ai.path" : "config"}
    end

    # Add a root path and re-discover. Returns whether it was newly added
    # and the resulting project count.
    def add_root(path : String)
      added = @manager.add_root(path)
      {added: added, count: @manager.sessions.size}
    end

    # Search for projects again.
    def refresh
      @manager.refresh
      {ok: true, count: @manager.sessions.size}
    end

    # Start the AI harness in a project's tmux window: `harness` (`claude`
    # or `codex`) if given, kept as the project's choice, else the
    # project's own.
    def start(name : String, args : Array(String) = [] of String, harness : String? = nil)
      @manager.refresh
      if harness
        kind = Harness::Kind.parse?(harness) || raise "No harness '#{harness}': claude or codex"
        @manager.set_harness(name, kind)
      end
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

    # Switch the attached client's view to a project's pane ("patch me over
    # to @memo"). Accepts a bare or @-prefixed name.
    def focus(name : String)
      session = require_session(name.lstrip('@'))
      raise "'#{name}' is not running" unless session.running?
      Tmux.select_window(session.name)
      info(session)
    end

    # Designate a project as the Leader and (re)bind the return-to-Leader key
    # so the attached human can jump home from any pane.
    def set_leader(name : String)
      session = require_session(name.lstrip('@'))
      @manager.config.leader = session.name
      @manager.config.save
      Tmux.bind_return_to_leader(session.name)
      {leader: session.name, return_key: Tmux::RETURN_TO_LEADER_KEY}
    end

    # The current Leader designation and the key that jumps to it.
    def leader
      {leader: @manager.config.leader, return_key: Tmux::RETURN_TO_LEADER_KEY}
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
        parent:    session.parent,
        state:     state_label(session),
        running:   session.running?,
        harness:   session.harness.program,
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
