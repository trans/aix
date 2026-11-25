module Aix
  # abduco keeps an agent running when its kitty tab closes, or kitty quits
  # (`Kitty`): it holds the agent's terminal, and a tab shows it by
  # attaching. Unlike tmux it draws nothing of its own and passes the
  # program's output through as it is, its titles and status reports
  # included.
  #
  # aix's sessions are kept apart from any of the person's own, in a folder
  # of aix's (`dir`), each named for its agent.
  #
  # Checked with abduco 0.6 on 2026-11-25.
  module Abduco
    PROGRAM = "abduco"

    # The folder abduco keeps aix's sessions in (`ABDUCO_SOCKET_DIR`); the
    # sockets go below it, in `abduco/<user>/`.
    def self.dir : String
      File.join(ENV["XDG_RUNTIME_DIR"]? || Dir.tempdir, "aix")
    end

    # The environment that puts abduco's sessions in `dir`.
    def self.env : Hash(String, String)
      {"ABDUCO_SOCKET_DIR" => dir}
    end

    enum State
      # Its program is running, with a tab attached or not.
      Running
      # Its program has exited, and no tab was attached to take the news:
      # abduco keeps the session until one does.
      Exited
    end

    # The command that starts `command` in a session named `name`.
    def self.create_command(name : String, command : Array(String)) : Array(String)
      [PROGRAM, "-c", name] + command
    end

    # The command that attaches a tab to the session `name`.
    def self.attach_command(name : String) : Array(String)
      [PROGRAM, "-a", name]
    end

    # aix's sessions and their states, from abduco's list. Its lines after
    # the first are a mark (`*` attached, `+` exited, else a space), the
    # time it started and its name, separated by tabs.
    def self.sessions : Hash(String, State)
      Dir.mkdir_p(dir, 0o700)
      output = IO::Memory.new
      Process.run(PROGRAM, env: env, output: output, error: Process::Redirect::Close)
      parse_list(output.to_s)
    rescue
      {} of String => State
    end

    def self.parse_list(text : String) : Hash(String, State)
      text.lines.skip(1).compact_map { |line|
        next if line.empty?
        name = line.split('\t').last.strip
        next if name.empty?
        {name, line.starts_with?('+') ? State::Exited : State::Running}
      }.to_h
    end

    def self.state(name : String) : State?
      sessions[name]?
    end

    # Each running session's agent process, by name: the child of the
    # abduco process serving it (which keeps the command line it was
    # started with, `abduco -c <name> …`, as the one that started it did).
    def self.agent_pids : Hash(String, Int64)
      pids = {} of String => Int64
      each_server do |name, server|
        child = children(server).first? || next
        pids[name] = child
      end
      pids
    end

    def self.agent_pid(name : String) : Int64?
      agent_pids[name]?
    end

    # Make the agent draw its screen again, for a tab that has just
    # attached: abduco keeps no copy of it, and a full-screen program
    # redraws when its terminal's size changes, so it's changed by a row
    # and back. A program drawing line by line just goes on.
    def self.redraw(name : String) : Bool
      pid = agent_pid(name) || return false
      tty = File.readlink("/proc/#{pid}/fd/0")
      return false unless tty.starts_with?("/dev/pts/")
      size = IO::Memory.new
      return false unless Process.run("stty", ["-F", tty, "size"], output: size).success?
      rows = size.to_s.split.first?.try(&.to_i?) || return false
      Process.run("stty", ["-F", tty, "rows", (rows - 1).to_s])
      sleep 100.milliseconds
      Process.run("stty", ["-F", tty, "rows", rows.to_s]).success?
    rescue
      false
    end

    # End the session `name`: its agent is hung up on, as when a terminal
    # closes, and abduco's process with it if it stays.
    def self.kill(name : String)
      servers = [] of Int64
      each_server { |session, server| servers << server if session == name }
      servers.each do |server|
        children(server).each { |child| signal(child, Signal::HUP) }
      end
      sleep 300.milliseconds
      servers.each { |server| signal(server, Signal::TERM) }
    end

    # abduco's processes serving aix's sessions (the ones with `dir` in
    # their environment), with their session names. A tab's attached
    # abduco has no child; the serving one has the agent.
    private def self.each_server(&)
      Dir.each_child("/proc") do |entry|
        pid = entry.to_i64? || next
        args = File.read("/proc/#{pid}/cmdline").split('\0', remove_empty: true) rescue next
        next unless args.size >= 3 && File.basename(args[0]) == PROGRAM && {"-c", "-A", "-n"}.includes?(args[1])
        next if children(pid).empty?
        next unless ours?(pid)
        yield args[2], pid
      end
    end

    private def self.ours?(pid : Int64) : Bool
      File.read("/proc/#{pid}/environ").split('\0').includes?("ABDUCO_SOCKET_DIR=#{dir}")
    rescue
      false
    end

    private def self.children(pid : Int64) : Array(Int64)
      File.read("/proc/#{pid}/task/#{pid}/children").split.compact_map(&.to_i64?)
    rescue
      [] of Int64
    end

    private def self.signal(pid : Int64, signal : Signal)
      Process.signal(signal, pid)
    rescue
      # Gone already.
    end
  end
end
