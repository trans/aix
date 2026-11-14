require "./tmux"
require "./harness"
require "./runner"

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
  # 1. the session is idle. For Claude Code, its session file says `idle`,
  #    or `shell` (idle with a background command running); there's none
  #    during a startup dialog, and it says `busy` or `waiting` mid-turn,
  #    when the Stop hook tells the session anyway. For Codex, which keeps
  #    no such file, dot-ai's record of the session says `idle`; its hooks
  #    write the record at the session's first prompt, so until then the
  #    bell holds;
  # 2. the user isn't typing in that pane right now; and
  # 3. the cursor is in the input box, and the box is empty. Claude Code's
  #    is the line between two horizontal rules (where menus that use the
  #    same mark aren't), with nothing but the prompt mark before the
  #    cursor (its hint text sits after it). Codex's is the line with its
  #    mark `›` before the cursor and nothing after it but dim text (its
  #    placeholder, "Ask Codex to do anything"); a draft isn't dim, and
  #    neither is a menu's entry after the same mark.
  #
  # Checked against Claude Code 2.1.322 on 2026-11-11, and Codex 0.167.2
  # on 2026-11-13.
  module Bell
    NOTICE = "You have mail in .ai/mail/inbox/."

    # The user counts as typing in a pane they've pressed a key in this
    # recently.
    USER_ACTIVE_WITHIN = 20.seconds

    # A session rung this recently isn't rung again: it hasn't had time to
    # go busy yet.
    RECENTLY_RUNG = 10.seconds

    PROMPT_MARKS = {"❯", ">"}
    CODEX_MARK   = "›"

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

      record = Runner.record_in_pane(pane.pid)
      if codex?(pane.pid, record)
        status = record.try(&.state)
        prompt_empty = codex_prompt_empty?(Tmux.pane_line_styled(pane.id, pane.cursor_y), pane.cursor_x)
        unknown = "no dot-ai record for it yet (Codex's hooks write one at its first prompt)"
      else
        status = Harness.claude_session_in_pane(pane.pid).try(&.status)
        lines = Tmux.pane_lines(pane.id, pane.cursor_y - 1, pane.cursor_y + 1)
        prompt_empty = prompt_empty?(lines, pane.cursor_x)
        unknown = "no Claude Code status for it (a startup dialog, or not Claude Code)"
      end
      result, reason = decide(
        status: status,
        user_typing: pane.focused && user_active?,
        prompt_empty: prompt_empty,
        unknown: unknown)
      return {result, reason} unless result.rung?

      Tmux.type_line(pane.id, text)
      mark_rung(window)
      {Result::Rung, "typed the notice"}
    end

    # Whether the pane runs Codex: its own process is `codex`, or dot-ai's
    # record of the session in it says so.
    def self.codex?(pane_pid : Int64, record : Runner::SessionRecord?) : Bool
      program = Harness.process_args(pane_pid).first?.try { |arg| File.basename(arg) }
      program == Harness::Kind::Codex.program || record.try(&.agent) == Harness::Kind::Codex.program
    end

    # Whether to ring, from what the guards found. `status` is the
    # session's own (Claude Code's) or its record's (dot-ai's, for Codex),
    # and `unknown` says why there's none.
    def self.decide(status : String?, user_typing : Bool, prompt_empty : Bool,
                    unknown : String = "no status for it") : {Result, String}
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
        return {Result::Held, unknown}
      else
        return {Result::Held, "its status is '#{status}', not idle"}
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

    # Whether Codex's input line is empty, from the cursor's line with its
    # styles (`Tmux.pane_line_styled`): Codex's mark and a space before the
    # cursor, and nothing else on the line that isn't dim.
    def self.codex_prompt_empty?(line : String, cursor_x : Int32) : Bool
      text, solid = unstyle(line)
      before = text.each_char.first({cursor_x, 0}.max).join
      before.strip == CODEX_MARK && solid.strip == CODEX_MARK
    end

    # A styled line's text, and the part of it that isn't dim (SGR 2).
    # Other escape sequences are dropped.
    def self.unstyle(line : String) : {String, String}
      text = String::Builder.new
      solid = String::Builder.new
      dim = false
      chars = line.chars
      i = 0
      while i < chars.size
        char = chars[i]
        if char == '\e' && chars[i + 1]? == '['
          j = i + 2
          while j < chars.size && !('@'..'~').includes?(chars[j])
            j += 1
          end
          dim = sgr_dim(chars[i + 2...j].join, dim) if chars[j]? == 'm'
          i = j + 1
        elsif char == '\e' && chars[i + 1]? == ']'
          # An OSC sequence (a link, say), to BEL or ST.
          j = i + 2
          while j < chars.size && chars[j] != '\a' && !(chars[j] == '\e' && chars[j + 1]? == '\\')
            j += 1
          end
          i = chars[j]? == '\a' ? j + 1 : j + 2
        elsif char == '\e'
          i += 2
        else
          text << char
          solid << char unless dim
          i += 1
        end
      end
      {text.to_s, solid.to_s}
    end

    # Whether text is dim after an SGR sequence with `params`. A colour's
    # own numbers (`38;2;R;G;B`, `38;5;N`) aren't attributes.
    private def self.sgr_dim(params : String, dim : Bool) : Bool
      codes = params.empty? ? ["0"] : params.split(';')
      k = 0
      while k < codes.size
        case codes[k]
        when "0", "", "22" then dim = false
        when "2"           then dim = true
        when "38", "48", "58"
          k += codes[k + 1]? == "5" ? 2 : (codes[k + 1]? == "2" ? 4 : 0)
        end
        k += 1
      end
      dim
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

    # When each window was last rung, kept in a file per window so two
    # `aix tell`s, separate processes, don't both ring at once.
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
