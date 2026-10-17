#!/bin/sh
# Runs the check scripts on the fixtures in Scripts/Fixtures and compares the exit codes.
# Each fixture runs in a temporary copy, so the repository stays clean.

set -u
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect() { # expected-exit script fixture expected-output
    cp -R "Scripts/Fixtures/$3" "$work/$3"
    swift "Scripts/$2" --root "$work/$3" > "$work/$3.log" 2>&1
    actual=$?
    if [ "$actual" -eq "$1" ] && grep -q -- "$4" "$work/$3.log"; then
        echo "pass: $2 on $3 exits with $actual"
    else
        echo "FAIL: $2 on $3 exits with $actual, expected $1 and \"$4\". Output:"
        cat "$work/$3.log"
        failures=$((failures + 1))
    fi
}

expect 1 check-layers.swift layers-feature-import "ARCH-02 Feature package CanvasFeature depends on feature package WorkspaceFeature"
expect 0 check-layers.swift layers-clean "2 packages, 0 findings"
expect 1 assertion-density.swift density-low "1 functions, 1 checks, average 1.00 is below 2.0"
expect 0 assertion-density.swift density-ok "1 functions, 3 checks, average 3.00"

[ "$failures" -eq 0 ]
