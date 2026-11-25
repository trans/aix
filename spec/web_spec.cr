require "./spec_helper"

private def line(data) : String
  data.to_json
end

describe Aix::Transcript do
  it "shows a person's prompt, without Claude Code's reminders in it" do
    entries = Aix::Transcript.entries(line({type: "user", origin: {kind: "human"},
                                            message: {role: "user", content: "Fix **this**<system-reminder>not theirs</system-reminder>"}}))
    entries.size.should eq 1
    entries[0].kind.should eq "user"
    entries[0].html.should contain "<strong>this</strong>"
    entries[0].html.should_not contain "not theirs"
  end

  it "shows a compaction's summary as a summary, not as the person's message" do
    entries = Aix::Transcript.entries(line({type: "user", isCompactSummary: true,
                                            message: {role: "user", content: "This session is being continued…"}}))
    entries.map(&.kind).should eq ["summary"]
  end

  it "renders markdown safely: no raw HTML, no script links" do
    html = Aix::Transcript.entries(line({type: "assistant", message: {content: [
      {type: "text", text: "<script>alert(1)</script> [x](javascript:alert(1))"},
    ]}}))[0].html
    html.should_not contain "<script>"
    html.should_not contain "javascript:"
  end

  it "shows a tool call with what it does, and its result" do
    call = Aix::Transcript.entries(line({type: "assistant", message: {content: [
      {type: "thinking", thinking: "hmm", signature: "x"},
      {type: "tool_use", id: "t1", name: "Bash", input: {command: "ls -la", description: "List files"}},
    ]}}))
    call.size.should eq 1
    call[0].kind.should eq "tool"
    call[0].summary.should eq "List files"
    call[0].input.should eq "ls -la"
    result = Aix::Transcript.entries(line({type: "user", message: {content: [
      {type: "tool_result", tool_use_id: "t1", content: [{type: "text", text: "a\nb"}], is_error: true},
    ]}}))
    result[0].kind.should eq "result"
    result[0].id.should eq "t1"
    result[0].text.should eq "a\nb"
    result[0].error.should be_true
  end

  it "leaves out subagents' entries, bookkeeping, and lines it can't read" do
    Aix::Transcript.entries(line({type: "assistant", isSidechain: true, message: {content: [{type: "text", text: "x"}]}})).should be_empty
    Aix::Transcript.entries(line({type: "api-request", id: "x"})).should be_empty
    Aix::Transcript.entries("{not json").should be_empty
    Aix::Transcript.entries(line({type: "ai-title", aiTitle: "Web UI"}))[0].text.should eq "Web UI"
  end

  it "follows a transcript as it grows, a whole line at a time, even mid-character" do
    with_tmpdir do |dir|
      path = File.join(dir, "t.jsonl")
      first = line({type: "assistant", message: {content: [{type: "text", text: "one"}]}})
      second = line({type: "assistant", message: {content: [{type: "text", text: "two é"}]}})
      File.write(path, first + "\n")
      follower = Aix::Transcript::Follower.new(path)
      follower.cut?.should be_false
      follower.read.map(&.html).should eq ["<p>one</p>\n"]
      bytes = (second + "\n").to_slice
      split = second.byte_index("é".to_slice[0]).not_nil! + 1 # inside the é
      File.open(path, "a") { |file| file.write(bytes[0, split]) }
      follower.read.should be_empty
      File.open(path, "a") { |file| file.write(bytes[split..]) }
      follower.read.map(&.html).should eq ["<p>two é</p>\n"]
      follower.read.should be_empty
    end
  end

  it "reads only the end of a long transcript, from a whole line" do
    with_tmpdir do |dir|
      path = File.join(dir, "t.jsonl")
      lines = (1..50).map { |n| line({type: "assistant", message: {content: [{type: "text", text: "message #{n}"}]}}) }
      File.write(path, lines.join("\n") + "\n")
      follower = Aix::Transcript::Follower.new(path, tail: 500)
      follower.cut?.should be_true
      shown = follower.read.map(&.html)
      shown.last.should eq "<p>message 50</p>\n"
      shown.size.should be < 50
    end
  end
end

describe Aix::ProjectFiles do
  it "lists a folder, folders first, without .git" do
    with_tmpdir do |root|
      Dir.mkdir_p(File.join(root, "src"))
      Dir.mkdir_p(File.join(root, ".git"))
      File.write(File.join(root, "README.md"), "# Hi")
      items = Aix::ProjectFiles.list(root)
      items.map(&.name).should eq ["src", "README.md"]
      items[0].dir.should be_true
      Aix::ProjectFiles.list(root, "src").should be_empty
    end
  end

  it "shows markdown rendered, text as text, and not binary files" do
    with_tmpdir do |root|
      File.write(File.join(root, "README.md"), "# Hi")
      File.write(File.join(root, "a.txt"), "<b>plain</b>")
      File.write(File.join(root, "b.bin"), Bytes[1, 0, 2])
      Aix::ProjectFiles.show(root, "README.md").html.should contain "<h1>Hi</h1>"
      Aix::ProjectFiles.show(root, "a.txt").text.should eq "<b>plain</b>"
      Aix::ProjectFiles.show(root, "b.bin").kind.should eq "binary"
    end
  end

  it "refuses paths outside the project, by .. or by a link" do
    with_tmpdir do |root|
      outside = File.join(File.dirname(root), "#{File.basename(root)}-outside")
      Dir.mkdir_p(outside)
      File.write(File.join(outside, "secret"), "no")
      File.symlink(outside, File.join(root, "link"))
      expect_raises(Aix::ProjectFiles::OutsideProject) { Aix::ProjectFiles.show(root, "../#{File.basename(outside)}/secret") }
      expect_raises(Aix::ProjectFiles::OutsideProject) { Aix::ProjectFiles.show(root, "link/secret") }
      expect_raises(Aix::ProjectFiles::OutsideProject) { Aix::ProjectFiles.list(root, "/etc") }
      FileUtils.rm_rf(outside)
    end
  end
end

describe Aix::WebAuth do
  it "keeps its secret in a file only the person can read, the same from start to start" do
    with_tmpdir do |dir|
      path = File.join(dir, "aix", "web-token")
      token = Aix::WebAuth.load_token(path)
      token.size.should be >= 32
      Aix::WebAuth.load_token(path).should eq token
      File.info(path).permissions.value.should eq 0o600
    end
  end

  it "takes only its own address as the Host, when listening on this machine" do
    auth = Aix::WebAuth.new("secret", "127.0.0.1", 9292)
    auth.allowed_host?("127.0.0.1:9292").should be_true
    auth.allowed_host?("localhost:9292").should be_true
    auth.allowed_host?("evil.example:9292").should be_false
    auth.allowed_host?("127.0.0.1:9293").should be_false
    auth.allowed_host?(nil).should be_false
    auth.address.should eq "http://127.0.0.1:9292/?token=secret"
  end
end
