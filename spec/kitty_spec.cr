require "./spec_helper"

describe Aix::Abduco do
  it "reads its list: running, attached or not, and exited" do
    text = "Active sessions (on host neo14)\n" \
           "* Wed\t 2026-11-25 13:24:09\tarcana\n" \
           "  Wed\t 2026-11-25 13:25:00\tmemo-2\n" \
           "+ Wed\t 2026-11-25 13:26:06\tair\n"
    sessions = Aix::Abduco.parse_list(text)
    sessions["arcana"].should eq Aix::Abduco::State::Running
    sessions["memo-2"].should eq Aix::Abduco::State::Running
    sessions["air"].should eq Aix::Abduco::State::Exited
    sessions.size.should eq 3
  end

  it "reads an empty list" do
    Aix::Abduco.parse_list("Active sessions (on host neo14)\n").should be_empty
  end

  it "starts a session attached, and attaches to one" do
    Aix::Abduco.create_command("air", ["claude", "--resume", "x"]).should eq ["abduco", "-c", "air", "claude", "--resume", "x"]
    Aix::Abduco.attach_command("air").should eq ["abduco", "-a", "air"]
  end
end

describe Aix::Kitty do
  it "finds the agents' windows in kitty's list, and which has the keyboard" do
    json = [
      {is_focused: true, tabs: [
        {is_active: false, windows: [
          {id: 1, title: "aix", is_active: true, user_vars: {} of String => String},
        ]},
        {is_active: true, windows: [
          {id: 2, title: "✳ Lost memories", is_active: true, user_vars: {"aix_agent" => "arcana"}},
        ]},
        {is_active: false, windows: [
          {id: 3, title: "Codex", is_active: true, user_vars: {"aix_agent" => "onboard"}},
        ]},
      ]},
    ].to_json
    windows = Aix::Kitty.parse_ls(json)
    windows.map(&.agent).should eq ["arcana", "onboard"]
    windows[0].id.should eq 2
    windows[0].title.should eq "✳ Lost memories"
    windows[0].focused.should be_true
    windows[1].focused.should be_false
  end

  it "reads a screen and its cursor from get-text" do
    text = "Claude Code\n────\n❯ \n────\n\e[?25h\e[3;3H\e[?12h"
    lines, x, y = Aix::Kitty.parse_screen(text)
    lines.should eq ["Claude Code", "────", "❯ ", "────"]
    {x, y}.should eq({2, 2})
  end

  it "reads a screen whose cursor is hidden" do
    lines, x, y = Aix::Kitty.parse_screen("menu\n\e[?25l\e[16;2H\e[?12h")
    lines.should eq ["menu"]
    {x, y}.should eq({1, 15})
  end

  it "names keys as kitty does, from tmux's names" do
    Aix::Kitty.key_name("Enter").should eq "enter"
    Aix::Kitty.key_name("BSpace").should eq "backspace"
    Aix::Kitty.key_name("BTab").should eq "shift+tab"
    Aix::Kitty.key_name("C-c").should eq "ctrl+c"
    Aix::Kitty.key_name("Up").should eq "up"
    Aix::Kitty.key_name("1").should eq "1"
  end

  it "writes a watcher that labels a tab with the agent's handle" do
    Aix::Kitty::WATCHER.should contain "def on_title_change(boss, window, data):"
    Aix::Kitty::WATCHER.should contain "user_vars.get('aix_agent')"
    Aix::Kitty::WATCHER.should contain %(f'@{name}\\n{title}')
  end
end

describe Aix::Config do
  it "keeps the terminal setting, tmux by default" do
    Aix::Config.new.terminal.should eq "tmux"
  end
end
