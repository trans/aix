require "fancyline"
require "./session_manager"

module Aix
  class MetaConsole
    getter manager : SessionManager
    getter fancy : Fancyline

    def initialize(@manager : SessionManager)
      @fancy = Fancyline.new

      # Tab-complete session names and commands
      @fancy.autocomplete.add do |ctx, range, word, yielder|
        completions = yielder.call(ctx, range, word)
        commands = %w[add start list ls drop rename help quit exit]
        names = @manager.sessions.map(&.name)
        (commands + names).each do |c|
          completions << Fancyline::Completion.new(range, c) if c.starts_with?(word)
        end
        completions
      end
    end

    # Run the REPL. Returns :switch when user switches to a session,
    # or :quit when user wants to exit.
    def run : Symbol
      loop do
        line = @fancy.readline(prompt)
        return :quit unless line
        line = line.strip
        next if line.empty?

        result = execute(line)
        return result if result == :switch || result == :quit
      end
      :quit
    end

    private def prompt : String
      if session = @manager.active
        "#{session.name}: "
      else
        "aix: "
      end
    end

    private def execute(line : String) : Symbol
      parts = line.split(/\s+/, 2)
      cmd = parts[0].downcase
      args = parts[1]?

      case cmd
      when "list", "ls"
        cmd_list
      when "add"
        cmd_add(args)
      when "start"
        return cmd_start(args)
      when "drop"
        cmd_drop(args)
      when "rename"
        cmd_rename(args)
      when "help", "?"
        cmd_help
      when "quit", "exit"
        return :quit
      else
        # Try as a session name — switch focus to it
        if @manager.sessions.any? { |s| s.name == cmd }
          return cmd_switch(cmd)
        end
        puts "Unknown command: #{cmd}. Type 'help' for commands."
      end
      :continue
    end

    private def cmd_list
      if @manager.sessions.empty?
        puts "No sessions."
        return
      end
      @manager.sessions.each_with_index do |s, i|
        marker = (i == @manager.active_index) ? "*" : " "
        puts " #{marker} #{s.name}\t#{s.state}\t#{s.directory}"
      end
    end

    private def cmd_add(args : String?)
      unless args
        puts "Usage: add <directory> [name]"
        return
      end
      parts = args.split(/\s+/, 2)
      dir = parts[0]
      name = parts[1]? || File.basename(File.expand_path(parts[0]))
      begin
        @manager.add(name, dir)
        puts "Added '#{name}' (#{File.expand_path(dir)})"
      rescue ex
        puts "Error: #{ex.message}"
      end
    end

    private def cmd_switch(name : String) : Symbol
      begin
        session = @manager.switch(name)
        if session.running?
          :switch
        else
          puts "Session '#{name}' is cold. Type 'start' to spin it up."
          :continue
        end
      rescue ex
        puts "Error: #{ex.message}"
        :continue
      end
    end

    private def cmd_start(args : String?) : Symbol
      begin
        claude_args = args ? args.split(/\s+/) : [] of String
        session = @manager.start(claude_args)
        puts "Starting '#{session.name}'..."
        :switch
      rescue ex
        puts "Error: #{ex.message}"
        :continue
      end
    end

    private def cmd_drop(args : String?)
      unless args
        puts "Usage: drop <name>"
        return
      end
      name = args.strip
      begin
        @manager.remove(name)
        puts "Dropped '#{name}'."
      rescue ex
        puts "Error: #{ex.message}"
      end
    end

    private def cmd_rename(args : String?)
      unless args
        puts "Usage: rename <old> <new>"
        return
      end
      parts = args.split(/\s+/, 2)
      if parts.size < 2
        puts "Usage: rename <old> <new>"
        return
      end
      begin
        @manager.rename(parts[0], parts[1])
        puts "Renamed '#{parts[0]}' to '#{parts[1]}'."
      rescue ex
        puts "Error: #{ex.message}"
      end
    end

    private def cmd_help
      puts <<-HELP
      Commands:
        add <dir> [name]       Add a session (name defaults to dir basename)
        <name>                 Switch focus to a session
        start [args...]        Start Claude Code (passes args to claude)
        list / ls              List sessions
        drop <name>            Stop and remove a session
        rename <old> <new>     Rename a session
        help / ?               Show this help
        quit / exit            Exit AIX

      In a session, press F12 to return here.
      HELP
    end
  end
end
