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

    # Load saved sessions as an array of {name, directory} tuples.
    def self.load : Array({String, String})
      return [] of {String, String} unless File.exists?(path)
      entries = Array(Array(String)).from_json(File.read(path))
      entries.map { |e| {e[0], e[1]} }
    rescue
      [] of {String, String}
    end

    # Save sessions (name + directory only — runtime state isn't persisted).
    def self.save(sessions : Array({String, String}))
      Dir.mkdir_p(data_dir)
      File.write(path, sessions.map { |s| [s[0], s[1]] }.to_json)
    end
  end
end
