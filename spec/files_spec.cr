require "./spec_helper"

describe Aix::Files do
  it "keeps each agent's browsing directory privately, and starts there while it exists" do
    with_tmpdir do |state|
      with_env({"XDG_STATE_HOME" => state}) do
        Aix::Files.cwd_file("wc").should eq File.join(state, "aix", "browse", "wc")
        Aix::Files.remembered("wc").should be_nil
        Dir.mkdir_p(Aix::Files.dir)
        File.write(Aix::Files.cwd_file("wc"), "#{state}\n")
        Aix::Files.remembered("wc").should eq state
        File.write(Aix::Files.cwd_file("wc"), File.join(state, "gone"))
        Aix::Files.remembered("wc").should be_nil
      end
    end
  end

  it "writes aix's own yazi settings once, and leaves them to the person after" do
    with_tmpdir do |config|
      with_env({"XDG_CONFIG_HOME" => config}) do
        dir = Aix::Files.config_dir
        dir.should eq File.join(config, "aix", "yazi")
        settings = File.join(dir, "yazi.toml")
        File.read(settings).should contain "ratio = [0, 1, 1]"
        File.write(settings, "# mine\n")
        Aix::Files.config_dir
        File.read(settings).should eq "# mine\n"
      end
    end
  end

  it "needs a window to toggle" do
    Aix::Files.toggle(nil).should eq 2
  end
end
