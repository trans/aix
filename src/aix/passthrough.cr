require "./session"
require "./terminal"

module Aix
  class Passthrough
    @got_tab = false

    # Run passthrough I/O for the given session.
    # Returns when Tab+Enter is detected or the session ends.
    def run(session : Session) : Symbol
      @got_tab = false
      result = :session_ended
      done = Channel(Symbol).new(1)
      output_stopped = Channel(Nil).new(1)

      Terminal.raw!

      # Force Claude to do a full redraw by faking a resize:
      # shrink by 1 row, SIGWINCH, brief pause, restore real size, SIGWINCH
      rows, cols = Terminal.winsize
      if session.running?
        session.resize(rows - 1, cols)
        LibC.kill(session.pid, Signal::WINCH.value)
        sleep 50.milliseconds
        session.resize(rows, cols)
        LibC.kill(session.pid, Signal::WINCH.value)
      end

      # Handle SIGWINCH
      Signal::WINCH.trap do
        r, c = Terminal.winsize
        session.resize(r, c)
      end

      # Make STDIN non-blocking for fiber-friendly reads
      stdin_was_blocking = STDIN.blocking
      STDIN.blocking = false

      # Track whether we're still active
      active = true

      # Fiber: PTY master → STDOUT (session output to terminal)
      spawn do
        buffer = Bytes.new(4096)
        loop do
          break unless active
          n = session.read(buffer)
          if n
            STDOUT.write(buffer[0, n])
            STDOUT.flush
          else
            break
          end
        end
        output_stopped.send(nil) rescue nil
        done.send(:session_ended) rescue nil
      end

      # Fiber: STDIN → PTY master (user input to session)
      # Watches for Tab (0x09) followed by Enter (0x0D or 0x0A)
      spawn do
        buffer = Bytes.new(1)
        tab_byte = Bytes[0x09]

        loop do
          break unless active
          begin
            n = STDIN.read(buffer)
            break if n == 0
          rescue IO::Error
            break
          end

          byte = buffer[0]

          if @got_tab
            if byte == 0x0D || byte == 0x0A
              done.send(:escape) rescue nil
              break
            else
              session.write(tab_byte)
              @got_tab = false
              session.write(buffer[0, 1])
            end
          elsif byte == 0x09
            @got_tab = true
          else
            session.write(buffer[0, 1])
          end
        end
        done.send(:session_ended) rescue nil
      end

      # Wait for first signal
      result = done.receive
      active = false

      # Wait briefly for output fiber to stop writing to STDOUT
      select
      when output_stopped.receive
      when timeout(0.2.seconds)
      end

      # Restore terminal state
      Terminal.restore!
      STDIN.blocking = stdin_was_blocking

      Signal::WINCH.reset

      # Reap child if it exited
      session.reap

      result
    end
  end
end
