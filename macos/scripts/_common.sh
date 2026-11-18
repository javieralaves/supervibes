# Sourced by the other scripts. Moves to macos/ and defines shared paths.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROJECT=Supervibes.xcodeproj
SCHEME=Supervibes
DERIVED=build
APP="$DERIVED/Build/Products/Debug/Supervibes.app"

generate() {
  xcodegen generate --quiet
}

# xcodebuild with quiet, readable output: only warnings, errors and test results.
xb() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" -skipPackagePluginValidation -skipMacroValidation "$@" 2>&1 | xcbeautify --quiet --disable-logging --disable-colored-output
}
