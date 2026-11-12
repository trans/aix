require "./tmux"
require "./harness"

module Aix
  # Rings an agent's doorbell: types a fixed notice into its tmux pane, the
  # way the user would ("you have mail"), but only when that's safe.
  #
  # The notice never carries a message (the user's rule, 2026-11-10): it
  # only says where mail is waiting, and the agent reads the mail itself as
  # a file. Typing is safe only at an empty prompt of an idle session. Into
  # anything else, keys do harm: at a dialog, Enter picks its default (the
  # folder-trust question's is "No, exit"); into the user's half-written
  # draft, they'd join it and send it. So the bell rings only when:
  #
  # 1. Claude Code's session file says `idle`, or `shell` (idle with a
  #    background command running). There's none during a startup dialog,
  #    and it says `busy` or `waiting` mid-turn, when the Stop hook tells
  #    the session anyway;
  # 2. the user isn't typing in that pane right now; and
  # 3. the cursor is in the input box (the line between two horizontal
  #    rules, where menus that use the same mark aren't) and the box is
  #    empty: nothing but the prompt mark before the cursor (Claude Code's
  #    hint text sits after it).
  #
  # Checked against Claude Code 2.1.322 on 2026-11-11.
  module Bell
    NOTICE = "You have mail in .ai/mail/inbox/."

    # The user counts as typing in a pane they've pressed a key in this
    # recently.
    USER_ACTIVE_WITHIN = 20.seconds

    # A session rung this recently isn't rung again: it hasn't had time to
    # go busy yet.
    RECENTLY_RUNG = 10.seconds

    PROMPT_MARKS = {"❯", ">"}

    enum Result
      # The notice was typed.
      Rung
      # In a turn, or waiting on the user mid-turn: the Stop hook tells it.
      Busy
      # It has a channel (dot-ai's), which tells it.
      Channel
      # It can't be told now. Try again later.
      Held
      # No such session is open in aix.
      NotOpen

      # `aix tell`'s exit status, as dot-ai's spec gives a runner's `tell`.
      def exit_status : Int32
        case self
        when NotOpen then 3
        when Held    then 4
        else              0
        end
      end
    end

    # Ring the bell for the agent in tmux window `window`. Returns what
    # happened, and why.
    def self.ring(window : String, text : String = NOTICE) : {Result, String}
      pane = Tmux.pane_info(window)
      return {Result::NotOpen, "no window '#{window}' in aix"} unless pane

      if Harness.channel?(Harness.process_args(pane.pid))
        return {Result::Channel, "started with a channel, which tells it"}
      end
      return {Result::Rung, "rung moments ago"} if recently_rung?(window)

      session = Harness.claude_session_in_pane(pane.pid)
      lines = Tmux.pane_lines(pane.id, pane.cursor_y - 1, pane.cursor_y + 1)
      result, reason = decide(
        status: session.try(&.status),
        user_typing: pane.focused && user_active?,
        prompt_empty: prompt_empty?(lines, pane.cursor_x))
      return {result, reason} unless result.rung?

      Tmux.type_line(pane.id, text)
      mark_rung(window)
      {Result::Rung, "typed the notice"}
    end

    # Whether to ring, from what the guards found.
    def self.decide(status : String?, user_typing : Bool, prompt_empty : Bool) : {Result, String}
      case status
      when "idle", "shell"
        # Go on to the other guards. `shell` is an idle session with a
        # command it started in the background still running (a dev
        # server, say); dot-ai's channel counts it as idle too.
      when "busy"
        return {Result::Busy, "in a turn: the Stop hook will tell it"}
      when "waiting"
        return {Result::Busy, "waiting on the user mid-turn: the Stop hook will tell it"}
      when nil
        return {Result::Held, "no Claude Code status for it (a startup dialog, or not Claude Code)"}
      else
        return {Result::Held, "Claude Code says '#{status}', not idle"}
      end
      return {Result::Held, "the user is typing in its pane"} if user_typing
      return {Result::Held, "its input box isn't empty"} unless prompt_empty
      {Result::Rung, "idle at an empty prompt"}
    end

    # Whether the cursor is at an empty prompt, from the pane's lines above,
    # at and below the cursor. The cursor's line has only the prompt mark
    # (and any box border) before the cursor, and it sits between two rules,
    # as Claude Code's input box does.
    def self.prompt_empty?(lines : Array(String), cursor_x : Int32) : Bool
      return false unless lines.size == 3
      above, line, below = lines
      return false unless rule?(above) && rule?(below)
      before = line.each_char.first({cursor_x, 0}.max).join
      # Claude Code puts a no-break space after its mark; `strip` takes any
      # Unicode space.
      PROMPT_MARKS.includes?(before.strip.strip("│┃|").strip)
    end

    # A horizontal rule: a line of box-drawing dashes (or a box's top or
    # bottom edge).
    private def self.rule?(line : String) : Bool
      edge = line.strip
      !edge.empty? && edge.each_char.all? { |char| "─━═╭╮╰╯┌┐└┘".includes?(char) }
    end

    private def self.user_active? : Bool
      last = Tmux.last_client_activity
      !!last && Time.utc - last < USER_ACTIVE_WITHIN
    end

    # Where aix keeps what lasts only while the machine is up.
    def self.runtime_dir : String
      File.join(ENV["XDG_RUNTIME_DIR"]? || Dir.tempdir, "aix")
    end

    # When each window was last rung, kept in a file per window so `aix
    # tell` and the bridge, separate processes, don't both ring at once.
    private def self.stamp(window : String) : String
      File.join(runtime_dir, "rung", window)
    end

    private def self.recently_rung?(window : String) : Bool
      info = File.info?(stamp(window))
      !!info && Time.utc - info.modification_time < RECENTLY_RUNG
    end

    private def self.mark_rung(window : String)
      path = stamp(window)
      Dir.mkdir_p(File.dirname(path))
      File.touch(path)
    rescue
      # Without the stamp a second ring may follow; the session's busy
      # status stops any after that.
    end
  end
end
