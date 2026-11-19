#!/bin/bash
# Builds and signs the two Shortcuts that turn Do Not Disturb on and off for sessions, into
# Supervibes/Shortcuts/. The app ships them so turning Do Not Disturb on in Settings is one click
# ("Add Shortcut") rather than building them by hand. Signing needs this Mac signed in to iCloud.
# Rerun only when the Shortcuts need to change; the signed files are checked in.
set -euo pipefail
cd "$(dirname "$0")/.."

out="Supervibes/Shortcuts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out"

python3 - "$work" <<'EOF'
import plistlib, sys

work = sys.argv[1]

def shortcut(enabled):
    return {
        "WFWorkflowClientVersion": "2607.0.3",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFQuickActionSurfaces": [],
        # One action: Set Focus, turning Do Not Disturb on (until turned off) or off.
        "WFWorkflowActions": [{
            "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
            "WFWorkflowActionParameters": {
                "Operation": "Turn",
                "Enabled": 1 if enabled else 0,
                "AssertionType": "Turned Off",
                "FocusModes": {"Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"},
            },
        }],
    }

# The file name becomes the Shortcut's name; SessionRoutine.focusOn/focusOff must match.
for name, enabled in [("Supervibes Do Not Disturb On", True), ("Supervibes Do Not Disturb Off", False)]:
    with open(f"{work}/{name}.shortcut", "wb") as f:
        plistlib.dump(shortcut(enabled), f, fmt=plistlib.FMT_BINARY)
EOF

for name in "Supervibes Do Not Disturb On" "Supervibes Do Not Disturb Off"; do
  shortcuts sign --mode anyone --input "$work/$name.shortcut" --output "$out/$name.shortcut"
  echo "Signed $out/$name.shortcut"
done
