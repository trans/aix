require "./spec_helper"

describe Aix::Config do
  describe ".agent_name" do
    it "is the handle in .ai/config.yml" do
      with_tmpdir do |dir|
        make_project(dir, "handle: oyl\n")
        Aix::Config.agent_name(dir).should eq "oyl"
      end
    end

    it "drops a quoted handle's @" do
      with_tmpdir do |dir|
        make_project(dir, %(handle: "@oyl"\n))
        Aix::Config.agent_name(dir).should eq "oyl"
      end
    end

    it "reads the older arcana.handle" do
      with_tmpdir do |dir|
        make_project(dir, "arcana:\n  handle: \"@older\"\n")
        Aix::Config.agent_name(dir).should eq "older"
      end
    end

    it "falls back to the directory's name, folded as Arcana folds it" do
      with_tmpdir do |root|
        circus = File.join(root, "Silicon.Circus")
        make_project(circus)
        Aix::Config.agent_name(circus).should eq "silicon-circus"

        digits = File.join(root, "2048")
        make_project(digits)
        Aix::Config.agent_name(digits).should eq "agent-2048"
      end
    end

    it "falls back when the handle wouldn't make a tmux window name" do
      with_tmpdir do |root|
        dir = File.join(root, "proj")
        make_project(dir, "handle: \"two words\"\n")
        Aix::Config.agent_name(dir).should eq "proj"
      end
    end
  end

  describe "#discover" do
    it "finds projects inside projects, in tree order" do
      with_tmpdir do |root|
        make_project(File.join(root, "alpha"), "handle: alpha\n")
        make_project(File.join(root, "alpha", "beta"), "handle: beta\n")
        make_project(File.join(root, "Gamma"))
        make_project(File.join(root, "node_modules", "skipped"))
        make_project(File.join(root, ".hidden"))

        projects = Aix::Config.new([root], depth: 2).discover

        projects.map(&.name).should eq ["alpha", "beta", "gamma"]
        beta = projects.find! { |p| p.name == "beta" }
        beta.parent.should eq "alpha"
        beta.level.should eq 1
        projects.find! { |p| p.name == "gamma" }.parent.should be_nil
      end
    end

    it "doesn't follow symbolic links, so a linked project is found once" do
      with_tmpdir do |root|
        make_project(File.join(root, "mjanime"), "handle: mj\n")
        File.symlink(File.join(root, "mjanime"), File.join(root, "minanime"))
        projects = Aix::Config.new([root], depth: 1).discover
        projects.map(&.name).should eq ["mj"]
        projects.first.directory.should eq File.join(File.realpath(root), "mjanime")
      end
    end

    it "doesn't descend past depth" do
      with_tmpdir do |root|
        make_project(File.join(root, "alpha"))
        make_project(File.join(root, "alpha", "beta"))
        Aix::Config.new([root], depth: 1).discover.map(&.name).should eq ["alpha"]
      end
    end
  end

  describe ".load" do
    it "has the mail channel off when the config doesn't mention it: the bell is the default" do
      with_config(%({"roots": ["~/Projects"]})) do
        config = Aix::Config.load
        config.roots.should eq ["~/Projects"]
        config.mail_channel.should be_false
      end
    end

    it "reads mail.channel: true, and saves it" do
      with_config(%({"roots": [], "mail": {"channel": true}})) do
        config = Aix::Config.load
        config.mail_channel.should be_true
        config.save
        Aix::Config.load.mail_channel.should be_true
      end
    end
  end
end

# Run the block with XDG_CONFIG_HOME pointing at a temporary directory whose
# aix/config.json holds JSON.
def with_config(json : String, &)
  with_tmpdir do |dir|
    Dir.mkdir_p(File.join(dir, "aix"))
    File.write(File.join(dir, "aix", "config.json"), json)
    saved = ENV["XDG_CONFIG_HOME"]?
    ENV["XDG_CONFIG_HOME"] = dir
    begin
      yield
    ensure
      saved ? (ENV["XDG_CONFIG_HOME"] = saved) : ENV.delete("XDG_CONFIG_HOME")
    end
  end
end

describe "Aix::Config.mail_search" do
  it "searches git config's ai.path, as deep as dot-ai's carrier" do
    with_tmpdir do |root|
      make_project(File.join(root, "my", "Projects", "air", "agpt"), "handle: agpt\n")
      make_project(File.join(root, "my", "a", "b", "c", "d", "too-deep"))
      gitconfig = File.join(root, "gitconfig")
      File.write(gitconfig, "[ai]\n\tpath = #{File.join(root, "my")}\n\tpath = #{File.join(root, "gone")}\n")
      with_git_config(gitconfig) do
        Aix::Config.dot_ai_paths.should eq [File.join(root, "my"), File.join(root, "gone")]
        Aix::Config.mail_search.discover.map(&.name).should eq ["agpt"]
      end
    end
  end

  it "falls back to aix's own roots without ai.path" do
    with_tmpdir do |root|
      gitconfig = File.join(root, "gitconfig")
      File.write(gitconfig, "")
      with_git_config(gitconfig) do
        Aix::Config.dot_ai_paths.should be_empty
        Aix::Config.mail_search.roots.should eq Aix::Config.load.roots
      end
    end
  end
end
