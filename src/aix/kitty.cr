require "json"
require "./abduco"
require "./config"

module Aix
  # Agents in kitty tabs, as tmux windows otherwise (`Term`): each runs in
  # an abduco session (`Abduco`), which a tab attaches to, so the agent
  # goes on when its tab closes or kitty quits, and a new tab picks it up.
  # aix drives kitty by its remote control (`kitten @`), over the socket
  # kitty listens on:
  #
  #     allow_remote_control socket-only
  #     listen_on unix:${XDG_RUNTIME_DIR}/kitty
  #
  # (kitty adds its process id to the name: `kitty-<pid>`.) An agent's
  # window is marked with a user variable (`VAR`), and its tab labelled
  # `@name` over the title its program gives it, by a watcher kitty runs
  # (`watcher`).
  #
  # Checked with kitty 0.51.1 on 2026-11-25.
  module Kitty
    VAR = "aix_agent"

    # An agent's window, as `kitten @ ls` gives it. `focused`: it has the
    # keyboard, in the window in front.
    record Window, id : Int64, agent : String, title : String, focused : Bool

    class Unavailable < Exception
    end

    SETUP = "kitty's remote control isn't on, or kitty isn't running. In kitty.conf:\n" \
            "    allow_remote_control socket-only\n" \
            "    listen_on unix:${XDG_RUNTIME_DIR}/kitty\n" \
            "then start kitty again."

    @@socket : String? = nil

    # The socket of the kitty to use: the one aix runs in
    # (`KITTY_LISTEN_ON`), if it's still there; else, of the kittys
    # listening in the runtime folder, the one with aix's tabs, or else the
    # newest. Nil if none is.
    def self.socket : String?
      if (known = @@socket) && live?(known)
        return known
      end
      @@socket = find_socket
    end

    def self.available? : Bool
      !socket.nil?
    end

    private def self.find_socket : String?
      candidates = [] of String
      ENV["KITTY_LISTEN_ON"]?.try { |value| candidates << value.lchop("unix:") if value.starts_with?("unix:") }
      runtime = ENV["XDG_RUNTIME_DIR"]? || return candidates.find { |path| live?(path) }
      Dir.glob(File.join(runtime, "kitty-*")).sort_by { |path| -(File.info?(path).try(&.modification_time.to_unix) || 0_i64) }
        .each { |path| candidates << path unless candidates.includes?(path) }
      live = candidates.select { |path| live?(path) }
      return live.first? if live.size <= 1
      live.find { |path| !windows_at(path).empty? } || live.first?
    end

    # A socket of a kitty that's running: kitty's name for it ends in its
    # process id, which must be a kitty.
    private def self.live?(path : String) : Bool
      return false unless File.info?(path).try(&.type.socket?)
      pid = path.split('-').last.to_i64? || return true
      File.basename(File.read("/proc/#{pid}/comm").strip).starts_with?("kitty")
    rescue
      false
    end

    # Run `kitten @` against kitty, with `input` on its standard input.
    # Its output; raises with kitty's message if it fails.
    def self.rc(args : Array(String), input : String? = nil, to : String? = nil) : String
      path = to || socket || raise Unavailable.new(SETUP)
      output = IO::Memory.new
      error = IO::Memory.new
      stdin = input ? IO::Memory.new(input) : Process::Redirect::Close
      status = Process.run("kitten", ["@", "--to", "unix:#{path}"] + args, input: stdin, output: output, error: error)
      raise "kitten @ #{args.first?}: #{error.to_s.strip}" unless status.success?
      output.to_s
    end

    # The agents' windows, in every kitty window and tab.
    def self.windows : Array(Window)
      path = socket || return [] of Window
      windows_at(path)
    end

    private def self.windows_at(path : String) : Array(Window)
      parse_ls(rc(["ls"], to: path))
    rescue
      [] of Window
    end

    def self.parse_ls(json : String) : Array(Window)
      found = [] of Window
      JSON.parse(json).as_a.each do |os_window|
        os_focused = os_window["is_focused"]?.try(&.as_bool?) || false
        os_window["tabs"].as_a.each do |tab|
          tab_active = tab["is_active"]?.try(&.as_bool?) || false
          tab["windows"].as_a.each do |window|
            agent = window["user_vars"]?.try(&.as_h?).try(&.[VAR]?).try(&.as_s?) || next
            focused = os_focused && tab_active && (window["is_active"]?.try(&.as_bool?) || false)
            found << Window.new(window["id"].as_i64, agent, window["title"]?.try(&.as_s?) || "", focused)
          end
        end
      end
      found
    end

    # Agent `name`'s window, if a tab shows it.
    def self.window(name : String) : Window?
      windows.find { |window| window.agent == name }
    end

    # Start `command` for agent `name` in a new tab, in `directory`, in an
    # abduco session (`Abduco`), with `env` set. The tab stays when the
    # agent exits, at a shell, so its last words can be read.
    def self.start(name : String, directory : String, command : Array(String), env : Hash(String, String))
      clear(name)
      launch(name, directory, Abduco.create_command(name, command), env)
      # A moment for the program to start, as in tmux.
      sleep 500.milliseconds
    end

    # Show agent `name`, running in its abduco session, in a new tab, and
    # have it draw its screen there.
    def self.attach(name : String, directory : String = Path.home.to_s)
      launch(name, directory, Abduco.attach_command(name), {} of String => String)
      sleep 300.milliseconds
      Abduco.redraw(name)
    end

    private def self.launch(name : String, directory : String, command : Array(String), env : Hash(String, String))
      # Claude Code's own variables, from a kitty started inside one, would
      # tell the agent it's nested in another.
      clean = ["env", "-u", "CLAUDECODE", "-u", "CLAUDE_CODE_ENTRYPOINT"]
      Abduco.env.merge(env).each { |key, value| clean << "#{key}=#{value}" }
      rc(["launch", "--type=tab", "--keep-focus", "--hold", "--cwd=#{directory}",
          "--tab-title=@#{name}", "--var=#{VAR}=#{name}", "--watcher=#{watcher}", "--"] + clean + command)
    end

    # Clear what's left of an agent that has exited: its abduco session
    # (kept for a tab to collect) and its tab.
    private def self.clear(name : String)
      Abduco.kill(name) if Abduco.state(name).try(&.exited?)
      window(name).try { |window| close(window.id) }
    end

    # Bring agent `name`'s tab to the front, attaching one if none shows
    # it. False if it isn't running.
    def self.focus(name : String, directory : String = Path.home.to_s) : Bool
      unless window(name)
        return false unless Abduco.state(name).try(&.running?)
        attach(name, directory)
      end
      found = window(name) || return false
      rc(["focus-window", "--match", "id:#{found.id}"])
      true
    end

    # Stop agent `name`: its session ended, its tab closed.
    def self.stop(name : String)
      Abduco.kill(name)
      window(name).try { |window| close(window.id) }
    end

    def self.close(id : Int64)
      rc(["close-window", "--match", "id:#{id}"])
    rescue
      # Closed already.
    end

    # The text on window `id`'s screen, and where its cursor is (column and
    # row, from 0), with its colours and attributes as escape sequences
    # when `styled`.
    def self.screen(id : Int64, styled : Bool = false) : {Array(String), Int32, Int32}
      args = ["get-text", "--match", "id:#{id}", "--add-cursor"]
      args << "--ansi" if styled
      parse_screen(rc(args))
    end

    # `get-text --add-cursor`'s output: the screen's lines, then escape
    # sequences for the cursor, its position among them (`ESC[row;colH`,
    # from 1).
    def self.parse_screen(text : String) : {Array(String), Int32, Int32}
      at = text.rindex("\e[?25") || text.size
      tail = text[at..]
      position = tail.match(/\e\[(\d+);(\d+)H/)
      row = position.try(&.[1].to_i) || 1
      col = position.try(&.[2].to_i) || 1
      lines = text[0, at].split('\n')
      lines.pop if lines.last? == ""
      {lines, col - 1, row - 1}
    end

    # Type `text` into window `id` as it is. As a paste (bracketed, when
    # the program has asked for that, as Claude Code and Codex do) when
    # `paste`, so its line breaks are part of it rather than Enter.
    def self.send_text(id : Int64, text : String, paste : Bool = false)
      args = ["send-text", "--match", "id:#{id}", "--stdin"]
      args << "--bracketed-paste=auto" if paste
      rc(args, input: text)
    end

    # Press `key` in window `id`, named as tmux names keys (`Enter`,
    # `BSpace`, `C-c`).
    def self.send_key(id : Int64, key : String)
      rc(["send-key", "--match", "id:#{id}", key_name(key)])
    end

    TMUX_KEYS = {
      "Enter" => "enter", "Escape" => "escape", "BSpace" => "backspace", "Tab" => "tab",
      "BTab" => "shift+tab", "Space" => "space", "DC" => "delete", "Delete" => "delete",
      "PageUp" => "page_up", "PPage" => "page_up", "PageDown" => "page_down", "NPage" => "page_down",
    }

    def self.key_name(key : String) : String
      TMUX_KEYS[key]? || (key.starts_with?("C-") ? "ctrl+#{key[2..].downcase}" : key.size == 1 ? key : key.downcase)
    end

    # The watcher that labels an agent's tab `@name`, over the title its
    # program gives it, written where aix keeps its settings.
    def self.watcher : String
      path = File.join(Config.config_dir, "kitty", "aix_watcher.py")
      unless (File.read(path) rescue nil) == WATCHER
        Dir.mkdir_p(File.dirname(path))
        File.write(path, WATCHER)
      end
      path
    end

    WATCHER = <<-PYTHON
      # Written by aix, which replaces it: labels an agent's tab with its
      # handle, over the title its program gives it (two lines, with
      # tab_title_max_lines 2).


      def on_title_change(boss, window, data):
          name = window.user_vars.get('#{VAR}')
          tab = window.tabref() if name else None
          if tab is not None:
              title = data.get('title') or ''
              tab.set_title(f'@{name}\\n{title}' if title else f'@{name}')

      PYTHON
  end
end
