require "json"

module Aix
  # AIX configuration: a set of root paths that are scanned for projects.
  #
  # A "project" is any directory, within `depth` levels of a root, that
  # contains a `.ai/` directory. This replaces manually registering each
  # project directory — you point AIX at the root(s) and it discovers the
  # rest.
  #
  # Stored at `$XDG_CONFIG_HOME/aix/config.json` (default `~/.config/aix`).
  class Config
    FILENAME      = "config.json"
    DEFAULT_DEPTH = 1
    # Directories never descended into while scanning for projects.
    IGNORE_DIRS = %w[node_modules vendor target dist build]

    property roots : Array(String)
    property depth : Int32

    def initialize(@roots : Array(String) = [] of String, @depth : Int32 = DEFAULT_DEPTH)
    end

    def self.config_dir : String
      base = ENV["XDG_CONFIG_HOME"]? || File.join(Path.home, ".config")
      File.join(base, "aix")
    end

    def self.path : String
      File.join(config_dir, FILENAME)
    end

    def self.load : Config
      return new unless File.exists?(path)
      raw = JSON.parse(File.read(path))
      roots = raw["roots"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
      depth = raw["depth"]?.try(&.as_i?) || DEFAULT_DEPTH
      new(roots, depth)
    rescue
      new
    end

    def save
      Dir.mkdir_p(self.class.config_dir)
      File.write(self.class.path, {roots: @roots, depth: @depth}.to_json)
    end

    # Add a root path (kept verbatim so `~` stays portable). Returns false
    # if an equivalent root is already configured.
    def add_root(path : String) : Bool
      normalized = SessionManager.expand_directory(path)
      return false if @roots.any? { |r| SessionManager.expand_directory(r) == normalized }
      @roots << path
      save
      true
    end

    # Remove a root by literal value or expanded-path equivalence.
    def remove_root(path : String) : Bool
      target = SessionManager.expand_directory(path)
      before = @roots.size
      @roots.reject! { |r| r == path || SessionManager.expand_directory(r) == target }
      changed = @roots.size != before
      save if changed
      changed
    end

    # Discover projects as {name, directory} pairs. A project is any
    # directory containing a `.ai/` subdirectory, found within `depth`
    # levels of a configured root. Names are made unique for use as tmux
    # window identifiers.
    def discover : Array({String, String})
      found = [] of {String, String}
      seen = Set(String).new
      @roots.each do |root|
        dir = SessionManager.expand_directory(root)
        next unless Dir.exists?(dir)
        scan(dir, @depth, found, seen)
      end
      dedupe_names(found)
    end

    private def scan(dir : String, remaining : Int32, found, seen)
      return if seen.includes?(dir)

      if Dir.exists?(File.join(dir, ".ai"))
        seen << dir
        found << {File.basename(dir), dir}
        return # a project is a leaf — don't descend into it
      end

      return if remaining <= 0

      Dir.each_child(dir) do |child|
        next if child.starts_with?(".")
        next if IGNORE_DIRS.includes?(child)
        path = File.join(dir, child)
        next unless Dir.exists?(path)
        scan(path, remaining - 1, found, seen)
      end
    rescue
      # Unreadable directory (permissions, races) — skip it.
    end

    # tmux window names must be unique. On a basename collision, prefix with
    # the parent directory name; fall back to a numeric suffix if needed.
    private def dedupe_names(found : Array({String, String})) : Array({String, String})
      counts = Hash(String, Int32).new(0)
      found.each { |name, _dir| counts[name] += 1 }

      used = Set(String).new
      result = found.map do |name, dir|
        candidate = name
        if counts[name] > 1
          parent = File.basename(File.dirname(dir))
          candidate = "#{parent}-#{name}"
        end

        base = candidate
        n = 2
        while used.includes?(candidate)
          candidate = "#{base}-#{n}"
          n += 1
        end
        used << candidate
        {candidate, dir}
      end

      result.sort_by! { |name, _dir| name.downcase }
    end
  end
end
