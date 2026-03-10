require "./tmux"

module Aix
  class Passthrough
    # Attach to the tmux session. Blocks until the user detaches (Ctrl+\).
    def run(session : Session) : Symbol
      Tmux.select_window(session.name)
      Tmux.attach

      # If we get here, the user detached
      if session.running?
        :escape
      else
        :session_ended
      end
    end
  end
end
