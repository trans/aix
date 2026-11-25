require "json"
require "./tmux"
require "./bell"

module Aix
  # What the web page sends an agent, and what it shows of the agent's
  # input while it does.
  #
  # A message is pasted whole, then Enter, as a person would write it
  # and send it; but only when the agent's input box is empty, with the
  # cursor in it (the bell's check, `Bell.input_state`). Otherwise the
  # text would land in a draft, a menu or a permission prompt. Then the
  # page shows the agent's screen instead, and sends keys: what's typed
  # (`type`, no Enter) and single keys (`press`), for menus and prompts,
  # which aix needn't understand.
  module Sender
    # The keys the page offers, and tmux's names for them.
    KEYS = {
      "1" => "1", "2" => "2", "3" => "3", "4" => "4", "5" => "5",
      "Up" => "Up", "Down" => "Down", "Left" => "Left", "Right" => "Right",
      "Enter" => "Enter", "Escape" => "Escape", "Tab" => "Tab", "ShiftTab" => "BTab",
      "Space" => "Space", "Backspace" => "BSpace",
    }

    # How many lines of the agent's screen the page shows.
    SCREEN_LINES = 18

    # The agent's input, as the page shows it.
    #
    # - `mode`: `message` (its input box is empty: a message is sent
    #   whole), `keys` (it isn't: it's waiting on an answer, has a draft, or
    #   shows something else, so what's sent is keys), or `off` (it isn't
    #   running).
    # - `waiting`: it's waiting on the person mid-turn (Claude Code's
    #   status), on a permission prompt or a question.
    # - `screen`: the bottom of its screen.
    record Screen, mode : String, waiting : Bool, busy : Bool, screen : String do
      include JSON::Serializable
    end

    def self.screen(name : String) : Screen
      pane = Tmux.pane_info(name) || return Screen.new("off", false, false, "")
      input = Bell.input_state(pane)
      mode = input.prompt_empty ? "message" : "keys"
      Screen.new(mode, input.status == "waiting", input.status == "busy", bottom(name))
    rescue
      Screen.new("off", false, false, "")
    end

    # Send `text` as a message. Nil once it's sent, else why it wasn't.
    def self.message(name : String, text : String) : String?
      text = text.strip
      return "There's nothing to send." if text.empty?
      pane = Tmux.pane_info(name) || return "Its agent isn't running."
      input = Bell.input_state(pane)
      if input.status == "waiting"
        return "It's waiting on your answer to a prompt: answer it first (its screen is shown)."
      end
      return "Its input box isn't empty, or it's showing something else: see its screen." unless input.prompt_empty
      return "Its pane is in tmux's #{pane.mode}, which aix couldn't leave." unless ready(pane)
      Tmux.paste(pane.id, text)
      sleep 150.milliseconds
      Tmux.send_key(name, "Enter")
      nil
    end

    # Type `text` as keys, without Enter.
    def self.type(name : String, text : String) : String?
      return "There's nothing to type." if text.empty?
      pane = Tmux.pane_info(name) || return "Its agent isn't running."
      return "Its pane is in tmux's #{pane.mode}, which aix couldn't leave." unless ready(pane)
      Tmux.send_literal(name, text)
      nil
    end

    # Press one of KEYS.
    def self.press(name : String, key : String) : String?
      tmux_key = KEYS[key]? || return "aix doesn't send that key."
      pane = Tmux.pane_info(name) || return "Its agent isn't running."
      return "Its pane is in tmux's #{pane.mode}, which aix couldn't leave." unless ready(pane)
      Tmux.send_key(name, tmux_key)
      nil
    end

    # Out of any tmux mode (copy mode), where keys wouldn't reach the agent.
    private def self.ready(pane : Tmux::PaneInfo) : Bool
      pane.mode.empty? || Tmux.leave_mode(pane.id)
    end

    # The last SCREEN_LINES lines of its screen with anything on them.
    private def self.bottom(name : String) : String
      lines = Tmux.capture_pane(name).lines.map(&.rstrip)
      while lines.last?.try(&.empty?)
        lines.pop
      end
      lines.last(SCREEN_LINES).join("\n")
    end
  end
end
