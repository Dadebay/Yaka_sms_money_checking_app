#!/usr/bin/env sh
# Run the app with an auto-injected build timestamp.
# Usage: tool/run.sh            (any "flutter run" flags work, e.g. --release)
# The timestamp is read at runtime via String.fromEnvironment('BUILD_TIME').
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
exec flutter run --dart-define=BUILD_TIME="$BUILD_TIME" "$@"
