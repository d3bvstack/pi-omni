#!/bin/sh
# Prepares the container for the agent, then execs whatever was requested.
set -eu

# bin/pi runs the container as the host user's uid on rootful Docker. That uid
# usually has no /etc/passwd entry and inherits a HOME it cannot write, so fall
# back to a scratch home: git, npm and pi always need somewhere to put state.
if ! { [ -n "${HOME:-}" ] && mkdir -p "$HOME" 2>/dev/null && [ -w "$HOME" ]; }; then
    HOME=/tmp/pi-home
    mkdir -p "$HOME"
    export HOME
fi

# The mounted project usually has a different owner than the agent process,
# which git refuses to work with by default.
if [ -d "$PI_WORKSPACE/.git" ]; then
    git config --global --add safe.directory "$PI_WORKSPACE" 2>/dev/null || true
fi

cat >&2 <<EOF
[pi] workspace  $PI_WORKSPACE
[pi] agent dir  $PI_CODING_AGENT_DIR
[pi] home       $HOME
[pi] run /login to authenticate a provider
EOF

exec "$@"
