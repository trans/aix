require "./term"
require "./screens"

module Aix
  class Passthrough
    # Attach to the tmux session. Blocks until the user detaches (Ctrl+\).
    # In kitty, the agent's tab comes to the front instead, and the console
    # goes on in its own.
    def run(session : Session) : Symbol
      if Term.kitty?
        Term.focus(session.name, session.directory)
        return :escape
      end
      Tmux.select_window(session.name)
      Tmux.attach

      # If we get here, the user detached. Keep the screen they left (or
      # the last one, if its agent exited), for the TUI's preview.
      Screens.capture(session.name)
      if session.running?
        :escape
      else
        :session_ended
      end
    end
  end
end
