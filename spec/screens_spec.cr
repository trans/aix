require "./spec_helper"

describe Aix::Screens do
  it "fits the bottom of a screen: trailing blank lines dropped, lines cut" do
    screen = "one\ntwo is longer\nthree\n\n\n   \n"
    Aix::Screens.fit(screen, 5, 2).should eq "two i\nthree"
    Aix::Screens.fit(screen, 20, 10).should eq "one\ntwo is longer\nthree"
  end

  it "counts a wide character as two columns" do
    Aix::Screens.fit("日本語です", 5, 1).should eq "日本"
    Aix::Screens.fit("ok ✓ done", 9, 1).should eq "ok ✓ done"
  end

  it "wraps text at spaces to fit a width" do
    Aix::Screens.wrap("its conversation is open in a terminal\nUntick Resume", 16)
      .should eq "its conversation\nis open in a\nterminal\nUntick Resume"
  end

  it "fits nothing into no room" do
    Aix::Screens.fit("text", 0, 3).should eq ""
    Aix::Screens.fit("text", 3, 0).should eq ""
  end

  it "saves a screen privately and reads it back" do
    with_tmpdir do |root|
      with_env({"XDG_STATE_HOME" => root}) do
        Aix::Screens.load("proj").should be_nil
        Aix::Screens.save("proj", "where it left off\n")
        Aix::Screens.load("proj").should eq "where it left off\n"
        File.info(Aix::Screens.dir).permissions.value.should eq 0o700
        Dir.children(Aix::Screens.dir).should eq ["proj"]
        Aix::Screens.preview("aix-spec-no-such-window", width: 8, height: 1).should be_nil
        Aix::Screens.save("aix-spec-no-such-window", "where it left off\n")
        Aix::Screens.preview("aix-spec-no-such-window", width: 8, height: 1).should eq "where it"
      end
    end
  end
end
