#!/usr/bin/env bash
# Run the test suite. Extra arguments go to xcodebuild, e.g.:
#   scripts/test.sh -only-testing:SupervibesTests/MenuBarTests/testMenuBarDuringBlock
source "$(dirname "$0")/_common.sh"

generate
mkdir -p "$DERIVED/snapshot-failures"
# TEST_RUNNER_* variables are passed to the test process without the prefix.
# Times are written in the Mac's locale, so the tests always run in US English (12-hour clock),
# whatever region the Mac is set to; the references were recorded that way.
TEST_RUNNER_SNAPSHOT_ARTIFACTS="$PWD/$DERIVED/snapshot-failures" \
TEST_RUNNER_SNAPSHOT_TESTING_RECORD="${SNAPSHOT_TESTING_RECORD:-never}" \
  xb -configuration Debug test -testLanguage en -testRegion US "$@"
