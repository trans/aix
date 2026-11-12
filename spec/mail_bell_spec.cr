require "./spec_helper"

# A world of its own for a bell: its socket, aix's config and git's config
# all under ROOT, so it finds no projects but the ones a spec adds.
def with_bell_world(root : String, &)
  gitconfig = File.join(root, "gitconfig")
  File.write(gitconfig, "")
  with_env({"XDG_RUNTIME_DIR" => root, "XDG_CONFIG_HOME" => root}) do
    with_git_config(gitconfig) { yield }
  end
end

describe Aix::MailBell do
  it "searches again on update, finding new projects and forgetting gone ones" do
    with_tmpdir do |root|
      with_bell_world(root) do
        projects = File.join(root, "projects")
        File.write(File.join(root, "gitconfig"), "[ai]\n\tpath = #{projects}\n")
        first = File.join(projects, "first")
        make_project(first, "handle: first\n")
        Dir.mkdir_p(File.join(first, ".ai", "mail", "inbox"))
        bell = Aix::MailBell.new
        bell.listen.should be_true
        spawn bell.run
        Fiber.yield
        Aix::MailBell.request("ping").should eq "pong"

        second = File.join(projects, "second")
        make_project(second, "handle: second\n")
        Dir.mkdir_p(File.join(second, ".ai", "mail", "inbox"))
        make_project(File.join(projects, "no-inbox"))
        Aix::MailBell.request("update").should eq "watching 2 inbox(es): 1 new, 0 gone"

        FileUtils.rm_rf(first)
        Aix::MailBell.request("update").should eq "watching 1 inbox(es): 0 new, 1 gone"
      end
    end
  end

  it "doesn't start while another bell listens" do
    with_tmpdir do |root|
      with_bell_world(root) do
        first = Aix::MailBell.new
        first.listen.should be_true
        spawn first.run
        Fiber.yield
        Aix::MailBell.new.listen.should be_false
      end
    end
  end

  it "takes over a socket a bell left behind" do
    with_tmpdir do |root|
      with_bell_world(root) do
        Dir.mkdir_p(File.dirname(Aix::MailBell.socket_path))
        File.write(Aix::MailBell.socket_path, "")
        Aix::MailBell.request("ping").should be_nil
        Aix::MailBell.new.listen.should be_true
      end
    end
  end
end
