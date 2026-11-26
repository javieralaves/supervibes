#!/usr/bin/env bash
# Render the snapshot tests and list their images, so they can be opened and looked at.
#   scripts/snapshot.sh                        compare every snapshot test against its references
#   scripts/snapshot.sh --record               re-record every reference (after an intended UI change)
#   scripts/snapshot.sh [--record] NAME...     only these: a test (testWeekView), a class
#                                              (SeasonTests) or both (SeasonTests/testSeasonPage)
# Arguments starting with "-" go to xcodebuild. Failed comparisons write the new image and a
# diff to build/snapshot-failures/.
source "$(dirname "$0")/_common.sh"

TARGET=SupervibesTests
SNAPSHOTS=Tests/Snapshots/__Snapshots__

record=never
if [[ "${1:-}" == "--record" ]]; then
  record=all
  shift
fi

# The class a test is declared in, from its func; fails unless exactly one declares it.
class_of() {
  local files
  files=$(grep -l "func $1()" Tests/Snapshots/*.swift 2>/dev/null || true)
  if [[ -z "$files" ]]; then
    echo "No snapshot test named $1." >&2
    return 1
  fi
  if [[ $(echo "$files" | wc -l) -gt 1 ]]; then
    echo "$1 is in more than one class; name it as Class/$1." >&2
    return 1
  fi
  sed -n 's/.*class \([A-Za-z0-9_]*\): XCTestCase.*/\1/p' "$files" | head -1
}

filters=()   # -only-testing arguments
globs=()     # the reference images they cover, to list afterwards
passthrough=()
for arg in "$@"; do
  if [[ "$arg" == -* ]]; then
    passthrough+=("$arg")
  elif [[ "$arg" == */* ]]; then
    filters+=("-only-testing:$TARGET/$arg")
    globs+=("$PWD/$SNAPSHOTS/${arg%%/*}/${arg#*/}.*png")
  elif [[ -d "$SNAPSHOTS/$arg" ]]; then
    filters+=("-only-testing:$TARGET/$arg")
    globs+=("$PWD/$SNAPSHOTS/$arg/*.png")
  else
    class=$(class_of "$arg") || exit 1
    filters+=("-only-testing:$TARGET/$class/$arg")
    globs+=("$PWD/$SNAPSHOTS/$class/$arg.*png")
  fi
done

# Nothing named: every class with references.
if [[ ${#filters[@]} -eq 0 ]]; then
  for dir in "$SNAPSHOTS"/*/; do
    filters+=("-only-testing:$TARGET/$(basename "$dir")")
  done
  globs+=("$PWD/$SNAPSHOTS/*/*.png")
fi

rm -rf "$DERIVED/snapshot-failures"
status=0
SNAPSHOT_TESTING_RECORD=$record scripts/test.sh "${filters[@]}" ${passthrough[@]+"${passthrough[@]}"} || status=$?

echo
echo "References:"
# Unquoted on purpose: each glob expands to its images.
ls -1 ${globs[@]} 2>/dev/null | sort || true
if [[ -d "$DERIVED/snapshot-failures" ]] && [[ -n "$(find "$DERIVED/snapshot-failures" -name '*.png' 2>/dev/null)" ]]; then
  echo
  echo "Failures (new image and diff):"
  find "$PWD/$DERIVED/snapshot-failures" -name '*.png' | sort
fi

# Recording always "fails" in swift-snapshot-testing; that's expected.
if [[ "$record" == "all" ]]; then exit 0; fi
exit $status
