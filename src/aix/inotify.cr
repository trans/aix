{% if flag?(:linux) %}
  lib LibInotify
    fun inotify_init1(flags : LibC::Int) : LibC::Int
    fun inotify_add_watch(fd : LibC::Int, pathname : LibC::Char*, mask : UInt32) : LibC::Int
  end
{% end %}

module Aix
  # Linux's inotify, for waiting on new files in a set of directories
  # without polling.
  class Inotify
    IN_CLOSE_WRITE = 0x00000008_u32
    IN_MOVED_TO    = 0x00000080_u32
    IN_NONBLOCK    =       0o4000
    IN_CLOEXEC     =    0o2000000

    # A file finished writing in, or renamed into, a watched directory.
    # dot-ai writes a message under a hidden name, then renames it into
    # place.
    NEW_FILE = IN_CLOSE_WRITE | IN_MOVED_TO

    def self.available? : Bool
      {{ flag?(:linux) }}
    end

    @io : IO::FileDescriptor

    def initialize
      fd = Inotify.open_fd
      @io = IO::FileDescriptor.new(fd)
      # Wrapping an fd that isn't a pipe or socket makes it blocking again,
      # and a blocking read would stall every fiber in the process (the
      # bell's retries). Non-blocking, the read waits in the event loop.
      IO::FileDescriptor.set_blocking(fd, false)
      @watches = {} of Int32 => String
    end

    protected def self.open_fd : Int32
      {% if flag?(:linux) %}
        fd = LibInotify.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        raise RuntimeError.from_errno("inotify_init1") if fd < 0
        fd
      {% else %}
        raise "inotify is Linux only"
      {% end %}
    end

    # Watch `dir` for new files. Returns false if it can't be watched.
    def watch(dir : String) : Bool
      {% if flag?(:linux) %}
        wd = LibInotify.inotify_add_watch(@io.fd, dir, NEW_FILE)
        return false if wd < 0
        @watches[wd] = dir
        true
      {% else %}
        false
      {% end %}
    end

    def watching?(dir : String) : Bool
      @watches.values.includes?(dir)
    end

    # Yield each new file's directory and name, as they come. Blocks the
    # fiber, not the process.
    def each_new_file(&)
      buffer = Bytes.new(64 * 1024)
      loop do
        count = @io.read(buffer)
        break if count == 0
        Inotify.parse(buffer[0, count]) do |wd, _mask, name|
          if dir = @watches[wd]?
            yield dir, name
          end
        end
      end
    end

    # Parse a read's worth of `struct inotify_event`s: a watch descriptor,
    # mask, cookie and name length (4 bytes each), then the name, padded
    # with NULs.
    def self.parse(bytes : Bytes, &)
      i = 0
      while i + 16 <= bytes.size
        wd = IO::ByteFormat::SystemEndian.decode(Int32, bytes[i, 4])
        mask = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[i + 4, 4])
        length = IO::ByteFormat::SystemEndian.decode(UInt32, bytes[i + 12, 4]).to_i
        break if i + 16 + length > bytes.size
        raw = bytes[i + 16, length]
        name = String.new(raw[0, raw.index(0_u8) || raw.size])
        yield wd, mask, name
        i += 16 + length
      end
    end
  end
end
