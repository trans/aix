require "json"
require "./harness"
require "./tmux"

module Aix
  # The conversations open in other programs than aix, by project
  # directory: so aix doesn't resume one that another program holds
  # (dot-ai's spec, "Runners": no program resumes a session another holds
  # open), and the TUI can say where a project is open.
  #
  # Claude Code keeps a file for each running session
  # (`sessions/<pid>.json`), with its directory and session id. Codex locks
  # a file for each open conversation (`thread-writer-locks/<id>.lock`, an
  # flock), and the kernel's table of locks (`/proc/locks`, Linux) gives the
  # process holding it; the conversation's directory is in the first line
  # of its session file (`sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`).
  # Checked against Claude Code 2.1.322 and Codex 0.167.2 and 0.169.0, on
  # 2026-11-14. Codex itself won't open a conversation that's locked ("This
  # conversation is open in another app"); Claude Code has no such lock.
  module Conversations
    # An open conversation: its harness, its id, the process holding it,
    # and where that is, in words.
    record Open, harness : Harness::Kind, id : String, pid : Int64, where : String

    # The conversations open outside aix's windows, by project directory
    # (symbolic links resolved).
    def self.elsewhere : Hash(String, Array(Open))
      in_aix = Tmux.window_pids.map(&.[1]).to_set
      found = Hash(String, Array(Open)).new { |hash, key| hash[key] = [] of Open }
      (claude_open + codex_open).each do |directory, open|
        next if in_aix.includes?(open.pid) || in_aix.includes?(Harness.parent_pid(open.pid) || 0_i64)
        found[real(directory)] << open
      end
      found
    end

    # Those open in `directory`, from `elsewhere`.
    def self.in(map : Hash(String, Array(Open)), directory : String) : Array(Open)
      map[real(directory)]? || [] of Open
    end

    # The one of `open` (a project's conversations open elsewhere) that
    # resuming the project in `harness` would take over, if any. Claude
    # Code resumes `target` (`Harness.claude_resume_target`). Codex's
    # `resume --last` takes the directory's newest, which aix can't see, so
    # any of the project's Codex conversations open elsewhere counts.
    def self.blocking(open : Array(Open), harness : Harness::Kind, target : String?) : Open?
      if harness.codex?
        open.find(&.harness.codex?)
      else
        open.find { |conversation| conversation.harness.claude? && conversation.id == target }
      end
    end

    # A line saying where `open` is, for people.
    def self.describe(open : Open) : String
      "#{open.harness.label} in #{open.where} (pid #{open.pid})"
    end

    # Claude Code's running sessions, with their directories.
    def self.claude_open(config_dir : String = Harness.claude_config_dir) : Array({String, Open})
      dir = File.join(config_dir, "sessions")
      return [] of {String, Open} unless Dir.exists?(dir)
      Dir.children(dir).compact_map do |file|
        next unless file.ends_with?(".json")
        pid = file.rchop(".json").to_i64? || next
        next unless running?(pid, "claude")
        begin
          data = JSON.parse(File.read(File.join(dir, file)))
          cwd = data["cwd"]?.try(&.as_s?) || next
          id = data["sessionId"]?.try(&.as_s?) || next
          {cwd, Open.new(Harness::Kind::Claude, id, pid, claude_where(data["entrypoint"]?.try(&.as_s?)))}
        rescue
          nil
        end
      end
    end

    # Codex's locked conversations, with their directories.
    def self.codex_open(home : String = codex_home, locks_table : String = "/proc/locks") : Array({String, Open})
      dir = File.join(home, "thread-writer-locks")
      return [] of {String, Open} unless Dir.exists?(dir)
      held = lock_holders(locks_table)
      return [] of {String, Open} if held.empty?
      Dir.children(dir).compact_map do |file|
        next unless file.ends_with?(".lock") && !file.starts_with?('.')
        id = file.rchop(".lock")
        next unless id.matches?(/\A[A-Za-z0-9\-]+\z/)
        key = file_key(File.join(dir, file)) || next
        pid = held[key]? || next
        cwd = codex_directory(home, id) || next
        {cwd, Open.new(Harness::Kind::Codex, id, pid, codex_where(pid))}
      end
    end

    # Codex's own directory: `CODEX_HOME`, else `~/.codex`.
    def self.codex_home : String
      ENV["CODEX_HOME"]? || File.join(Path.home, ".codex")
    end

    # The processes holding a lock on each file, from the kernel's table of
    # locks: a line per lock, `N: FLOCK ADVISORY WRITE <pid> <maj>:<min>:<inode> …`
    # (the device in hex), and `N: -> …` for one waiting, which holds
    # nothing.
    def self.lock_holders(table : String = "/proc/locks") : Hash({Int64, Int64, UInt64}, Int64)
      holders = {} of {Int64, Int64, UInt64} => Int64
      return holders unless File.exists?(table)
      File.each_line(table) do |line|
        fields = line.split
        next if fields.size < 6 || fields[1] == "->"
        pid = fields[4].to_i64? || next
        device = fields[5].split(':')
        next unless device.size == 3
        major, minor, inode = device[0].to_i64?(16), device[1].to_i64?(16), device[2].to_u64?
        holders[{major, minor, inode}] = pid if major && minor && inode
      end
      holders
    rescue
      {} of {Int64, Int64, UInt64} => Int64 # unreadable: no locks seen
    end

    # A file's device (major, minor) and inode, as the table of locks
    # gives them.
    def self.file_key(path : String) : {Int64, Int64, UInt64}?
      stat = uninitialized LibC::Stat
      return nil unless LibC.stat(path.check_no_null_byte, pointerof(stat)) == 0
      dev = stat.st_dev.to_u64
      major = ((dev >> 8) & 0xfff) | ((dev >> 32) & ~0xfff_u64)
      minor = (dev & 0xff) | ((dev >> 12) & ~0xff_u64)
      {major.to_i64, minor.to_i64, stat.st_ino.to_u64}
    end

    # A Codex conversation's directory, from its session file's first line
    # (`{"type":"session_meta","payload":{"cwd":…}}`).
    def self.codex_directory(home : String, id : String) : String?
      path = Dir.glob(File.join(home, "sessions", "*", "*", "*", "rollout-*-#{id}.jsonl")).first? ||
             Dir.glob(File.join(home, "archived_sessions", "rollout-*-#{id}.jsonl")).first? || return nil
      first = File.open(path, &.gets) || return nil
      JSON.parse(first)["payload"]?.try(&.["cwd"]?).try(&.as_s?)
    rescue
      nil
    end

    private def self.claude_where(entrypoint : String?) : String
      return "another program" unless entrypoint
      return "a terminal" if entrypoint == "cli"
      entrypoint.includes?("vscode") ? "VS Code" : entrypoint
    end

    private def self.codex_where(pid : Int64) : String
      if Harness.process_args(pid).includes?("app-server")
        "Codex's shared app server (VS Code, the Codex app, or a plain codex)"
      else
        "a terminal"
      end
    end

    # Whether `pid` is a running process of `program` (a pid's file may
    # outlive it, and the number be reused).
    private def self.running?(pid : Int64, program : String) : Bool
      Process.exists?(pid) && Harness.process_args(pid).any?(&.includes?(program))
    end

    private def self.real(path : String) : String
      File.realpath(path)
    rescue
      path
    end
  end
end
