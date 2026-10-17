#!/bin/sh
# Runs the check scripts and the SwiftLint rules on the fixtures in Scripts/Fixtures and compares
# the results. Each fixture runs in a temporary copy, so the repository stays clean.

set -u
cd "$(dirname "$0")/.." || exit 1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

fail() { # message log
    echo "FAIL: $1 Output:"
    cat "$2"
    failures=$((failures + 1))
}

expect() { # expected-exit script fixture expected-output...
    code=$1 script=$2 fixture=$3
    shift 3
    cp -R "Scripts/Fixtures/$fixture" "$work/$fixture"
    swift "Scripts/$script" --root "$work/$fixture" > "$work/$fixture.log" 2>&1
    actual=$?
    if [ "$actual" -ne "$code" ]; then
        fail "$script on $fixture exits with $actual, expected $code." "$work/$fixture.log"
        return
    fi
    for line in "$@"; do
        if ! grep -q -- "$line" "$work/$fixture.log"; then
            fail "$script on $fixture does not print \"$line\"." "$work/$fixture.log"
            return
        fi
    done
    echo "pass: $script on $fixture exits with $actual"
}

# The fixture must give exactly the rule identifiers in its expected-rules.txt, or none.
expect_lint() { # fixture
    cp -R "Scripts/Fixtures/$1" "$work/$1"
    cp .swiftlint.yml "$work/$1/.swiftlint.yml"
    (cd "$work/$1" && swiftlint lint --strict --quiet) > "$work/$1.log" 2>&1
    sed -n 's/.*(\([a-z0-9_]*\))$/\1/p' "$work/$1.log" | sort -u > "$work/$1.rules"
    expected="$work/$1/expected-rules.txt"
    [ -f "$expected" ] || expected=/dev/null
    if diff "$expected" "$work/$1.rules" > "$work/$1.diff"; then
        echo "pass: swiftlint on $1 gives $(wc -l < "$work/$1.rules" | tr -d ' ') rules"
    else
        cat "$work/$1.diff" >> "$work/$1.log"
        fail "swiftlint on $1 gives other rules than expected (diff at the end)." "$work/$1.log"
    fi
}

expect 1 check-layers.swift layers-feature-import \
    "ARCH-02 Feature package CanvasFeature depends on feature package WorkspaceFeature"
expect 1 check-layers.swift layers-upward \
    "ARCH-02 Model (layer 0) depends on Persistence (layer 1)"
expect 1 check-layers.swift layers-third-party \
    "BUILD-03 The project has a remote package" \
    "BUILD-03 The project references the package Vendor/Library" \
    "BUILD-03 The project references a prebuilt framework" \
    "BUILD-03 CanvasFeature has the binary target Prebuilt" \
    "BUILD-03 CanvasFeature depends on .*Vendor/Library, which is not a Pointer package" \
    "1 packages, 5 findings"
expect 0 check-layers.swift layers-clean "2 packages, 0 findings"
expect 1 assertion-density.swift density-low "1 functions, 1 checks, average 1.00 is below 2.0"
expect 1 assertion-density.swift density-syntax "3 functions, 4 checks, average 1.33 is below 2.0"
expect 0 assertion-density.swift density-ok "1 functions, 3 checks, average 3.00"
expect_lint lint-violations
expect_lint lint-clean

[ "$failures" -eq 0 ]
