#!/usr/bin/env bash
# Build the Release app, which talks to production, to use day to day.
#   scripts/release.sh            build it
#   scripts/release.sh --install  build it, then quit the copy in /Applications, replace it and open it
# It's signed with your Apple Developer team once an Apple Development certificate is in the
# Keychain (Xcode → Settings → Accounts → Manage Certificates), and ad hoc until then.
source "$(dirname "$0")/_common.sh"

RELEASE_APP="$DERIVED/Build/Products/Release/Supervibes.app"
SIGNING=Config/Signing.local.xcconfig

# The first time a certificate is there, remember its team for every build after.
if [[ ! -f "$SIGNING" ]]; then
  team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | sed -n 's/^ *organizationalUnitName *= *\([A-Z0-9]\{10\}\)$/\1/p' | head -1 || true)
  if [[ -n "$team" ]]; then
    printf '%s\n' \
      "// Written by scripts/release.sh from the Apple Development certificate in the Keychain." \
      "CODE_SIGN_STYLE = Automatic" \
      "CODE_SIGN_IDENTITY = Apple Development" \
      "DEVELOPMENT_TEAM = $team" > "$SIGNING"
    echo "Signing with team $team from now on ($SIGNING)."
  fi
fi

flags=()
if [[ -f "$SIGNING" ]]; then
  # Lets Xcode make the provisioning profile the widget's sandbox needs, with the account in Xcode.
  flags+=(-allowProvisioningUpdates)
else
  echo "No Apple Development certificate in the Keychain: signing ad hoc, which runs on this Mac."
fi

generate
xb -configuration Release ${flags[@]+"${flags[@]}"} build
echo "Built $RELEASE_APP ($(/usr/libexec/PlistBuddy -c 'Print SupervibesBaseURL' "$RELEASE_APP/Contents/Info.plist"))"
codesign -dv "$RELEASE_APP" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)=' | head -2

if [[ "${1:-}" == "--install" ]]; then
  dest=/Applications/Supervibes.app
  if pgrep -f "$dest/Contents/MacOS/Supervibes" >/dev/null; then
    osascript -e 'quit app id "com.supervibes.mac"' 2>/dev/null || pkill -f "$dest/Contents/MacOS/Supervibes" || true
    while pgrep -f "$dest/Contents/MacOS/Supervibes" >/dev/null; do sleep 0.2; done
  fi
  rm -rf "$dest"
  ditto "$RELEASE_APP" "$dest"
  open "$dest"
  echo "Installed and opened $dest"
fi
