#!/usr/bin/env bash
# The app's own logs (subsystem com.supervibes.mac).
#   scripts/logs.sh        stream live
#   scripts/logs.sh 5m     show the last five minutes, then exit
set -euo pipefail

predicate='subsystem == "com.supervibes.mac"'

if [[ -n "${1:-}" ]]; then
  log show --last "$1" --style compact --info --debug --predicate "$predicate"
else
  log stream --style compact --level debug --predicate "$predicate"
fi
