require "json"
require "yaml"

module Aix
  # AIX configuration: a set of root paths that are scanned for projects.
  #
  # A "project" is any directory, within `depth` levels of a root, that
  # contains a `.ai/` directory. This replaces manually registering each
  # project directory — you point AIX at the root(s) and it discovers the
  # rest. Projects nest into a tree of responsibility: a project inside
  # another project's directory is below it, and that project's agent is
  # the one above it. A project is named by its agent's Arcana handle, so
  # the bus bridge can find an agent's window from its address.
  #
  # Stored at `$XDG_CONFIG_HOME/aix/config.json` (default `~/.config/aix`).
  class Config
    FILENAME      = "config.json"
    DEFAULT_DEPTH = 1
    # Directories never descended into while scanning for projects.
    IGNORE_DIRS = %w[node_modules vendor target dist build]

    # A discovered project. `parent` names the project above it (the
    # nearest project whose directory contains this one), or is nil at the
    # top of the tree; `level` counts the projects above it.
    record Project, name : String, directory : String, parent : String? = nil, level : Int32 = 0

    property roots : Array(String)
    property depth : Int32
    # The project designated as Leader (return-to-Leader keybind target).
    property leader : String?

    def initialize(@roots : Array(String) = [] of String, @depth : Int32 = DEFAULT_DEPTH,
                   @leader : String? = nil)
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
      leader = raw["leader"]?.try(&.as_s?)
      new(roots, depth, leader)
    rescue
      new
    end

    def save
      Dir.mkdir_p(self.class.config_dir)
      File.write(self.class.path, {roots: @roots, depth: @depth, leader: @leader}.to_json)
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

    # Discover projects as a tree. A project is any directory containing a
    # `.ai/` subdirectory, found within `depth` levels of a configured root;
    # the scan goes on inside projects, so the projects below one are found
    # too. Returned in tree order (each project, then the projects below it,
    # by name), with names made unique for use as tmux window identifiers.
    def discover : Array(Project)
      found = Set(String).new
      @roots.each do |root|
        dir = SessionManager.expand_directory(root)
        next unless Dir.exists?(dir)
        scan(dir, @depth, found)
      end
      tree(dedupe_names(found.map { |dir| {Config.agent_name(dir), dir} }))
    end

    # A project's name: its agent's Arcana handle without the `@`. That is
    # `handle` in `.ai/config.yml` (or `arcana.handle`, where it was kept
    # before dot-ai moved it to the top), or else Arcana's own fallback, the
    # directory name in lower case with anything outside a-z, 0-9 and `-`
    # made a dash. The bus bridge wakes `@name` by its window `name`.
    def self.agent_name(dir : String) : String
      configured_handle(dir).try(&.lchop('@')) || fallback_name(dir)
    end

    private def self.configured_handle(dir : String) : String?
      {"config.yml", "config.yaml"}.each do |file|
        path = File.join(dir, ".ai", file)
        next unless File.exists?(path)
        top = YAML.parse(File.read(path)).as_h?
        arcana = top.try(&.[YAML::Any.new("arcana")]?).try(&.as_h?)
        handle = handle_in(top) || handle_in(arcana)
        # Only a handle that makes a usable tmux window name.
        return handle if handle && handle =~ /\A@?[A-Za-z0-9][\w.-]*\z/
        return nil
      end
      nil
    rescue
      nil # unreadable or malformed config: use the fallback
    end

    private def self.handle_in(map : Hash(YAML::Any, YAML::Any)?) : String?
      map.try(&.[YAML::Any.new("handle")]?).try(&.as_s?).try(&.strip).presence
    end

    private def self.fallback_name(dir : String) : String
      name = File.basename(dir).downcase.gsub(/[^a-z0-9-]+/, "-").strip('-')
      name =~ /\A[a-z]/ ? name : "agent-#{name}"
    end

    # Overlapping roots can reach a directory twice; `found` being a set
    # keeps each project once.
    private def scan(dir : String, remaining : Int32, found : Set(String))
      found << dir if Dir.exists?(File.join(dir, ".ai"))

      return if remaining <= 0

      Dir.each_child(dir) do |child|
        next if child.starts_with?(".")
        next if IGNORE_DIRS.includes?(child)
        path = File.join(dir, child)
        next unless Dir.exists?(path)
        scan(path, remaining - 1, found)
      end
    rescue
      # Unreadable directory (permissions, races) — skip it.
    end

    # Link each project to the one above it, worked out from the directories
    # rather than the scan, so the order of roots doesn't matter. Then order
    # them depth-first: each project, then the projects below it, by name.
    private def tree(projects : Array({String, String})) : Array(Project)
      # Compare directories without a trailing slash; a root may keep one.
      name_at = projects.to_h { |name, dir| {dir.rchop('/'), name} }
      dir_of = projects.to_h { |name, dir| {name, dir} }
      parent_of = projects.to_h do |name, dir|
        above = Path[dir.rchop('/')].parents.reverse.find { |path| name_at.has_key?(path.to_s) }
        {name, above.try { |path| name_at[path.to_s] }}
      end

      below = Hash(String?, Array(String)).new { |hash, key| hash[key] = [] of String }
      parent_of.each { |name, parent| below[parent] << name }

      ordered = [] of Project
      stack = below[nil].sort_by(&.downcase).reverse.map { |name| {name, 0} }
      while entry = stack.pop?
        name, level = entry
        ordered << Project.new(name, dir_of[name], parent_of[name], level)
        below[name].sort_by(&.downcase).reverse_each { |child| stack << {child, level + 1} }
      end
      ordered
    end

    # tmux window names must be unique. On a basename collision, prefix with
    # the parent directory name; fall back to a numeric suffix if needed.
    private def dedupe_names(found : Array({String, String})) : Array({String, String})
      counts = Hash(String, Int32).new(0)
      found.each { |name, _dir| counts[name] += 1 }

      used = Set(String).new
      found.map do |name, dir|
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
    end
  end
end
