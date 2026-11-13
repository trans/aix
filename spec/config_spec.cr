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

describe "Aix::Config's search" do
  it "follows git config's ai.path, as deep as dot-ai, over aix's own roots" do
    with_tmpdir do |root|
      make_project(File.join(root, "my", "Projects", "air", "agpt"), "handle: agpt\n")
      make_project(File.join(root, "my", "a", "b", "c", "d", "too-deep"))
      make_project(File.join(root, "mine", "only-in-aix-roots"))
      gitconfig = File.join(root, "gitconfig")
      File.write(gitconfig, "[ai]\n\tpath = #{File.join(root, "my")}\n\tpath = #{File.join(root, "gone")}\n")
      with_git_config(gitconfig) do
        Aix::Config.dot_ai_paths.should eq [File.join(root, "my"), File.join(root, "gone")]
        config = Aix::Config.new([File.join(root, "mine")], depth: 1)
        config.ai_path?.should be_true
        config.search_depth.should eq 4
        config.discover.map(&.name).should eq ["agpt"]
      end
    end
  end

  it "searches what dot-ai searches: vendor/ and the like, not node_modules/ or hidden directories" do
    with_tmpdir do |root|
      make_project(File.join(root, "app", "vendor", "lib"), "handle: lib\n")
      make_project(File.join(root, "app", "node_modules", "dep"))
      make_project(File.join(root, "app", ".cache", "hidden"))
      gitconfig = File.join(root, "gitconfig")
      File.write(gitconfig, "[ai]\n\tpath = #{root}\n")
      with_git_config(gitconfig) do
        Aix::Config.new.discover.map(&.name).should eq ["lib"]
      end
    end
  end

  it "falls back to aix's own roots and depth without ai.path" do
    with_tmpdir do |root|
      make_project(File.join(root, "one"))
      make_project(File.join(root, "one", "two", "three"))
      config = Aix::Config.new([root], depth: 1)
      config.ai_path?.should be_false
      config.search_roots.should eq [root]
      config.discover.map(&.name).should eq ["one"]
    end
  end

  it "adds and removes roots in ai.path when it follows it" do
    with_tmpdir do |root|
      Dir.mkdir_p(File.join(root, "a"))
      Dir.mkdir_p(File.join(root, "b"))
      gitconfig = File.join(root, "gitconfig")
      File.write(gitconfig, "[ai]\n\tpath = #{File.join(root, "a")}\n")
      with_git_config(gitconfig) do
        with_config(%({"roots": []})) do
          config = Aix::Config.new
          config.add_root(File.join(root, "a") + "/").should be_false
          config.add_root(File.join(root, "b")).should be_true
          Aix::Config.dot_ai_paths.should eq [File.join(root, "a"), File.join(root, "b")]
          config.roots.should be_empty
          config.remove_root(File.join(root, "a")).should be_true
          Aix::Config.dot_ai_paths.should eq [File.join(root, "b")]
          config.remove_root(File.join(root, "a")).should be_false

          Dir.mkdir_p(File.join(root, "c"))
          Dir.cd(root) { config.add_root("c").should be_true }
          Aix::Config.dot_ai_paths(expand: false).last.should eq File.join(root, "c")
          config.add_root("~/somewhere")
          Aix::Config.dot_ai_paths(expand: false).last.should eq "~/somewhere"
        end
      end
    end
  end
end
