require "./session"
require "./store"
require "./tmux"

module Aix
  class SessionManager
    getter sessions : Array(Session)
    property active_index : Int32 = -1

    def initialize
      @sessions = [] of Session
      load_saved
    end

    def active : Session?
      return nil if @active_index < 0 || @active_index >= @sessions.size
      @sessions[@active_index]
    end

    def find(name : String) : Session?
      @sessions.find { |s| s.name == name }
    end

    def add(name : String, directory : String) : Session
      dir = self.class.expand_directory(directory)
      raise "Directory not found: #{dir}" unless Dir.exists?(dir)
      raise "Session '#{name}' already exists" if @sessions.any? { |s| s.name == name }

      active_session = active
      session = Session.new(name, dir)
      @sessions << session
      sort_sessions!(active_session)
      persist_sessions
      session
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

    def remove(name : String)
      idx = @sessions.index { |s| s.name == name }
      raise "No session named '#{name}'" unless idx
      session = @sessions[idx]
      session.stop if session.running?
      @sessions.delete_at(idx)
      if @sessions.empty?
        @active_index = -1
      elsif @active_index >= @sessions.size
        @active_index = @sessions.size - 1
      end
      persist_sessions
    end

    def rename(old_name : String, new_name : String)
      active_session = active
      session = @sessions.find { |s| s.name == old_name }
      raise "No session named '#{old_name}'" unless session
      raise "Session '#{new_name}' already exists" if @sessions.any? { |s| s.name == new_name }
      Tmux.rename_window(old_name, new_name) if session.running?
      session.name = new_name
      sort_sessions!(active_session)
      persist_sessions
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

    private def load_saved
      Store.load.each do |name, dir, claude_id|
        next unless Dir.exists?(dir)
        next if @sessions.any? { |s| s.name == name }
        @sessions << Session.new(name, dir, claude_id)
      end
      sort_sessions!
    end

    def persist_sessions
      entries = @sessions.map { |s| {s.name, s.directory, s.claude_session_id} }
      Store.save(entries)
    end

    private def sort_sessions!(active_session : Session? = nil)
      @sessions.sort_by!(&.name.downcase)
      @active_index = @sessions.index(active_session) || -1 if active_session
    end
  end
end
