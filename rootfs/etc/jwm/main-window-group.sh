#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

# Print beginning of configuration.
echo "\
<?xml version="1.0"?>
<JWM>"

# Print the beginning of the group.
echo "<Group>"

# Print group types, used to match the window.
MATCH_CRITERIAS=
if [ -f /etc/jwm/main-window-selection.jwmrc ]; then
    MATCH_CRITERIAS="$(cat /etc/jwm/main-window-selection.jwmrc | grep '<Type>\|<Class>\|<Name>\|<Title>\|<Option>')"
fi
echo "${MATCH_CRITERIAS:-<Type>normal</Type>}"

# Print group options.
echo "\
<Option>layer:below</Option>
<Option>maximized</Option>
<Option>nomaxtitle</Option>
<Option>nomaxborder</Option>"

# Print the end of the group.
echo "</Group>"

# Print end of configuration.
echo "</JWM>"
