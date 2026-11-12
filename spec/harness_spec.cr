require "./spec_helper"

describe Aix::Harness do
  describe ".claude_args" do
    it "puts dot-ai's mail channel first when it's on and installed" do
      Aix::Harness.claude_args(["--resume", "abc"], true, installed: true)
        .should eq ["--dangerously-load-development-channels", "plugin:dot-ai@dot-ai", "--resume", "abc"]
    end

    it "leaves the arguments alone when the channel is off" do
      Aix::Harness.claude_args(["--continue"], false, installed: true).should eq ["--continue"]
    end

    it "leaves the arguments alone when the dot-ai plugin isn't installed" do
      Aix::Harness.claude_args(["--continue"], true, installed: false).should eq ["--continue"]
    end

    it "doesn't add a second development channel option" do
      args = ["--dangerously-load-development-channels", "server:other"]
      Aix::Harness.claude_args(args, true, installed: true).should eq args
    end
  end

  describe ".channel?" do
    it "sees dot-ai's development channel, or --channels" do
      Aix::Harness.channel?(["--dangerously-load-development-channels", "plugin:dot-ai@dot-ai"]).should be_true
      Aix::Harness.channel?(["--channels", "plugin:dot-ai@dot-ai"]).should be_true
      Aix::Harness.channel?(["--resume", "abc"]).should be_false
    end
  end

  describe ".session_env" do
    it "names aix as the runner of a session without a channel" do
      Aix::Harness.session_env(["--continue"]).should eq({"DOT_AI_BY" => "aix"})
    end

    it "leaves a channel session to dot-ai, whose channel pushes to it" do
      Aix::Harness.session_env(["--dangerously-load-development-channels", "plugin:dot-ai@dot-ai"]).should be_empty
    end
  end

  describe ".claude_session" do
    it "reads Claude Code's session file for a pid" do
      with_tmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "sessions"))
        File.write(File.join(dir, "sessions", "4242.json"),
          %({"pid": 4242, "sessionId": "abc-123", "status": "idle", "cwd": "/x"}))
        session = Aix::Harness.claude_session(4242_i64, dir).not_nil!
        session.session_id.should eq "abc-123"
        session.status.should eq "idle"
        Aix::Harness.claude_pid("abc-123", dir).should eq 4242
        Aix::Harness.claude_session(4343_i64, dir).should be_nil
      end
    end
  end

  describe ".parent_pid and .process_args" do
    it "reads this process from /proc" do
      Aix::Harness.parent_pid(Process.pid).should eq Process.ppid
      Aix::Harness.process_args(Process.pid).should_not be_empty
    end
  end

  describe ".dot_ai_installed?" do
    it "finds dot-ai in Claude Code's plugin registry" do
      with_tmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "plugins"))
        File.write(File.join(dir, "plugins", "installed_plugins.json"),
          %({"version": 2, "plugins": {"dot-ai@dot-ai": [{"scope": "user"}]}}))
        Aix::Harness.dot_ai_installed?(dir).should be_true
      end
    end

    it "is false when the registry has other plugins only" do
      with_tmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "plugins"))
        File.write(File.join(dir, "plugins", "installed_plugins.json"),
          %({"version": 2, "plugins": {"other@market": []}}))
        Aix::Harness.dot_ai_installed?(dir).should be_false
      end
    end

    it "is false without a registry, or with a malformed one" do
      with_tmpdir do |dir|
        Aix::Harness.dot_ai_installed?(dir).should be_false
        Dir.mkdir_p(File.join(dir, "plugins"))
        File.write(File.join(dir, "plugins", "installed_plugins.json"), "{not json")
        Aix::Harness.dot_ai_installed?(dir).should be_false
      end
    end
  end
end
