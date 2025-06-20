#!/bin/sh
#
# Check shell scripts by doing static analysis and formatting. Based on Google
# shell style guide (https://google.github.io/styleguide/shellguide.html), with
# the following exceptions:
#   - Indentation: 4 spaces
#

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

die() {
    echo "ERROR: $*" >&2
    exit 1
}

check_script() {
    echo "Checking "$@"..."
    shfmt \
        --diff \
        --posix \
        --indent 4 \
        --case-indent \
        --space-redirects \
        --binary-next-line \
        "$@"

    shellcheck \
        --norc \
        --enable avoid-nullary-conditions,deprecate-which,quote-safe-variables,require-variable-braces \
        --exclude SC1091 \
        --shell sh \
        "$@"
}

command -v shfmt > /dev/null || die "shfmt not found."
command -v shellcheck > /dev/null || die "shellcheck not found."

[ -n "${1:-}" ] || die "ERROR: No shell script specified."

for fpath in "$@"; do
    if [ -d "${fpath}" ]; then
        find "${fpath}" -type f | while read -r f; do
            if file "${f}" | grep -q "POSIX shell script"; then
                check_script "${f}"
            fi
        done
    else
        check_script "${fpath}"
    fi
done

# vim:ft=sh:ts=4:sw=4:et:sts=4
