require "./libc_ext"

module Aix
  # Manages the host terminal's raw/cooked mode and size queries.
  module Terminal
    @@original : LibC::Termios? = nil

    # Save the current terminal state so we can restore it later.
    def self.save
      termios = uninitialized LibC::Termios
      if LibC.tcgetattr(STDIN.fd, pointerof(termios)) == 0
        @@original = termios
      end
    end

    # Switch to raw mode: no echo, no line buffering, no signal generation.
    def self.raw!
      save unless @@original
      raw = @@original.not_nil!.dup
      LibC.cfmakeraw(pointerof(raw))
      LibC.tcsetattr(STDIN.fd, LibC::TCSANOW, pointerof(raw))
    end

    # Restore the original terminal mode (cooked).
    def self.restore!
      if orig = @@original
        o = orig.dup
        LibC.tcsetattr(STDIN.fd, LibC::TCSANOW, pointerof(o))
      end
    end

    # Get the current terminal window size.
    def self.winsize : {UInt16, UInt16}
      ws = uninitialized LibC::Winsize
      LibC.ioctl(STDOUT.fd, TIOCGWINSZ, pointerof(ws))
      {ws.ws_row, ws.ws_col}
    end
  end
end
