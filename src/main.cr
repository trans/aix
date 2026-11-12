# The aix command. `src/aix.cr` only defines Aix, so specs can require it
# without launching the TUI.
require "./aix"

Aix.run
