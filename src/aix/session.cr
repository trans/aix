require "./libc_ext"
require "./terminal"

module Aix
  enum SessionState
    Cold    # No process yet, just a placeholder
    Running # Claude Code is running in a PTY
    Stopped # Process exited
  end

  class Session
    property name : String
    getter directory : String
    getter state : SessionState
    getter master_fd : Int32 = -1
    getter master_io : IO::FileDescriptor? = nil
    getter pid : Int32 = -1
    getter exit_status : Int32? = nil

    def initialize(@name : String, @directory : String)
      @state = SessionState::Cold
    end

    # Spawn Claude Code in a new PTY.
    # Extra args are passed through to the claude command.
    def start(args : Array(String) = [] of String)
      raise "Session already running" if @state == SessionState::Running

      # Create PTY pair
      o_noctty = 0o400
      master = LibC.posix_openpt(LibC::O_RDWR | o_noctty)
      raise "posix_openpt failed: #{Errno.value}" if master < 0
      raise "grantpt failed" if LibC.grantpt(master) != 0
      raise "unlockpt failed" if LibC.unlockpt(master) != 0

      slave_path = String.new(LibC.ptsname(master))

      # Get current terminal size to propagate
      rows, cols = Terminal.winsize
      ws = LibC::Winsize.new(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
      LibC.ioctl(master, TIOCSWINSZ, pointerof(ws))

      # Prepare argv and chdir path BEFORE forking so pointers stay valid
      argv_strings = ["claude"] + args
      c_strings = argv_strings.map { |s| s.to_unsafe }
      c_strings << Pointer(UInt8).null
      c_argv = c_strings.to_unsafe.as(UInt8**)
      dir_cstr = @directory.to_unsafe
      slave_cstr = slave_path.to_unsafe

      pid = LibC.fork
      raise "fork failed" if pid < 0

      if pid == 0
        # Child process — only libc calls, no Crystal runtime
        LibC.close(master)
        LibC.setsid

        slave = LibC.open(slave_cstr, LibC::O_RDWR)
        LibC._exit(127) if slave < 0
        LibC.ioctl(slave, TIOCSCTTY, 0)

        LibC.dup2(slave, 0)
        LibC.dup2(slave, 1)
        LibC.dup2(slave, 2)
        LibC.close(slave) if slave > 2

        LibC.ioctl(0, TIOCSWINSZ, pointerof(ws))

        LibC.chdir(dir_cstr)
        LibC.execvp(c_argv[0], c_argv)
        LibC._exit(127)
      end

      # Parent — wrap master fd in Crystal IO for fiber-friendly reads
      @master_fd = master
      @master_io = IO::FileDescriptor.new(master, blocking: false)
      @pid = pid
      @state = SessionState::Running
    end

    # Set the PTY window size (call on SIGWINCH).
    def resize(rows : UInt16, cols : UInt16)
      return unless @state == SessionState::Running
      ws = LibC::Winsize.new(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
      LibC.ioctl(@master_fd, TIOCSWINSZ, pointerof(ws))
    end

    # Write bytes to the PTY master (sends to Claude Code's stdin).
    def write(data : Bytes)
      return unless @state == SessionState::Running
      if io = @master_io
        io.write(data)
        io.flush
      end
    end

    # Read bytes from the PTY master (Claude Code's stdout).
    # Returns nil if the PTY is closed / process exited.
    def read(buffer : Bytes) : Int32?
      return nil unless @state == SessionState::Running
      io = @master_io
      return nil unless io
      begin
        n = io.read(buffer)
        if n == 0
          mark_stopped
          nil
        else
          n.to_i32
        end
      rescue IO::Error
        mark_stopped
        nil
      end
    end

    # Reap the child process and collect exit status.
    def reap
      return if @pid < 0
      result = LibC.waitpid(@pid, out status, LibC::WNOHANG)
      if result > 0
        @exit_status = (status >> 8) & 0xff
        mark_stopped
      end
    end

    # Stop the session.
    def stop
      return unless @state == SessionState::Running
      LibC.kill(@pid, Signal::HUP.value)
      LibC.waitpid(@pid, out status, 0)
      @exit_status = (status >> 8) & 0xff
      close_master
      @state = SessionState::Stopped
    end

    def running?
      @state == SessionState::Running
    end

    private def mark_stopped
      @state = SessionState::Stopped
      close_master
    end

    private def close_master
      if io = @master_io
        io.close rescue nil
        @master_io = nil
      end
      if @master_fd >= 0
        @master_fd = -1
      end
    end
  end
end
