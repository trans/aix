require "json"
require "yaml"
require "./harness"

module Aix
  # AIX configuration, and where it finds projects.
  #
  # A project is any directory holding a `.ai/` directory. aix finds them
  # as dot-ai does (its spec, `spec/mail.md`, "Finding projects"): under
  # the directories in git config's `ai.path`, up to 4 levels down, without
  # following symbolic links or searching hidden directories and
  # `node_modules/`. So aix lists the projects dot-ai's carrier delivers
  # mail to, and follows when `ai.path` changes. Without `ai.path`, it
  # searches its own `roots`, `depth` levels down.
  #
  # Projects nest into a tree of responsibility: a project inside another
  # project's directory is below it, and that project's agent is the one
  # above it. A project is named by its agent's handle, so the bell finds
  # an agent's window from its address.
  #
  # Stored at `$XDG_CONFIG_HOME/aix/config.json` (default `~/.config/aix`).
  class Config
    FILENAME      = "config.json"
    DEFAULT_DEPTH = 1
    # How far below a search root dot-ai looks for projects.
    DOT_AI_DEPTH = 4
    # Directories never searched, besides hidden ones (as dot-ai).
    IGNORE_DIRS = %w[node_modules]

    # A discovered project. `parent` names the project above it (the
    # nearest project whose directory contains this one), or is nil at the
    # top of the tree; `level` counts the projects above it.
    record Project, name : String, directory : String, parent : String? = nil, level : Int32 = 0

    # aix's own roots and depth, searched only without `ai.path`.
    property roots : Array(String)
    property depth : Int32
    # The project designated as Leader (return-to-Leader keybind target).
    property leader : String?
    # Start Claude Code with dot-ai's mail channel, the fallback to aix's
    # bell (`Harness`, `Bell`): `"mail": {"channel": true}`. Off otherwise.
    property mail_channel : Bool
    # The harness the person chose for a project, by its directory:
    # `"harness": {"/home/me/Projects/x": "codex"}`. A project not listed
    # gets what it's set up for (`Harness.detect`).
    property harnesses : Hash(String, String)

    def initialize(@roots : Array(String) = [] of String, @depth : Int32 = DEFAULT_DEPTH,
                   @leader : String? = nil, @mail_channel : Bool = false,
                   @harnesses : Hash(String, String) = {} of String => String)
    end

    # The harness for the project in `directory`.
    def harness_for(directory : String) : Harness::Kind
      @harnesses[directory]?.try { |name| Harness::Kind.parse?(name) } || Harness.detect(directory)
    end

    # Choose the harness for the project in `directory`, and save.
    def set_harness(directory : String, kind : Harness::Kind)
      @harnesses[directory] = kind.program
      save
    end

    # The directories searched for projects: `ai.path`'s, or without any,
    # aix's own `roots`.
    def search_roots : Array(String)
      paths = Config.dot_ai_paths
      paths.empty? ? @roots : paths
    end

    # How far below a search root projects are looked for.
    def search_depth : Int32
      ai_path? ? DOT_AI_DEPTH : @depth
    end

    # Whether the search follows git config's `ai.path`.
    def ai_path? : Bool
      !Config.dot_ai_paths.empty?
    end

    # git config's `ai.path`, with `~` expanded, read as dot-ai reads it:
    # from the person's own config (`--global`), or the system's where that
    # sets none, never from a repository's.
    def self.dot_ai_paths(expand : Bool = true) : Array(String)
      paths = git_config_values("--global", expand)
      paths.empty? ? git_config_values("--system", expand) : paths
    end

    private def self.git_config_values(scope : String, expand : Bool) : Array(String)
      args = ["config", scope, "--get-all", "ai.path"]
      args.insert(2, "--type=path") if expand
      output = IO::Memory.new
      status = Process.run("git", args, output: output, error: Process::Redirect::Close)
      return [] of String unless status.success?
      output.to_s.lines.map(&.strip).reject(&.empty?)
    rescue
      [] of String # no git
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
      mail_channel = raw["mail"]?.try(&.as_h?).try(&.["channel"]?).try(&.as_bool?)
      harnesses = {} of String => String
      raw["harness"]?.try(&.as_h?).try &.each do |dir, name|
        name.as_s?.try { |value| harnesses[dir] = value }
      end
      new(roots, depth, leader, mail_channel || false, harnesses)
    rescue
      new
    end

    def save
      Dir.mkdir_p(self.class.config_dir)
      File.write(self.class.path, {roots: @roots, depth: @depth, leader: @leader, mail: {channel: @mail_channel},
                                   harness: @harnesses}.to_json)
    end

    # Add a directory to search: to git config's `ai.path` when the search
    # follows it (so dot-ai searches it too), else to aix's own roots. A
    # path starting with `~` is kept so, to stay portable; any other is
    # made absolute, since a relative one would be read from wherever its
    # reader runs. Returns false if it's searched already.
    def add_root(path : String) : Bool
      path = File.expand_path(path) unless path.starts_with?('~')
      return false if search_roots.any? { |root| Config.same_dir?(root, path) }
      if ai_path?
        Process.run("git", ["config", "--global", "--add", "ai.path", path]).success?
      else
        @roots << path
        save
        true
      end
    end

    # Stop searching a directory: take it out of git config's `ai.path`
    # when the search follows it, else out of aix's own roots.
    def remove_root(path : String) : Bool
      if ai_path?
        values = Config.dot_ai_paths(expand: false)
        expanded = Config.dot_ai_paths
        gone = values.zip?(expanded).select { |raw, full| raw == path || Config.same_dir?(full || raw, path) }.map(&.[0]).uniq
        gone.all? { |raw| Process.run("git", ["config", "--global", "--fixed-value", "--unset-all", "ai.path", raw]).success? } && !gone.empty?
      else
        before = @roots.size
        @roots.reject! { |root| root == path || Config.same_dir?(root, path) }
        changed = @roots.size != before
        save if changed
        changed
      end
    end

    # Whether two paths name one directory, `~` and links resolved.
    def self.same_dir?(a : String, b : String) : Bool
      resolve(a) == resolve(b)
    end

    private def self.resolve(path : String) : String
      full = SessionManager.expand_directory(path)
      (File.realpath(full) rescue full).rchop('/')
    end

    # Discover projects as a tree. A project is any directory containing a
    # `.ai/` subdirectory, found within `search_depth` levels of a search
    # root; the scan goes on inside projects, so the projects below one are found
    # too. Returned in tree order (each project, then the projects below it,
    # by name), with names made unique for use as tmux window identifiers.
    def discover : Array(Project)
      found = Set(String).new
      depth = search_depth
      search_roots.each do |root|
        # A root is followed even if it's a link (the user named it), but
        # by its real path, so two roots reaching one place agree.
        dir = File.realpath(SessionManager.expand_directory(root)) rescue next
        next unless Dir.exists?(dir)
        scan(dir, depth, found)
      end
      tree(dedupe_names(found.map { |dir| {Config.agent_name(dir), dir} }))
    end

    # A project's name: its agent's Arcana handle without the `@`. That is
    # `handle` in `.ai/config.yml` (or `arcana.handle`, where it was kept
    # before dot-ai moved it to the top), or else Arcana's own fallback, the
    # directory name in lower case with anything outside a-z, 0-9 and `-`
    # made a dash. The bell finds `@name`'s agent by its window `name`.
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

    # Symbolic links aren't followed, so each project is found once, where
    # it really is (as dot-ai finds projects): a link to a project would
    # find it twice, and two projects with one handle get neither's name.
    # Overlapping roots can still reach a directory twice; `found` being a
    # set keeps each project once.
    private def scan(dir : String, remaining : Int32, found : Set(String))
      found << dir if Dir.exists?(File.join(dir, ".ai"))

      return if remaining <= 0

      Dir.each_child(dir) do |child|
        next if child.starts_with?(".")
        next if IGNORE_DIRS.includes?(child)
        path = File.join(dir, child)
        # One lstat: a directory, and not a link to one.
        next unless File.info?(path, follow_symlinks: false).try(&.directory?)
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
