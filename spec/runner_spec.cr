require "./spec_helper"

# Run the block with dot-ai's state folder under ROOT.
def with_state(root : String, &)
  with_env({"XDG_STATE_HOME" => root}) { yield }
end

def write_record(id : String, fields : String) : String
  dir = File.join(Aix::Runner.state_dir, "sessions")
  Dir.mkdir_p(dir)
  path = File.join(dir, "#{Aix::Runner.session_key(id)}.session")
  File.write(path, fields)
  path
end

# A process id that has just exited.
def gone_pid : Int64
  process = Process.new("true")
  process.wait
  process.pid.to_i64
end

describe Aix::Runner do
  it "registers aix: one line, its absolute path, private to the person" do
    with_tmpdir do |root|
      with_state(root) do
        Aix::Runner.register("/opt/aix/bin/aix").should be_true
        path = File.join(root, "dot-ai", "runners", "aix")
        File.read(path).should eq "/opt/aix/bin/aix\n"
        File.info(File.dirname(path)).permissions.value.should eq 0o700
        (File.info(path).permissions.value & 0o022).should eq 0
        Dir.children(File.dirname(path)).should eq ["aix"] # no hidden file left
        Aix::Runner.register("/home/me/.local/bin/aix").should be_true
        File.read(path).should eq "/home/me/.local/bin/aix\n"
      end
    end
  end

  it "doesn't register a program not named aix, such as a crystal eval's" do
    with_tmpdir do |root|
      with_state(root) do
        Aix::Runner.register("/home/me/.cache/crystal/crystal-run-eval.tmp").should be_false
        File.exists?(File.join(root, "dot-ai", "runners", "aix")).should be_false
      end
    end
  end

  it "finds the record of the session in a pane by its process, the newest open one" do
    with_tmpdir do |root|
      with_state(root) do
        dir = File.join(root, "dot-ai", "sessions")
        Dir.mkdir_p(dir)
        File.write(File.join(dir, "old.session"), "root=/p\nagent=codex\nid=old\nby=aix\npid=4242\nstate=ended\n")
        File.write(File.join(dir, "new.session"), "root=/p\nagent=codex\nid=new\nby=aix\npid=4242\nstate=idle\n")
        record = Aix::Runner.record_in_pane(4242).not_nil!
        record.id.should eq "new"
        record.agent.should eq "codex"
        record.state.should eq "idle"
        Aix::Runner.record_in_pane(4343).should be_nil
      end
    end
  end

  it "keys a record by the session id, made safe for a file name" do
    Aix::Runner.session_key("01a1-ce58/x y").should eq "01a1-ce58_x_y"
  end

  describe ".not_in_pane" do
    it "is 3 for a session with no record, or one already ended" do
      with_tmpdir do |root|
        with_state(root) do
          Aix::Runner.not_in_pane("nope")[0].should eq 3
          write_record("done", "id=done\nby=aix\nstate=ended\n")
          Aix::Runner.not_in_pane("done")[0].should eq 3
        end
      end
    end

    it "is 4 while the session's process lives: one an aix session started" do
      with_tmpdir do |root|
        with_state(root) do
          write_record("child", "id=child\nby=aix\npid=#{Process.pid}\nstate=busy\n")
          Aix::Runner.not_in_pane("child")[0].should eq 4
        end
      end
    end

    it "is 4 when the record names no process to check" do
      with_tmpdir do |root|
        with_state(root) do
          write_record("codex", "agent=codex\nid=codex\nby=aix\nstate=idle\n")
          Aix::Runner.not_in_pane("codex")[0].should eq 4
        end
      end
    end

    it "is 3 once the process is gone, marking aix's record ended" do
      with_tmpdir do |root|
        with_state(root) do
          path = write_record("old", "root=/p\nid=old\nby=aix\npid=#{gone_pid}\nstate=idle\n")
          Aix::Runner.not_in_pane("old")[0].should eq 3
          File.read(path).should contain "state=ended\n"
          File.read(path).should contain "root=/p\n"
        end
      end
    end

    it "leaves another runner's record alone" do
      with_tmpdir do |root|
        with_state(root) do
          path = write_record("toms", "id=toms\nby=tom\npid=#{gone_pid}\nstate=idle\n")
          Aix::Runner.not_in_pane("toms")[0].should eq 3
          File.read(path).should contain "state=idle"
        end
      end
    end
  end
end
