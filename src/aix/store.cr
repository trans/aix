require "json"

module Aix
  module Store
    FILENAME = "sessions.json"

    def self.data_dir : String
      base = ENV["XDG_DATA_HOME"]? || File.join(Path.home, ".local", "share")
      File.join(base, "aix")
    end

    def self.path : String
      File.join(data_dir, FILENAME)
    end

    # Load saved sessions as an array of {name, directory, claude_session_id?} tuples.
    def self.load : Array({String, String, String?})
      return [] of {String, String, String?} unless File.exists?(path)
      entries = Array(Array(String?)).from_json(File.read(path))
      entries.map { |e| {e[0].not_nil!, e[1].not_nil!, e[2]?} }
    rescue
      [] of {String, String, String?}
    end

    # Save sessions (name, directory, and claude session ID).
    def self.save(sessions : Array({String, String, String?}))
      Dir.mkdir_p(data_dir)
      File.write(path, sessions.map { |s| [s[0], s[1], s[2]] }.to_json)
    end
  end
end
