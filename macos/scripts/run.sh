#!/usr/bin/env bash
# Build the Debug app, quit any running copy, and open the new one.
# Debug builds load http://localhost:3000, so run `npm run dev` too.
source "$(dirname "$0")/_common.sh"

generate
xb -configuration Debug build

# Quit the Debug app if it's running; an installed Release build is a separate app and keeps running.
binary="$PWD/$APP/Contents/MacOS/Supervibes Dev"
if pgrep -f "$binary" >/dev/null; then
  osascript -e 'quit app id "com.supervibes.mac.debug"' 2>/dev/null || pkill -f "$binary" || true
  while pgrep -f "$binary" >/dev/null; do sleep 0.2; done
fi

open "$APP"
echo "Running $APP"
