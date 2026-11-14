require "./tmux"

module Aix
  # The last screen of each project's agent, for the TUI's preview: the
  # pane's text as it was the last time aix saw it, so a project whose agent
  # isn't running still shows where it left off. Kept per person, in a
  # folder only they can open, since a screen can hold anything.
  module Screens
    def self.dir : String
      base = ENV["XDG_STATE_HOME"]? || File.join(Path.home, ".local", "state")
      File.join(base, "aix", "screens")
    end

    # Capture a running agent's screen and save it. Nil if its window isn't
    # open.
    def self.capture(name : String) : String?
      text = Tmux.capture_screen(name) || return nil
      save(name, text)
      text
    end

    def self.save(name : String, text : String) : Nil
      Dir.mkdir_p(dir)
      File.chmod(dir, 0o700)
      path = File.join(dir, name)
      hidden = File.join(dir, ".#{name}.#{Process.pid}")
      File.write(hidden, text, perm: 0o600)
      File.rename(hidden, path)
    rescue
      # Not saved: the preview shows the last one that was.
    end

    def self.load(name : String) : String?
      File.read(File.join(dir, name))
    rescue
      nil
    end

    # What the preview shows for `name`: its screen now if its window is
    # there (its agent running, or exited and its last screen kept), else
    # the one saved last, fitted to `width` by `height`.
    def self.preview(name : String, width : Int32, height : Int32) : String?
      text = capture(name) || load(name)
      text.try { |screen| fit(screen, width, height) }
    end

    # The bottom of a screen that fits `width` by `height`: blank lines at
    # the end dropped (a screen is padded to the pane's height), then the
    # last `height` lines, each cut to `width` columns.
    def self.fit(text : String, width : Int32, height : Int32) : String
      return "" if width <= 0 || height <= 0
      lines = text.lines.map(&.rstrip)
      while lines.last?.try(&.empty?)
        lines.pop
      end
      lines = lines.last(height)
      lines.map { |line| cut(line, width) }.join("\n")
    end

    # Text with its lines broken at spaces to fit `width` columns.
    def self.wrap(text : String, width : Int32) : String
      return text if width <= 0
      text.lines.flat_map { |line|
        rows = [] of String
        row = ""
        line.split(' ').each do |word|
          if row.empty?
            row = word
          elsif row.size + 1 + word.size <= width
            row += " #{word}"
          else
            rows << row
            row = word
          end
        end
        rows << row
        rows
      }.join("\n")
    end

    # A line cut to `width` columns, counting a wide character (most CJK,
    # emoji) as two.
    private def self.cut(line : String, width : Int32) : String
      columns = 0
      String.build do |io|
        line.each_char do |char|
          w = wide?(char) ? 2 : 1
          break if columns + w > width
          io << char
          columns += w
        end
      end
    end

    private def self.wide?(char : Char) : Bool
      code = char.ord
      (0x1100..0x115F).includes?(code) || (0x2E80..0xA4CF).includes?(code) ||
        (0xAC00..0xD7A3).includes?(code) || (0xF900..0xFAFF).includes?(code) ||
        (0xFE30..0xFE4F).includes?(code) || (0xFF00..0xFF60).includes?(code) ||
        (0xFFE0..0xFFE6).includes?(code) || (0x1F300..0x1FAFF).includes?(code) ||
        (0x20000..0x3FFFD).includes?(code)
    end
  end
end
