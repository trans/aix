# aix's tasks. `just --list` shows them.

# Where `just install` puts aix: `$PREFIX/bin`, `~/.local/bin` by default.
prefix := env("PREFIX", home_directory() / ".local")
bindir := prefix / "bin"

# Build aix, optimized, into bin/
build:
    shards build --release

# Run the specs
test:
    crystal spec

# Build, then install aix into ~/.local/bin (or $PREFIX/bin)
install: build
    install -Dm755 bin/aix "{{ bindir }}/aix"
    @echo "installed {{ bindir }}/aix"
    @found="$(command -v aix)"; [ "$found" = "{{ bindir }}/aix" ] || echo "note: \`aix\` on PATH is $found, not this one: put {{ bindir }} ahead of it"

# Remove what `just install` installed
uninstall:
    rm -f "{{ bindir }}/aix"
