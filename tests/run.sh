#!/bin/sh
# Runs the whole suite: unit tests, then the D-Bus tests against fake
# NetworkManager and firewalld services, all on a private session bus that
# disappears with the run. Extra arguments go to qmltestrunner.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
runner=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}

exec dbus-run-session --config-file="$here/dbus/session.conf" -- sh -c '
    here=$1 runner=$2
    shift 2
    python3 -I "$here/dbus/fake_services.py" &
    fake=$!
    if ! gdbus wait --session --timeout 10 net.rcspam.firewallzone.TestControl; then
        echo "run.sh: the fake D-Bus services did not start" >&2
        kill "$fake" 2>/dev/null
        exit 1
    fi
    status=0
    "$runner" -input "$here" "$@" || status=$?
    kill "$fake"
    wait "$fake" 2>/dev/null || true
    exit "$status"
' sh "$here" "$runner" "$@"
