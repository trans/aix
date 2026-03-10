require "./session"
require "./store"

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

    def add(name : String, directory : String) : Session
      dir = File.expand_path(directory)
      raise "Directory not found: #{dir}" unless Dir.exists?(dir)
      raise "Session '#{name}' already exists" if @sessions.any? { |s| s.name == name }

      session = Session.new(name, dir)
      @sessions << session
      persist
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
      raise "Session '#{session.name}' has stopped" if session.state == SessionState::Stopped
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
      persist
    end

    def rename(old_name : String, new_name : String)
      session = @sessions.find { |s| s.name == old_name }
      raise "No session named '#{old_name}'" unless session
      raise "Session '#{new_name}' already exists" if @sessions.any? { |s| s.name == new_name }
      session.name = new_name
      persist
    end

    def stop_all
      @sessions.each do |s|
        s.stop if s.running?
      end
    end

    private def find!(name : String) : Session
      @sessions.find { |s| s.name == name } || raise "No session named '#{name}'"
    end

    private def load_saved
      Store.load.each do |name, dir|
        next unless Dir.exists?(dir)
        next if @sessions.any? { |s| s.name == name }
        @sessions << Session.new(name, dir)
      end
    end

    private def persist
      entries = @sessions.map { |s| {s.name, s.directory} }
      Store.save(entries)
    end
  end
end
