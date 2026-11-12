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

describe Aix::Inotify do
  it "parses inotify events, names padded with NULs" do
    io = IO::Memory.new
    {7, 0x80_u32, "20261111-x.md"}.tap do |wd, mask, name|
      padded = name.to_slice + Bytes.new(16 - name.bytesize % 16)
      io.write_bytes(wd.to_i32, IO::ByteFormat::SystemEndian)
      io.write_bytes(mask, IO::ByteFormat::SystemEndian)
      io.write_bytes(0_u32, IO::ByteFormat::SystemEndian)
      io.write_bytes(padded.size.to_u32, IO::ByteFormat::SystemEndian)
      io.write(padded)
    end
    events = [] of {Int32, String}
    Aix::Inotify.parse(io.to_slice) { |wd, _mask, name| events << {wd, name} }
    events.should eq [{7, "20261111-x.md"}]
  end

  it "waits without stalling other fibers" do
    with_tmpdir do |dir|
      inotify = Aix::Inotify.new
      inotify.watch(dir)
      spawn { inotify.each_new_file { } }
      ticks = 0
      spawn { 3.times { sleep 10.milliseconds; ticks += 1 } }
      sleep 100.milliseconds # hangs here if the read blocks the thread
      ticks.should eq 3
    end
  end

  it "tells of a file renamed into a watched directory, as dot-ai delivers" do
    with_tmpdir do |dir|
      inotify = Aix::Inotify.new
      inotify.watch(dir).should be_true
      seen = Channel({String, String}).new
      spawn { inotify.each_new_file { |d, name| seen.send({d, name}) } }
      File.write(File.join(dir, ".delivering.md"), "hi")
      File.rename(File.join(dir, ".delivering.md"), File.join(dir, "msg.md"))
      found = nil
      loop do
        select
        when event = seen.receive
          (found = event; break) if event[1] == "msg.md"
        when timeout(2.seconds)
          break
        end
      end
      found.should eq({dir, "msg.md"})
    end
  end
end
