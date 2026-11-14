require "./spec_helper"

# Lines captured from a Claude Code 2.1.322 pane on 2026-11-11.
RULE  = "─" * 60
# Claude Code puts a no-break space (U+00A0) after its mark.
EMPTY = %(❯\u00A0Try "how does <filepath> work?")
DRAFT = "❯\u00A0half a thought"

describe Aix::Bell do
  describe ".prompt_empty?" do
    it "is true at the empty input box, hint text after the cursor" do
      Aix::Bell.prompt_empty?([RULE, EMPTY, RULE], 2).should be_true
    end

    it "is false with a draft before the cursor" do
      Aix::Bell.prompt_empty?([RULE, DRAFT, RULE], 16).should be_false
    end

    it "is false with interrupted text put back in the box" do
      Aix::Bell.prompt_empty?([RULE, "❯ You have mail in .ai/mail/inbox/.", RULE], 35).should be_false
    end

    it "is false at a menu that uses the same mark (no rules around it)" do
      Aix::Bell.prompt_empty?(["", " ❯ No, exit", "   Yes, I trust this folder"], 2).should be_false
    end

    it "takes the older boxed prompt" do
      Aix::Bell.prompt_empty?(["╭" + "─" * 20 + "╮", "│ >                  │", "╰" + "─" * 20 + "╯"], 4).should be_true
    end

    it "is false without the three lines" do
      Aix::Bell.prompt_empty?([EMPTY], 2).should be_false
    end
  end

  describe ".decide" do
    it "rings an idle session at an empty prompt" do
      Aix::Bell.decide("idle", user_typing: false, prompt_empty: true)[0].should eq Aix::Bell::Result::Rung
    end

    it "rings a session idle with a background command running (status shell)" do
      Aix::Bell.decide("shell", user_typing: false, prompt_empty: true)[0].should eq Aix::Bell::Result::Rung
    end

    it "leaves a busy or waiting session to the Stop hook" do
      Aix::Bell.decide("busy", user_typing: false, prompt_empty: true)[0].should eq Aix::Bell::Result::Busy
      Aix::Bell.decide("waiting", user_typing: false, prompt_empty: true)[0].should eq Aix::Bell::Result::Busy
    end

    it "holds without a status, as during a startup dialog" do
      Aix::Bell.decide(nil, user_typing: false, prompt_empty: true)[0].should eq Aix::Bell::Result::Held
    end

    it "holds while the user is typing there, or with a draft in the box" do
      Aix::Bell.decide("idle", user_typing: true, prompt_empty: true)[0].should eq Aix::Bell::Result::Held
      Aix::Bell.decide("idle", user_typing: false, prompt_empty: false)[0].should eq Aix::Bell::Result::Held
    end
  end

  describe "Result#exit_status" do
    it "gives dot-ai's runner statuses" do
      Aix::Bell::Result::Rung.exit_status.should eq 0
      Aix::Bell::Result::Busy.exit_status.should eq 0
      Aix::Bell::Result::Channel.exit_status.should eq 0
      Aix::Bell::Result::NotOpen.exit_status.should eq 3
      Aix::Bell::Result::Held.exit_status.should eq 4
    end
  end
end

describe "Aix::Bell, for Codex" do
  # Codex 0.167.2's input line, as `capture-pane -e` gives it.
  empty = "\e[1m›\e[0m \e[2mAsk Codex to do anything\e[0m"

  it "sees an empty input line: the mark, the cursor after it, and only dim text" do
    Aix::Bell.codex_prompt_empty?(empty, 2).should be_true
    Aix::Bell.codex_prompt_empty?("\e[1m›\e[0m ", 2).should be_true
  end

  it "doesn't take a draft, which isn't dim, for empty" do
    Aix::Bell.codex_prompt_empty?("\e[1m›\e[0m draft text", 2).should be_false
    Aix::Bell.codex_prompt_empty?("\e[1m›\e[0m draft text", 12).should be_false
  end

  it "doesn't take a menu's entry after the same mark for an input line" do
    Aix::Bell.codex_prompt_empty?("\e[36m› 1. Yes, proceed\e[39m", 2).should be_false
  end

  it "doesn't read a colour's numbers as dim" do
    Aix::Bell.codex_prompt_empty?("\e[38;2;2;2;2m›\e[39m \e[38;2;246;226;183mtext\e[39m", 2).should be_false
  end

  it "holds with a reason of its own when there's no record yet" do
    result, reason = Aix::Bell.decide(nil, user_typing: false, prompt_empty: true, unknown: "no record yet")
    result.should eq Aix::Bell::Result::Held
    reason.should eq "no record yet"
  end
end
