#!/bin/sh
# Runs the performance suites alone, each run in a new test process (D-177).
# Usage: Scripts/perf-runs.sh <name> <first> <last> <device> <suites...>
# The bundles go to .build/Perf/<name>-<n>.xcresult. Keep the iPad unlocked during the runs.

set -u
cd "$(dirname "$0")/.." || exit 1
name=$1 first=$2 last=$3 device=$4
shift 4
only=""
for suite in "$@"; do only="$only -only-testing:PointerDeviceTests/$suite"; done
data=.build/DeviceData
common="-project Pointer.xcodeproj -scheme PointerApp -configuration Release \
    -destination id=$device -derivedDataPath $data -allowProvisioningUpdates \
    ENABLE_TESTABILITY=YES -quiet"
mkdir -p .build/Perf
if [ "$first" -eq 1 ]; then
    # The bundles of an earlier set go, or the compare reads the runs of another build through
    # its glob (review of 2026-10-28).
    rm -rf ".build/Perf/$name"-[0-9]*.xcresult
    # shellcheck disable=SC2086
    xcodebuild build-for-testing $common > ".build/Perf/$name-build.log" 2>&1 || {
        cat ".build/Perf/$name-build.log"
        exit 1
    }
fi
run=$first
while [ "$run" -le "$last" ]; do
    if ! xcrun devicectl device info lockState --device "$device" 2>&1 \
        | grep -q "passcodeRequired: false"; then
        echo "The iPad is locked. Unlock it and run again."
        exit 1
    fi
    bundle=".build/Perf/$name-$run.xcresult"
    rm -rf "$bundle"
    # shellcheck disable=SC2086
    xcodebuild test-without-building $common $only -resultBundlePath "$bundle" \
        > ".build/Perf/$name-$run.log" 2>&1
    echo "perf run $run of $last: exit $?"
    run=$((run + 1))
done
