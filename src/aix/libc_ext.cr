require "c/termios"

# POSIX bindings not in Crystal's stdlib for Linux
lib LibC
  # PTY creation
  fun posix_openpt(flags : Int32) : Int32
  fun grantpt(fd : Int32) : Int32
  fun unlockpt(fd : Int32) : Int32
  fun ptsname(fd : Int32) : Char*

  # Session/controlling terminal
  fun setsid : Int32
  fun ioctl(fd : Int32, request : UInt64, ...) : Int32

  # Terminal window size
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end
end

module Aix
  TIOCSWINSZ = 0x5414_u64
  TIOCGWINSZ = 0x5413_u64
  TIOCSCTTY  = 0x540E_u64
end
