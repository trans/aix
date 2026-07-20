require "./session"
require "./store"
require "./tmux"
require "./config"

module Aix
  class SessionManager
    getter sessions : Array(Session)
    getter config : Config
    property active_index : Int32 = -1

    def initialize
      @sessions = [] of Session
      @config = Config.load
      refresh
    end

    def active : Session?
      return nil if @active_index < 0 || @active_index >= @sessions.size
      @sessions[@active_index]
    end

    def find(name : String) : Session?
      @sessions.find { |s| s.name == name }
    end

    # Re-scan the configured roots and rebuild the session list. Existing
    # session objects are preserved (keyed by directory) so running windows
    # and captured Claude IDs survive a refresh; the resume-id cache is
    # overlaid onto newly discovered projects.
    def refresh
      active_session = active
      discovered = @config.discover
      by_dir = @sessions.index_by(&.directory)
      resume = resume_ids

      @sessions = discovered.map do |name, dir|
        if existing = by_dir[dir]?
          existing.name = name
          existing
        else
          Session.new(name, dir, resume[dir]?)
        end
      end

      sort_sessions!(active_session)
    end

    # Add a root path to the config and re-discover. Returns true if the
    # root was newly added.
    def add_root(path : String) : Bool
      added = @config.add_root(path)
      refresh if added
      added
    end

    # Remove a root path from the config and re-discover. Returns true if a
    # root was removed.
    def remove_root(path : String) : Bool
      removed = @config.remove_root(path)
      refresh if removed
      removed
    end

    def switch(name : String) : Session
      idx = @sessions.index { |s| s.name == name }
      raise "No session named '#{name}'" unless idx
      @active_index = idx
      @sessions[idx]
    end

    def start(args : Array(String) = [] of String) : Session
      session = active
      raise "No active session" unless session
      raise "Session '#{session.name}' is already running" if session.running?
      session.start(args)
      session
    end

    def start(name : String, args : Array(String) = [] of String) : Session
      session = find(name)
      raise "No session named '#{name}'" unless session
      raise "Session '#{session.name}' is already running" if session.running?
      session.start(args)
      session
    end

    # Stop a session's tmux window. The project stays in the list (it is
    # owned by discovery); it simply returns to a cold/stopped state.
    def stop(name : String)
      session = find(name)
      raise "No session named '#{name}'" unless session
      session.stop if session.running?
    end

    def stop_all
      @sessions.each do |s|
        s.stop if s.running?
      end
    end

    def self.expand_directory(directory : String) : String
      path = if directory == "~"
               Path.home
             elsif directory.starts_with?("~/")
               File.join(Path.home, directory[2..])
             else
               directory
             end
      File.expand_path(path)
    end

    # Persist the resume-id cache (Claude session IDs keyed by directory).
    def persist_sessions
      entries = @sessions.map { |s| {s.name, s.directory, s.claude_session_id} }
      Store.save(entries)
    end

    # Claude session IDs from the persisted cache, keyed by directory.
    private def resume_ids : Hash(String, String?)
      cache = {} of String => String?
      Store.load.each { |_name, dir, cid| cache[dir] = cid }
      cache
    end

    private def sort_sessions!(active_session : Session? = nil)
      @sessions.sort_by!(&.name.downcase)
      @active_index = @sessions.index(active_session) || -1 if active_session
    end
  end
end
