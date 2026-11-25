require "json"
require "html"
require "markd"
require "./harness"

module Aix
  # A Claude Code conversation, read from the transcript Claude Code keeps
  # of it (`projects/<project key>/<session id>.jsonl` in its config
  # folder), for the web page: the messages' own markdown, rendered,
  # rather than the screen it was drawn on.
  #
  # A line per entry. `user` and `assistant` entries hold a message
  # (`message.content`: a string, or parts: `text`, `thinking`,
  # `tool_use`, `tool_result`); a person's prompt has `origin.kind:
  # "human"`. Others (`system`, `attachment`, `api-request`, …) are
  # Claude Code's bookkeeping. Entries of a subagent's own conversation
  # are marked `isSidechain`. Checked against Claude Code 2.1.322 on
  # 2026-11-24; the format is Claude Code's own and undocumented, so
  # anything unexpected is skipped.
  module Transcript
    # What the page shows, an entry at a time.
    #
    # - `user`, `assistant`: `html`, the message's markdown rendered.
    # - `tool`: a tool call: `id`, `name`, `summary` (a line saying what it
    #   does) and `input` (its arguments, as text).
    # - `result`: a tool call's result: `id` (the call's), `text`, `error`.
    # - `title`: the conversation's title, as Claude Code named it.
    # - `summary`: Claude Code's summary of the conversation before a
    #   compaction (`html`), which it gives the agent as a message.
    # - `note`: a line from aix (`text`).
    record Entry, kind : String, html : String = "", id : String = "", name : String = "",
      summary : String = "", input : String = "", text : String = "", error : Bool = false do
      include JSON::Serializable
    end

    # How much of a transcript's end is read at first.
    TAIL_BYTES = 2 * 1024 * 1024

    # A tool's arguments, and its result, are cut to this many characters.
    INPUT_LIMIT  =  4_000
    RESULT_LIMIT = 10_000

    MARKDOWN = Markd::Options.new(safe: true)

    # The transcript of the conversation in `session`: for an agent that's
    # running, the one it's in; else its last.
    def self.path_for(session : Session, config_dir : String = Harness.claude_config_dir) : String?
      return nil unless session.harness.claude?
      id = session.running? ? running_session_id(session.name) : nil
      id ||= Harness.claude_resume_target(session.directory, session.claude_session_id, config_dir)
      return nil unless id
      path = File.join(config_dir, "projects", Harness.project_key(session.directory), "#{id}.jsonl")
      File.exists?(path) ? path : nil
    end

    private def self.running_session_id(window : String) : String?
      pid = Term.agent_pids.find { |name, _| name == window }.try(&.[1]) || return nil
      Harness.claude_session_in_pane(pid).try(&.session_id)
    end

    # Follows a transcript as it grows: `read` gives the entries written
    # since the last time.
    class Follower
      getter path : String

      # Whether the start of the transcript was left out.
      getter? cut : Bool

      def initialize(@path : String, tail : Int32 = TAIL_BYTES)
        size = File.size(@path)
        @offset = size > tail ? size - tail : 0_i64
        @cut = @offset > 0
        @skipping = @cut # to the start of the first whole line
        @pending = Bytes.empty
      end

      def read : Array(Entry)
        size = File.size(@path)
        return [] of Entry if size <= @offset
        fresh = Bytes.new(size - @offset)
        File.open(@path) do |file|
          file.seek(@offset)
          file.read_fully(fresh)
        end
        @offset = size
        bytes = Bytes.new(@pending.size + fresh.size)
        @pending.copy_to(bytes)
        fresh.copy_to(bytes + @pending.size)
        # Whole lines only, as bytes: a read may stop inside a character.
        last = bytes.rindex('\n'.ord.to_u8)
        unless last
          @pending = bytes
          return [] of Entry
        end
        @pending = bytes[(last + 1)..].dup
        text = String.new(bytes[0, last + 1])
        if @skipping
          text = text[((text.index('\n') || -1) + 1)..]
          @skipping = false
        end
        text.split('\n').flat_map { |line| Transcript.entries(line) }
      rescue
        [] of Entry
      end
    end

    # The entries in one line of a transcript.
    def self.entries(line : String) : Array(Entry)
      return [] of Entry if line.blank?
      data = JSON.parse(line)
      return [] of Entry if data["isSidechain"]?.try(&.as_bool?) || data["isMeta"]?.try(&.as_bool?)
      case data["type"]?.try(&.as_s?)
      when "user"      then user_entries(data)
      when "assistant" then assistant_entries(data)
      when "ai-title"
        title = data["aiTitle"]?.try(&.as_s?)
        title ? [Entry.new("title", text: title)] : [] of Entry
      when "system"
        data["subtype"]?.try(&.as_s?) == "compact_boundary" ? [Entry.new("note", text: "The conversation was compacted here.")] : [] of Entry
      else
        [] of Entry
      end
    rescue
      [] of Entry
    end

    private def self.user_entries(data : JSON::Any) : Array(Entry)
      content = data.dig?("message", "content")
      kind = data["isCompactSummary"]?.try(&.as_bool?) ? "summary" : "user"
      if text = content.try(&.as_s?)
        shown = strip_reminders(text)
        return shown.blank? ? [] of Entry : [Entry.new(kind, html: markdown(shown))]
      end
      parts(content).compact_map do |part|
        case part["type"]?.try(&.as_s?)
        when "tool_result"
          Entry.new("result", id: part["tool_use_id"]?.try(&.as_s?) || "",
            text: cut(result_text(part["content"]?), RESULT_LIMIT),
            error: part["is_error"]?.try(&.as_bool?) || false)
        when "text"
          shown = strip_reminders(part["text"]?.try(&.as_s?) || "")
          shown.blank? ? nil : Entry.new("user", html: markdown(shown))
        end
      end
    end

    private def self.assistant_entries(data : JSON::Any) : Array(Entry)
      parts(data.dig?("message", "content")).compact_map do |part|
        case part["type"]?.try(&.as_s?)
        when "text"
          text = part["text"]?.try(&.as_s?) || ""
          text.blank? ? nil : Entry.new("assistant", html: markdown(text))
        when "tool_use"
          name = part["name"]?.try(&.as_s?) || "tool"
          input = part["input"]? || JSON::Any.new(nil)
          Entry.new("tool", id: part["id"]?.try(&.as_s?) || "", name: name,
            summary: tool_summary(name, input), input: cut(tool_input(input), INPUT_LIMIT))
        end
      end
    end

    private def self.parts(content : JSON::Any?) : Array(JSON::Any)
      content.try(&.as_a?) || [] of JSON::Any
    end

    # A line saying what a tool call does: its description or the
    # argument that says most.
    def self.tool_summary(name : String, input : JSON::Any) : String
      fields = input.as_h? || return ""
      key = {"description", "command", "file_path", "path", "pattern", "query", "url", "prompt", "skill"}.find do |candidate|
        fields[candidate]?.try(&.as_s?).try { |value| !value.blank? }
      end
      value = key ? fields[key].as_s : (fields.values.compact_map(&.as_s?).first? || "")
      line = value.lines.first?.try(&.strip) || ""
      line.size > 160 ? line[0, 159] + "…" : line
    end

    private def self.tool_input(input : JSON::Any) : String
      fields = input.as_h? || return input.to_pretty_json
      # A command reads best as itself.
      if (command = fields["command"]?.try(&.as_s?)) && fields.size <= 3
        return command
      end
      input.to_pretty_json
    end

    private def self.result_text(content : JSON::Any?) : String
      return "" unless content
      return content.as_s if content.as_s?
      parts(content).compact_map do |part|
        case part["type"]?.try(&.as_s?)
        when "text"  then part["text"]?.try(&.as_s?)
        when "image" then "(an image)"
        end
      end.join("\n")
    end

    # Claude Code's notes to the model, put in a person's message
    # (`<system-reminder>…</system-reminder>`), aren't what the person
    # wrote.
    def self.strip_reminders(text : String) : String
      text.gsub(/<system-reminder>.*?<\/system-reminder>/m, "").strip
    end

    def self.markdown(text : String) : String
      Markd.to_html(text, MARKDOWN)
    rescue
      "<pre>#{HTML.escape(text)}</pre>"
    end

    private def self.cut(text : String, limit : Int32) : String
      return text if text.size <= limit
      "#{text[0, limit]}\n… (#{text.size - limit} more characters)"
    end
  end
end
