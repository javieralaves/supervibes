#!/usr/bin/env bash
# Render the snapshot tests and list the images, so they can be opened and looked at.
#   scripts/snapshot.sh             compare against the checked-in references
#   scripts/snapshot.sh --record    re-record every reference (after an intended UI change)
# Failed comparisons write the new image and a diff to build/snapshot-failures/.
source "$(dirname "$0")/_common.sh"

record=never
if [[ "${1:-}" == "--record" ]]; then
  record=all
  shift
fi

rm -rf "$DERIVED/snapshot-failures"
status=0
SNAPSHOT_TESTING_RECORD=$record scripts/test.sh -only-testing:SupervibesTests/SurfaceSnapshotTests "$@" || status=$?

echo
echo "References:"
find "$PWD/Tests" -path '*__Snapshots__*' -name '*.png' | sort
if [[ -d "$DERIVED/snapshot-failures" ]] && [[ -n "$(find "$DERIVED/snapshot-failures" -name '*.png' 2>/dev/null)" ]]; then
  echo
  echo "Failures (new image and diff):"
  find "$PWD/$DERIVED/snapshot-failures" -name '*.png' | sort
fi

# Recording always "fails" in swift-snapshot-testing; that's expected.
if [[ "$record" == "all" ]]; then exit 0; fi
exit $status
