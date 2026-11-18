#!/usr/bin/env bash
# Run the test suite. Extra arguments go to xcodebuild, e.g.:
#   scripts/test.sh -only-testing:SupervibesTests/SurfaceSnapshotTests/testMenuBarDuringBlock
source "$(dirname "$0")/_common.sh"

generate
mkdir -p "$DERIVED/snapshot-failures"
# TEST_RUNNER_* variables are passed to the test process without the prefix.
TEST_RUNNER_SNAPSHOT_ARTIFACTS="$PWD/$DERIVED/snapshot-failures" \
TEST_RUNNER_SNAPSHOT_TESTING_RECORD="${SNAPSHOT_TESTING_RECORD:-never}" \
  xb -configuration Debug test "$@"
