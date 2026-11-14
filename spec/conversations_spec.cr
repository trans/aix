require "./spec_helper"

describe Aix::Conversations do
  describe ".lock_holders" do
    it "reads who holds each file from the kernel's table, skipping those waiting" do
      with_tmpdir do |dir|
        table = File.join(dir, "locks")
        File.write(table, <<-TABLE)
          18: FLOCK  ADVISORY  WRITE 2029232 00:2f:2017312970 0 EOF
          24: FLOCK  ADVISORY  WRITE 2991163 103:02:2017954227 0 EOF
          24: -> FLOCK  ADVISORY  WRITE 3000000 103:02:2017954227 0 EOF
          TABLE
        holders = Aix::Conversations.lock_holders(table)
        holders[{0x00_i64, 0x2f_i64, 2017312970_u64}].should eq 2029232
        holders[{0x103_i64, 0x02_i64, 2017954227_u64}].should eq 2991163
        holders.size.should eq 2
      end
    end

    it "sees no locks where there's no table" do
      Aix::Conversations.lock_holders("/nonexistent/locks").should be_empty
    end
  end

  describe ".codex_open" do
    it "finds a locked Codex conversation, its directory from its session file" do
      with_tmpdir do |home|
        id = "01a1d68e-a16b-7882-8379-ad77715eb48c"
        Dir.mkdir_p(File.join(home, "thread-writer-locks"))
        lock = File.join(home, "thread-writer-locks", "#{id}.lock")
        File.write(lock, "")
        File.write(File.join(home, "thread-writer-locks", "01a1-unlocked.lock"), "")
        day = File.join(home, "sessions", "2026", "11", "14")
        Dir.mkdir_p(day)
        File.write(File.join(day, "rollout-2026-11-14T10-00-00-#{id}.jsonl"),
          %({"type":"session_meta","payload":{"id":"#{id}","cwd":"/home/me/Projects/x"}}\n{"type":"event"}\n))
        major, minor, inode = Aix::Conversations.file_key(lock).not_nil!
        table = File.join(home, "locks")
        File.write(table, "1: FLOCK  ADVISORY  WRITE #{Process.pid} #{major.to_s(16)}:#{minor.to_s(16)}:#{inode} 0 EOF\n")

        found = Aix::Conversations.codex_open(home, table)
        found.size.should eq 1
        directory, open = found.first
        directory.should eq "/home/me/Projects/x"
        open.harness.should eq Aix::Harness::Kind::Codex
        open.id.should eq id
        open.pid.should eq Process.pid
        open.where.should eq "a terminal"
      end
    end
  end

  describe ".claude_open" do
    it "finds a running Claude Code session, but not one whose process is gone" do
      with_tmpdir do |config|
        Dir.mkdir_p(File.join(config, "sessions"))
        claude = Process.new("bash", ["-c", "exec -a claude sleep 30"])
        begin
          sleep 100.milliseconds
          File.write(File.join(config, "sessions", "#{claude.pid}.json"),
            %({"pid":#{claude.pid},"sessionId":"abc","cwd":"/home/me/Projects/y","entrypoint":"cli"}))
          File.write(File.join(config, "sessions", "999999999.json"),
            %({"pid":999999999,"sessionId":"gone","cwd":"/home/me/Projects/y","entrypoint":"cli"}))
          found = Aix::Conversations.claude_open(config)
          found.map { |dir, open| {dir, open.id, open.where} }.should eq [{"/home/me/Projects/y", "abc", "a terminal"}]
        ensure
          claude.terminate
          claude.wait
        end
      end
    end
  end

  describe ".blocking" do
    codex = Aix::Conversations::Open.new(Aix::Harness::Kind::Codex, "c1", 10_i64, "VS Code")
    claude = Aix::Conversations::Open.new(Aix::Harness::Kind::Claude, "abc", 11_i64, "a terminal")

    it "counts any of a project's Codex conversations open elsewhere, since resume --last's pick isn't known" do
      Aix::Conversations.blocking([codex], Aix::Harness::Kind::Codex, nil).should eq codex
      Aix::Conversations.blocking([claude], Aix::Harness::Kind::Codex, nil).should be_nil
    end

    it "counts a Claude Code conversation only if it's the one resume would take" do
      Aix::Conversations.blocking([claude], Aix::Harness::Kind::Claude, "abc").should eq claude
      Aix::Conversations.blocking([claude], Aix::Harness::Kind::Claude, "other").should be_nil
      Aix::Conversations.blocking([claude], Aix::Harness::Kind::Claude, nil).should be_nil
    end
  end
end

describe "Aix::Harness.claude_resume_target" do
  it "is the session's own conversation if its transcript is there, else the newest" do
    with_tmpdir do |config|
      transcripts = File.join(config, "projects", Aix::Harness.project_key("/home/me/p"))
      Dir.mkdir_p(transcripts)
      Aix::Harness.claude_resume_target("/home/me/p", nil, config).should be_nil
      File.write(File.join(transcripts, "old.jsonl"), "")
      File.touch(File.join(transcripts, "old.jsonl"), Time.utc - 1.hour)
      File.write(File.join(transcripts, "new.jsonl"), "")
      Aix::Harness.claude_resume_target("/home/me/p", nil, config).should eq "new"
      Aix::Harness.claude_resume_target("/home/me/p", "old", config).should eq "old"
      Aix::Harness.claude_resume_target("/home/me/p", "missing", config).should eq "new"
    end
  end
end
