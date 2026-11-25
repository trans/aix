require "json"
require "./transcript"

module Aix
  # A project's files, for the web page's file tree: a folder's entries,
  # and a file's contents. Only inside the project: a path that leads out
  # of it (`..`, or a symbolic link to elsewhere) is refused.
  module ProjectFiles
    # Left out of the tree.
    HIDDEN = {".git"}

    # Larger files aren't shown.
    SHOW_LIMIT = 512 * 1024

    record Item, name : String, path : String, dir : Bool, size : Int64 do
      include JSON::Serializable
    end

    # A file's contents, as the page shows them: `markdown` (`html`),
    # `text` (`text`), or `binary` and `large`, which aren't shown.
    record Shown, kind : String, path : String, html : String = "", text : String = "", size : Int64 = 0 do
      include JSON::Serializable
    end

    class OutsideProject < Exception
    end

    # The entries of folder `relative` in `root`: folders first, then
    # files, each by name.
    def self.list(root : String, relative : String = "") : Array(Item)
      folder = inside(root, relative)
      raise OutsideProject.new("not a folder") unless Dir.exists?(folder)
      items = Dir.children(folder).compact_map do |name|
        next if HIDDEN.includes?(name)
        path = File.join(folder, name)
        info = File.info?(path) || next # a broken link
        Item.new(name, join(relative, name), info.directory?, info.directory? ? 0_i64 : info.size)
      end
      items.sort_by { |item| {item.dir ? 0 : 1, item.name.downcase} }
    end

    # File `relative` in `root`, to show.
    def self.show(root : String, relative : String) : Shown
      path = inside(root, relative)
      raise OutsideProject.new("not a file") unless File.file?(path)
      size = File.size(path)
      return Shown.new("large", relative, size: size) if size > SHOW_LIMIT
      bytes = File.open(path, &.getb_to_end)
      return Shown.new("binary", relative, size: size) if bytes[0, {bytes.size, 8000}.min].includes?(0_u8)
      text = String.new(bytes).scrub
      if {".md", ".markdown"}.includes?(File.extname(path).downcase)
        Shown.new("markdown", relative, html: Transcript.markdown(text), size: size)
      else
        Shown.new("text", relative, text: text, size: size)
      end
    end

    # The real path of `relative` in `root`, which must be inside it.
    def self.inside(root : String, relative : String) : String
      base = File.realpath(root)
      path = File.realpath(File.expand_path(relative, base))
      raise OutsideProject.new("outside the project") unless path == base || path.starts_with?(base + "/")
      path
    rescue ex : File::Error
      raise OutsideProject.new("no such file")
    end

    private def self.join(relative : String, name : String) : String
      relative.empty? ? name : "#{relative}/#{name}"
    end
  end
end
