require "json"

module Aix
  # How aix launches a harness, and what it can read about a running one.
  #
  # An idle Claude Code session hears of new mail only when something tells
  # it. aix's own way is the bell (`Bell`): it types a fixed notice into the
  # session's pane when that's safe. The fallback is dot-ai's mail channel,
  # which Claude Code loads only when started with
  # `--dangerously-load-development-channels plugin:dot-ai@dot-ai` (the
  # option the user's own launcher passes) and which shows a warning at
  # every start. `mail.channel` in the config turns the fallback on.
  module Harness
    CHANNEL_OPTION = "--dangerously-load-development-channels"
    DOT_AI_PLUGIN  = "dot-ai@dot-ai"
    DOT_AI_CHANNEL = "plugin:#{DOT_AI_PLUGIN}"

    # The runner a session started by aix names in its environment, so
    # dot-ai's hooks inside it leave telling it of mail to aix (dot-ai's
    # spec, "Runners").
    RUNNER = "aix"

    # Claude Code's arguments for a session: dot-ai's mail channel, when
    # `mail_channel` is on and the dot-ai plugin is installed, then `args`.
    # Arguments that already load a channel are left alone.
    def self.claude_args(args : Array(String), mail_channel : Bool = false,
                         installed : Bool = dot_ai_installed?) : Array(String)
      return args unless mail_channel && installed
      return args if channel?(args)
      [CHANNEL_OPTION, DOT_AI_CHANNEL] + args
    end

    # Whether Claude Code arguments load a channel, which then tells the
    # session of mail itself.
    def self.channel?(args : Array(String)) : Bool
      args.any? { |arg| arg == CHANNEL_OPTION || arg == "--channels" || arg.starts_with?("--channels=") }
    end

    # The environment for a session aix starts. A session with dot-ai's
    # channel keeps dot-ai as its runner, since the channel is what pushes
    # to it; any other is aix's.
    def self.session_env(args : Array(String)) : Hash(String, String)
      channel?(args) ? {} of String => String : {"DOT_AI_BY" => RUNNER}
    end

    # Whether Claude Code has the dot-ai plugin installed, from its plugin
    # registry. Without it, the channel option would name a plugin Claude
    # Code doesn't have.
    def self.dot_ai_installed?(config_dir : String = claude_config_dir) : Bool
      path = File.join(config_dir, "plugins", "installed_plugins.json")
      return false unless File.exists?(path)
      plugins = JSON.parse(File.read(path))["plugins"]?.try(&.as_h?)
      plugins ? plugins.has_key?(DOT_AI_PLUGIN) : false
    rescue
      false # unreadable or malformed registry: launch without the channel
    end

    # Claude Code's own directory: `CLAUDE_CONFIG_DIR`, else `~/.claude`.
    def self.claude_config_dir : String
      ENV["CLAUDE_CONFIG_DIR"]? || File.join(Path.home, ".claude")
    end

    # A running Claude Code session, from the file Claude Code keeps for
    # each one (`sessions/<pid>.json`). Undocumented, so read defensively:
    # `status` has been `idle`, `busy` or `waiting`.
    record ClaudeSession, pid : Int64, session_id : String?, status : String?

    def self.claude_session(pid : Int64, config_dir : String = claude_config_dir) : ClaudeSession?
      path = File.join(config_dir, "sessions", "#{pid}.json")
      return nil unless File.exists?(path)
      data = JSON.parse(File.read(path))
      ClaudeSession.new(pid, data["sessionId"]?.try(&.as_s?), data["status"]?.try(&.as_s?))
    rescue
      nil
    end

    # The Claude Code session running in a pane whose process is
    # `pane_pid`: the pane's process itself (aix starts `claude` directly),
    # or a child of it (`claude` started from a shell in the pane).
    def self.claude_session_in_pane(pane_pid : Int64, config_dir : String = claude_config_dir) : ClaudeSession?
      if own = claude_session(pane_pid, config_dir)
        return own
      end
      each_claude_session(config_dir) do |session|
        return session if parent_pid(session.pid) == pane_pid
      end
      nil
    end

    # The process id of the Claude Code session with this session id.
    def self.claude_pid(session_id : String, config_dir : String = claude_config_dir) : Int64?
      each_claude_session(config_dir) do |session|
        return session.pid if session.session_id == session_id
      end
      nil
    end

    private def self.each_claude_session(config_dir : String, &)
      dir = File.join(config_dir, "sessions")
      return unless Dir.exists?(dir)
      Dir.each_child(dir) do |file|
        next unless file.ends_with?(".json")
        pid = file.rchop(".json").to_i64?
        next unless pid
        if session = claude_session(pid, config_dir)
          yield session
        end
      end
    end

    # A process's parent, from `/proc/<pid>/stat` (Linux).
    def self.parent_pid(pid : Int64) : Int64?
      stat = File.read("/proc/#{pid}/stat")
      # The command name, field 2, is in parentheses and may hold spaces.
      fields = stat[(stat.rindex(')') || return nil) + 2..].split(' ')
      fields[1]?.try(&.to_i64?)
    rescue
      nil
    end

    # A process's arguments, from `/proc/<pid>/cmdline` (Linux).
    def self.process_args(pid : Int64) : Array(String)
      File.read("/proc/#{pid}/cmdline").split('\0', remove_empty: true)
    rescue
      [] of String
    end
  end
end
