#!/usr/bin/env bash
# Build the Debug app, quit any running copy, and open the new one.
# Debug builds load http://localhost:3000, so run `npm run dev` too.
source "$(dirname "$0")/_common.sh"

generate
xb -configuration Debug build

if pgrep -x Supervibes >/dev/null; then
  osascript -e 'quit app id "com.supervibes.mac"' 2>/dev/null || pkill -x Supervibes || true
  while pgrep -x Supervibes >/dev/null; do sleep 0.2; done
fi

open "$APP"
echo "Running $APP"
