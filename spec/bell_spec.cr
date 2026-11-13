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
