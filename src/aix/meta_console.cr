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
        commands = %w[add roots refresh start stop list ls send peek help quit exit]
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
      # Shell passthrough: lines starting with $
      if line.starts_with?("$")
        cmd_shell(line[1..].strip)
        return :continue
      end

      parts = line.split(/\s+/, 2)
      cmd = parts[0].downcase
      args = parts[1]?

      case cmd
      when "list", "ls"
        cmd_list
      when "add"
        cmd_add_root(args)
      when "roots"
        cmd_roots
      when "refresh"
        cmd_refresh
      when "start"
        return cmd_start(args)
      when "stop", "drop"
        cmd_stop(args)
      when "send"
        cmd_send(args)
      when "peek"
        cmd_peek(args)
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

    private def cmd_add_root(args : String?)
      unless args
        puts "Usage: add <root-path>"
        return
      end
      path = args.strip
      begin
        if @manager.add_root(path)
          puts "Added root '#{path}'. #{@manager.sessions.size} project(s) discovered."
        else
          puts "Root '#{path}' is already configured."
        end
      rescue ex
        puts "Error: #{ex.message}"
      end
    end

    private def cmd_roots
      roots = @manager.config.roots
      if roots.empty?
        puts "No roots configured. Add one with: add <root-path>"
        return
      end
      puts "Roots (scan depth #{@manager.config.depth}):"
      roots.each { |r| puts "  #{r}" }
    end

    private def cmd_refresh
      @manager.refresh
      puts "Rescanned. #{@manager.sessions.size} project(s) available."
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

    private def cmd_stop(args : String?)
      name = args.try(&.strip)
      name = @manager.active.try(&.name) if name.nil? || name.empty?
      unless name
        puts "Usage: stop <name>"
        return
      end
      begin
        @manager.stop(name)
        puts "Stopped '#{name}'."
      rescue ex
        puts "Error: #{ex.message}"
      end
    end

    private def cmd_send(args : String?)
      unless args
        puts "Usage: send <text>"
        return
      end
      session = @manager.active
      unless session && session.running?
        puts "No running session. Switch to one first."
        return
      end
      Tmux.send_keys(session.name, args)
    end

    private def cmd_peek(args : String?)
      session = @manager.active
      unless session && session.running?
        puts "No running session. Switch to one first."
        return
      end
      lines = args.try(&.strip.to_i?)
      puts Tmux.capture_pane(session.name, lines)
    end

    private def cmd_shell(cmd : String)
      if cmd.empty?
        puts "Usage: $ <command>"
        return
      end
      dir = @manager.active.try(&.directory)
      Process.run("sh", ["-c", cmd],
        chdir: dir,
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
    end

    private def cmd_help
      puts <<-HELP
      Commands:
        add <root-path>        Add a root path scanned for projects (dirs with .ai/)
        roots                  List configured root paths
        refresh                Rescan roots for projects
        <name>                 Switch focus to a project
        start [args...]        Start Claude Code (passes args to claude)
        list / ls              List projects
        stop <name>            Stop a running session
        send <text>            Send keystrokes to active session
        peek [lines]           View active session output
        $ <command>            Run a shell command
        help / ?               Show this help
        quit / exit            Exit AIX

      Projects are discovered automatically: any directory under a
      configured root that contains a .ai/ directory becomes a project.

      In a session, press F12 to return here.
      HELP
    end
  end
end
