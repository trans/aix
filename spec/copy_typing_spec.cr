require "./spec_helper"

describe "Aix::Tmux.copy_typing_config" do
  config = Aix::Tmux.copy_typing_config({
    "q"     => "send-keys -X cancel",
    "Space" => "send-keys -X page-down",
    "n"     => %(if-shell -F "\#{==:\#{session_name},aix}" { send-keys -X cancel ; send-keys -l n }),
  })
  lines = config.lines

  it "binds the printable characters, Space, Backspace and Enter, but a key aix bound already" do
    lines.size.should eq Aix::Tmux::TYPING_KEYS.size - 1
    config.should_not contain "-T copy-mode 'n'"
  end

  it "types the key in the aix session, and keeps its own meaning elsewhere" do
    lines.should contain "bind-key -T copy-mode 'q' if-shell -F '\#{==:\#{session_name},aix}' " \
                         "{ send-keys -X cancel ; send-keys -l 'q' } { send-keys -X cancel }"
    lines.should contain "bind-key -T copy-mode 'Space' if-shell -F '\#{==:\#{session_name},aix}' " \
                         "{ send-keys -X cancel ; send-keys 'Space' } { send-keys -X page-down }"
    lines.should contain "bind-key -T copy-mode 'a' if-shell -F '\#{==:\#{session_name},aix}' " \
                         "{ send-keys -X cancel ; send-keys -l 'a' }"
  end

  it "quotes a single quote in double quotes" do
    config.should contain %(bind-key -T copy-mode "'" )
  end
end
