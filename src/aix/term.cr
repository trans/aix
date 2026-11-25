require "./tmux"
require "./kitty"
require "./abduco"
require "./config"

module Aix
  # Where agents run, for the rest of aix: windows in aix's tmux session,
  # or tabs in kitty, each kept alive by abduco (`Kitty`). The config's
  # `terminal` chooses (`AIX_TERMINAL` overrides it, for a test); tmux is
  # the default.
  #
  # A pane, the bell's unit, is a tmux pane or a kitty window; either way
  # `Tmux::PaneInfo` describes it, its `id` being kitty's window id there.
  module Term
    @@kitty : Bool? = nil

    def self.kitty? : Bool
      if (known = @@kitty).nil?
        choice = ENV["AIX_TERMINAL"]? || Config.load.terminal
        @@kitty = choice == "kitty"
      else
        known
      end
    end

    # Ready to run agents: tmux's session made, or kitty reachable.
    def self.ensure
      if kitty?
        raise Kitty::Unavailable.new(Kitty::SETUP) unless Kitty.available?
      else
        Tmux.ensure_session
      end
    end

    # Whether agent `name` is running.
    def self.running?(name : String) : Bool
      kitty? ? Abduco.state(name).try(&.running?) || false : Tmux.window_exists?(name)
    end

    # Whether agent `name` has exited and left something to clear: tmux's
    # window kept with its last screen, or in kitty its abduco session or
    # its tab.
    def self.exited?(name : String) : Bool
      if kitty?
        Abduco.state(name).try(&.exited?) || (!running?(name) && !Kitty.window(name).nil?)
      else
        Tmux.window_dead?(name)
      end
    end

    # Start `command` for agent `name` in `directory`, with `env`. In tmux
    # the window is made; in kitty a tab, behind the one in front (`focus`
    # brings it forward).
    def self.start(name : String, directory : String, command : Array(String), env : Hash(String, String))
      kitty? ? Kitty.start(name, directory, command, env) : Tmux.new_window(name, directory, command, env)
    end

    # Stop agent `name`, closing its window or tab.
    def self.stop(name : String)
      kitty? ? Kitty.stop(name) : Tmux.kill_window(name)
    end

    # Bring agent `name` to the front: tmux's window selected, kitty's tab
    # focused (a tab attached first if none shows it).
    def self.focus(name : String, directory : String = Path.home.to_s)
      kitty? ? Kitty.focus(name, directory) : Tmux.select_window(name)
    end

    # Agent `name`'s pane, as the bell reads it; nil if it isn't running,
    # or (in kitty) no tab shows it, so its screen can't be read.
    def self.pane_info(name : String) : Tmux::PaneInfo?
      return Tmux.pane_info(name) unless kitty?
      return nil unless running?(name)
      window = Kitty.window(name) || return nil
      pid = Abduco.agent_pid(name) || return nil
      _, x, y = Kitty.screen(window.id)
      Tmux::PaneInfo.new(window.id.to_s, pid, window.focused, x, y)
    rescue
      nil
    end

    # Agent `name`'s screen as text, with the last screen of one that has
    # exited (tmux), or nil if none can be read.
    def self.screen(name : String) : String?
      return Tmux.capture_screen(name) unless kitty?
      window = Kitty.window(name) || return nil
      Kitty.screen(window.id)[0].join("\n") + "\n"
    rescue
      nil
    end

    # Agent `name`'s screen, and with `lines`, that much scrollback (tmux).
    def self.capture(name : String, lines : Int32? = nil) : String
      return Tmux.capture_pane(name, lines) unless kitty?
      screen(name) || raise "'#{name}' has no tab in kitty"
    end

    # Lines `from` to `to` of a pane's screen (0 is the top), a line
    # outside it empty.
    def self.pane_lines(pane_id : String, from : Int32, to : Int32) : Array(String)
      return Tmux.pane_lines(pane_id, from, to) unless kitty?
      lines = Kitty.screen(pane_id.to_i64)[0]
      (from..to).map { |y| y >= 0 ? lines[y]? || "" : "" }
    end

    # Line `y` of a pane's screen, with its colours and attributes.
    def self.pane_line_styled(pane_id : String, y : Int32) : String
      return Tmux.pane_line_styled(pane_id, y) unless kitty?
      Kitty.screen(pane_id.to_i64, styled: true)[0][y]? || ""
    end

    # Take a pane out of a tmux mode it's in (copy mode). kitty has none
    # that keeps keys from the program.
    def self.leave_mode(pane_id : String) : Bool
      kitty? ? true : Tmux.leave_mode(pane_id)
    end

    # Type `text` into a pane, then press Enter, a moment later so the
    # program doesn't take it as part of a paste.
    def self.type_line(pane_id : String, text : String)
      return Tmux.type_line(pane_id, text) unless kitty?
      Kitty.send_text(pane_id.to_i64, text)
      sleep 150.milliseconds
      Kitty.send_key(pane_id.to_i64, "Enter")
    end

    # Paste `text` into a pane, its line breaks part of it.
    def self.paste(pane_id : String, text : String)
      kitty? ? Kitty.send_text(pane_id.to_i64, text, paste: true) : Tmux.paste(pane_id, text)
    end

    # Type `text` into agent `name`, then Enter.
    def self.send_line(name : String, text : String)
      return Tmux.send_keys(name, text) unless kitty?
      type_line(window_id(name), text)
    end

    # Type `text` into agent `name`, without Enter.
    def self.send_literal(name : String, text : String)
      kitty? ? Kitty.send_text(window_id(name).to_i64, text) : Tmux.send_literal(name, text)
    end

    # Press `key` (tmux's name for it) in agent `name`.
    def self.send_key(name : String, key : String)
      kitty? ? Kitty.send_key(window_id(name).to_i64, key) : Tmux.send_key(name, key)
    end

    private def self.window_id(name : String) : String
      (Kitty.window(name) || raise "'#{name}' has no tab in kitty").id.to_s
    end

    # The running agents with their processes.
    def self.agent_pids : Array({String, Int64})
      kitty? ? Abduco.agent_pids.to_a : Tmux.window_pids
    end

    # Each agent's title, as its program gives it.
    def self.titles : Hash(String, String)
      return Tmux.agent_titles unless kitty?
      Kitty.windows.each_with_object({} of String => String) do |window, titles|
        titles[window.agent] = window.title unless window.title.empty?
      end
    end

    # When the person last pressed a key where aix's agents are, if that
    # can be known (tmux; kitty doesn't say).
    def self.last_activity : Time?
      kitty? ? nil : Tmux.last_client_activity
    end

    # Show a passing message where the person sees aix's agents (tmux's
    # status line; kitty has no such place).
    def self.message(text : String)
      Tmux.display_message(text) unless kitty?
    end
  end
end
