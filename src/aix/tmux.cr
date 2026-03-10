module Aix
  # Thin wrapper around tmux CLI commands.
  module Tmux
    SESSION = "aix"

    # Ensure the aix tmux session exists. Creates it if not.
    # If no windows exist yet, creates a placeholder that new_window will replace.
    def self.ensure_session
      return if session_exists?
      # Start tmux server with clean env (no Claude nesting vars)
      result = Process.run("env", ["-u", "CLAUDECODE", "-u", "CLAUDE_CODE_ENTRYPOINT",
                                   "tmux", "new-session", "-d", "-s", SESSION,
                                   "-x", "#{cols}", "-y", "#{rows}"],
                           error: Process::Redirect::Pipe)
      raise "tmux new-session: failed" unless result.success?
      # Bind F12 to detach (prefix-free, aix session only)
      run("bind-key", "-n", "F12", "detach-client")
    end

    def self.session_exists? : Bool
      Process.run("tmux", ["has-session", "-t", SESSION],
        error: Process::Redirect::Close).success?
    end

    def self.window_exists?(name : String) : Bool
      output = IO::Memory.new
      result = Process.run("tmux", ["list-windows", "-t", SESSION, "-F", "\#{window_name}"],
        output: output, error: Process::Redirect::Close)
      return false unless result.success?
      output.to_s.split('\n').any? { |w| w.strip == name }
    end

    # Create a new window running claude with the given args.
    def self.new_window(name : String, directory : String, args : Array(String) = [] of String)
      ensure_session
      tmux_args = ["new-window", "-t", SESSION, "-n", name, "-c", directory, "--", "claude"] + args
      err = IO::Memory.new
      result = Process.run("tmux", tmux_args, error: err)
      raise "tmux new-window: #{err.to_s.strip}" unless result.success?
      # Give the window a moment to initialize
      sleep 500.milliseconds
    end

    # Kill a window.
    def self.kill_window(name : String)
      run("kill-window", "-t", "#{SESSION}:#{name}")
    end

    # Select a window (make it active).
    def self.select_window(name : String)
      run("select-window", "-t", "#{SESSION}:#{name}")
    end

    # Attach to the aix session. Blocks until the user detaches.
    def self.attach
      Process.run("tmux", ["attach", "-t", SESSION],
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
    end

    # Rename a window.
    def self.rename_window(old_name : String, new_name : String)
      run("rename-window", "-t", "#{SESSION}:#{old_name}", new_name)
    end

    # List window names in the aix session.
    def self.list_windows : Array(String)
      output = capture("list-windows", "-t", SESSION, "-F", "#W")
      output.split('\n').reject(&.empty?)
    rescue
      [] of String
    end

    # Clean up — kill the whole session.
    def self.kill_session
      run("kill-session", "-t", SESSION) if session_exists?
    end

    private def self.rows : Int32
      `tput lines`.strip.to_i rescue 24
    end

    private def self.cols : Int32
      `tput cols`.strip.to_i rescue 80
    end

    private def self.run(*args : String)
      result = Process.run("tmux", args.to_a,
        error: Process::Redirect::Pipe)
      unless result.success?
        raise "tmux #{args.first}: failed"
      end
    end

    private def self.capture(*args : String) : String
      output = IO::Memory.new
      result = Process.run("tmux", args.to_a,
        output: output,
        error: Process::Redirect::Close)
      raise "tmux #{args.first}: failed" unless result.success?
      output.to_s
    end
  end
end
