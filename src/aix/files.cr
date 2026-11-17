require "random/secure"
require "./tmux"
require "./config"

module Aix
  # The file pane: a file browser (yazi) beside an agent, in its own pane
  # of the agent's window (the user's design, 2026-11-16). Each agent's
  # window has its own, so switching agents switches browsers, with
  # nothing to keep in step, and each stays where it was left. When yazi
  # quits, it writes the directory it was in to a file kept per agent
  # (`--cwd-file`), and the next file pane for that agent starts there: its
  # current browsing directory, kept across restarts.
  #
  # `F8` (`Tmux::FILES_KEY`) runs `aix files <window>`, which opens the
  # pane, or closes the one that's open. yazi there reads aix's own yazi
  # settings (`config_dir`), so it can be laid out for a pane beside an
  # agent without changing the person's yazi elsewhere.
  module Files
    PROGRAM = "yazi"

    # aix's yazi settings, written when missing; the person's to edit.
    # Checked against yazi 26.9.1 (2026-11-16).
    SETTINGS = <<-TOML
      # yazi's settings in aix's file pane (F8). aix writes this file only
      # when it's missing, so edit it freely. Your yazi elsewhere reads
      # ~/.config/yazi as usual; copy what you want from there to here.

      [mgr]
      # The columns: the parent directory, the current one, and a preview
      # of the selected file. The pane sits beside an agent, so no parent
      # column: the current directory, and the preview.
      ratio = [0, 1, 1]

      TOML

    # Where each agent's browsing directory is kept: a file per window
    # name, holding the path. Per person, in a folder only they can open.
    def self.dir : String
      base = ENV["XDG_STATE_HOME"]? || File.join(Path.home, ".local", "state")
      File.join(base, "aix", "browse")
    end

    # The file yazi writes agent `name`'s last directory to.
    def self.cwd_file(name : String) : String
      File.join(dir, name)
    end

    # Agent `name`'s browsing directory, if it has one that's still there.
    def self.remembered(name : String) : String?
      path = File.read(cwd_file(name)).strip
      Dir.exists?(path) ? path : nil
    rescue
      nil
    end

    # aix's own yazi configuration directory (`YAZI_CONFIG_HOME` in the
    # file pane), with its settings written if they're missing.
    def self.config_dir : String
      path = File.join(Config.config_dir, "yazi")
      settings = File.join(path, "yazi.toml")
      unless File.exists?(settings)
        Dir.mkdir_p(path)
        File.write(settings, SETTINGS)
      end
      path
    end

    # Open window `window`'s file pane, or close the one that's open. Run
    # from a key binding, so it says nothing on standard output (tmux
    # would show it); trouble goes to the status line.
    def self.toggle(window : String?) : Int32
      return 2 unless window
      panes = Tmux.window_panes(window)
      return 3 if panes.empty?
      if files = panes.find(&.files)
        close(files)
        panes.find(&.agent).try { |agent| Tmux.select_pane(agent.id) }
        return 0
      end
      unless Process.find_executable(PROGRAM)
        Tmux.display_message("aix: F8 opens #{PROGRAM}, which isn't installed")
        return 1
      end
      open(panes.find(&.agent) || panes.first)
      0
    rescue ex
      Tmux.display_message("aix: the file pane: #{ex.message}")
      1
    end

    private def self.open(agent : Tmux::WindowPane)
      start = remembered(agent.window) || agent.path
      Dir.mkdir_p(dir)
      File.chmod(dir, 0o700)
      # yazi's id, for closing it with its own quit (`close`).
      client = Random::Secure.rand(1_000_000_000_i64..999_999_999_999_i64).to_s
      command = [PROGRAM, "--client-id", client, "--cwd-file=#{cwd_file(agent.window)}", start]
      Tmux.open_files_pane(agent.id, start, command, {"YAZI_CONFIG_HOME" => config_dir}, client)
    end

    # Quit the file pane's yazi as `q` would, so it saves where it was:
    # through its own quit action (`ya emit-to`), which works in any of its
    # modes, else by its keys, and if it's still there after all, by
    # closing the pane.
    private def self.close(files : Tmux::WindowPane)
      files.client.presence.try do |client|
        Process.run("ya", ["emit-to", client, "quit"], output: Process::Redirect::Close,
          error: Process::Redirect::Close) rescue nil
      end
      return if gone?(files.id)
      Tmux.quit_by_keys(files.id)
      return if gone?(files.id)
      Tmux.kill_pane(files.id)
    end

    # Whether pane `id` closes within `within`.
    private def self.gone?(id : String, within : Time::Span = 1.second) : Bool
      deadline = Time.instant + within
      while Time.instant < deadline
        return true unless Tmux.pane_exists?(id)
        sleep 100.milliseconds
      end
      !Tmux.pane_exists?(id)
    end
  end
end
