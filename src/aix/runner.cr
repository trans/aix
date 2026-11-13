require "./harness"

module Aix
  # aix as a dot-ai runner (dot-ai's spec, `spec/mail.md`, "Runners" and
  # "Session records", Draft 0.5). aix registers itself, so dot-ai's carrier
  # can run `aix tell <id>` for the sessions aix started, and it reads those
  # sessions' records to answer.
  module Runner
    NAME = Harness::RUNNER

    # dot-ai's per-person state: `$XDG_STATE_HOME/dot-ai`, else
    # `~/.local/state/dot-ai`.
    def self.state_dir : String
      base = ENV["XDG_STATE_HOME"]? || File.join(Path.home, ".local", "state")
      File.join(base, "dot-ai")
    end

    # Register aix: `runners/aix` holds one line, the absolute path of the
    # program to run, written under a hidden name and renamed into place, in
    # a folder only the person can open. The carrier runs it only through
    # this file, after checking that only the person can write it. Done each
    # time aix starts a session, so the last aix to start one is the one the
    # carrier runs.
    def self.register(program : String? = Process.executable_path) : Bool
      return false unless program
      dir = File.join(state_dir, "runners")
      Dir.mkdir_p(dir)
      File.chmod(dir, 0o700)
      path = File.join(dir, NAME)
      line = "#{program}\n"
      return true if (File.read(path) rescue nil) == line
      hidden = File.join(dir, ".#{NAME}.#{Process.pid}")
      File.write(hidden, line, perm: 0o600)
      File.rename(hidden, path)
      true
    rescue
      false # unwritable state folder: the carrier won't run aix, and the session hears at its Stop
    end

    # A session's record, written by dot-ai's hooks inside the session:
    # `sessions/<key>.session`, a `field=value` line each.
    record SessionRecord, id : String, path : String, by : String?, pid : Int64?, state : String?

    # The record file's key: the session id, with each character other than
    # `A-Za-z0-9_.-` turned into `_`.
    def self.session_key(id : String) : String
      id.gsub(/[^A-Za-z0-9_.\-]/, "_")
    end

    def self.session_record(id : String) : SessionRecord?
      path = File.join(state_dir, "sessions", "#{session_key(id)}.session")
      return nil unless File.exists?(path)
      fields = {} of String => String
      File.each_line(path) do |line|
        key, sep, value = line.partition('=')
        fields[key] = value unless sep.empty? || fields.has_key?(key)
      end
      SessionRecord.new(id, path, fields["by"]?, fields["pid"]?.try(&.to_i64?), fields["state"]?)
    rescue
      nil
    end

    # Mark a record `ended`, as a runner does when it finds its session
    # isn't open (`tell`'s status 3), rewriting it under a hidden name.
    def self.mark_ended(record : SessionRecord) : Bool
      lines = File.read_lines(record.path).map { |line| line.starts_with?("state=") ? "state=ended" : line }
      hidden = File.join(File.dirname(record.path), ".#{File.basename(record.path)}.#{Process.pid}")
      File.write(hidden, lines.join("\n") + "\n")
      File.rename(hidden, record.path)
      true
    rescue
      false
    end

    # What `aix tell` answers for a session that isn't in any of aix's panes:
    # 4 while it's still open (one started from inside an aix session, which
    # inherited `DOT_AI_BY`, or one whose record names no process to check),
    # since aix can't push to it and it hears at its next start or Stop; 3
    # when it's not open, with its record, if it's aix's, marked `ended`.
    def self.not_in_pane(id : String) : {Int32, String}
      record = session_record(id)
      return {3, "not open in aix"} unless record && record.state != "ended"
      pid = record.pid
      unless pid
        return {4, "not in an aix pane, and its record names no process to check: it hears at its next start or Stop"}
      end
      if Process.exists?(pid)
        return {4, "open, but not in an aix pane: it hears at its next start or Stop"}
      end
      mark_ended(record) if record.by == NAME
      {3, "not open; its record is marked ended"}
    end
  end
end
