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
expect 1 check-layers.swift layers-access-import \
    "ARCH-02 Model (layer 0) depends on Persistence (layer 1)"
expect 0 check-layers.swift layers-clean "2 packages, 0 findings"
expect 1 assertion-density.swift density-low \
    "Scale.swift:5: error: CONTRACT-02 A function of 11 lines has no contract check."
expect 1 assertion-density.swift density-syntax \
    "Syntax.swift:22: error: CONTRACT-02 A function of 11 lines has no contract check." \
    "3 functions, 4 checks, average 1.33"
expect 0 assertion-density.swift density-ok "1 functions, 3 checks, average 3.00"
expect 1 assertion-density.swift density-nested \
    "Nested.swift:5: error: CONTRACT-02 A function of 12 lines has no contract check."
expect 1 assertion-density.swift density-error-exit \
    "Exits.swift:4: error: CONTRACT-02 A function of 11 lines has no contract check." \
    "Exits.swift:48: error: CONTRACT-02 A function of 11 lines has no contract check." \
    "3 functions, 1 checks, average 0.33"
expect 0 coverage.swift coverage-ok "Geometry: 90.00 % (90 of 100 lines)" \
    "Persistence: 95.00 % (95 of 100 lines)" "Rendering: 70.00 % (70 of 100 lines)" \
    "Export: 70.00 % (70 of 100 lines)"
expect 1 coverage.swift coverage-low "TEST-02 Geometry: 89.00 % (89 of 100 lines) is below 90 %" \
    "TEST-02 Rendering: 69.00 % (69 of 100 lines) is below 70 %" \
    "TEST-02 Export: 69.00 % (69 of 100 lines) is below 70 %"
expect 1 coverage.swift coverage-missing "TEST-02 Rendering: no report at"
# The compare of performance samples (D-172, D-177). The critical U values of 10 runs against
# 10 come from the published two-tailed tables: U <= 16 for p < 0.01, U <= 23 for p < 0.05.
expect_perf() { # expected-exit runs-file expected-output
    cp -R Scripts/Fixtures/perf "$work/perf"
    swift Scripts/perf.swift record --output "$work/perf/baseline.json" --commit fixture \
        --device fixture --os fixture --xcode fixture "$work/perf/base-runs.json" > /dev/null
    swift Scripts/perf.swift compare --baseline "$work/perf/baseline.json" "$work/perf/$2" \
        > "$work/perf-$2.log" 2>&1
    actual=$?
    rm -rf "$work/perf"
    if [ "$actual" -ne "$1" ] || ! grep -q -- "$3" "$work/perf-$2.log"; then
        fail "perf.swift on $2 exits with $actual, expected $1 and \"$3\"." "$work/perf-$2.log"
        return
    fi
    echo "pass: perf.swift on $2 exits with $actual"
}

expect_perf 0 same.json "pass: A/t.ms: base 10.45, new 10.5, +0.5 %"
expect_perf 1 slow.json "fail: A/t.ms: base 10.45, new 11.85, +13.4 %, p 1.1e-05"
expect_perf 1 critical-16.json "fail: A/t.ms: base 10.45, new 12.25, +17.2 %, p 0.0089"
expect_perf 3 unsure.json "unsure: A/t.ms: base 10.45, new 12.15, +16.3 %, p 0.043"
expect_perf 1 missing.json "missing: A/t.ms: missing in the new runs"
expect_perf 1 slow.json "recorded: A/peak.mb: base 104.5, new 204.5"
# The nesting tool of FLOW-04 (D-175). It is a package, so it builds once before the fixtures.
swift build -c release --package-path Scripts/Nesting --quiet || exit 1
expect_nesting() { # expected-exit fixture expected-output
    Scripts/Nesting/.build/release/Nesting --root "Scripts/Fixtures/$2" > "$work/$2.log" 2>&1
    actual=$?
    if [ "$actual" -ne "$1" ] || ! grep -q -- "$3" "$work/$2.log"; then
        fail "Nesting on $2 exits with $actual, expected $1 and \"$3\"." "$work/$2.log"
        return
    fi
    echo "pass: Nesting on $2 exits with $actual"
}

expect_nesting 1 nesting-deep "Deep.swift:3: error: FLOW-04 deep nests 4 levels deep at line 8"
expect_nesting 0 nesting-ok "nesting: 1 files, 0 functions over 3 levels"
expect_lint lint-violations
expect_lint lint-pdf-context
expect_lint lint-clean

[ "$failures" -eq 0 ]
