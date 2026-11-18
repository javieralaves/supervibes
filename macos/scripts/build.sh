#!/usr/bin/env bash
# Generate the project and build the Debug app. Prints only warnings and errors.
source "$(dirname "$0")/_common.sh"

generate
xb -configuration Debug build
echo "Built $APP"
