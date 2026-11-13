require "spec"
require "file_utils"
require "../src/aix"

# Specs read no one's real git config: a project search would otherwise
# follow the machine's `ai.path`. `with_git_config` gives one its own.
EMPTY_GITCONFIG = File.tempname("aix-spec-gitconfig")
File.write(EMPTY_GITCONFIG, "")
ENV["GIT_CONFIG_GLOBAL"] = EMPTY_GITCONFIG
ENV["GIT_CONFIG_NOSYSTEM"] = "1"
at_exit { File.delete?(EMPTY_GITCONFIG) }

# A fresh, empty directory for one example, removed afterwards.
def with_tmpdir(&)
  dir = File.tempname("aix-spec")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

# Make DIR a project: a `.ai/` directory, with `config.yml` holding CONFIG
# when given.
def make_project(dir : String, config : String? = nil)
  Dir.mkdir_p(File.join(dir, ".ai"))
  File.write(File.join(dir, ".ai", "config.yml"), config) if config
end

# Run the block with these environment variables set, then put them back.
def with_env(vars : Hash(String, String), &)
  saved = vars.keys.to_h { |key| {key, ENV[key]?} }
  vars.each { |key, value| ENV[key] = value }
  begin
    yield
  ensure
    saved.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
  end
end

# Run the block with git reading only GITCONFIG as its global config.
def with_git_config(gitconfig : String, &)
  with_env({"GIT_CONFIG_GLOBAL" => gitconfig, "GIT_CONFIG_NOSYSTEM" => "1"}) { yield }
end
