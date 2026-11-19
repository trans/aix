require "./spec_helper"

describe "Aix.argument_problem" do
  it "takes the options aix knows, with their values" do
    Aix.argument_problem([] of String).should be_nil
    Aix.argument_problem(["--repl"]).should be_nil
    Aix.argument_problem(["--web", "--host", "0.0.0.0", "--port", "9393"]).should be_nil
    Aix.argument_problem(["--web", "--port=9393"]).should be_nil
    Aix.argument_problem(["--mcp"]).should be_nil
  end

  it "refuses anything else, rather than starting the TUI" do
    Aix.argument_problem(["--verison"]).should eq "unknown option '--verison'"
    Aix.argument_problem(["status"]).should eq "unknown option 'status'"
    Aix.argument_problem(["--web", "9393"]).should eq "unknown option '9393'"
  end

  it "refuses a value option without its value" do
    Aix.argument_problem(["--web", "--port"]).should eq "--port needs a value"
    Aix.argument_problem(["--web", "--port="]).should eq "--port needs a value"
    Aix.argument_problem(["--web", "--host", "--repl"]).should eq "--host needs a value"
  end
end
