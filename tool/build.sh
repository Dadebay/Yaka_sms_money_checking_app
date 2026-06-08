#!/usr/bin/env sh
# Build the app with an auto-injected build timestamp.
# Usage: tool/build.sh apk        (any "flutter build" target + flags work)
#        tool/build.sh appbundle --release
# The timestamp is read at runtime via String.fromEnvironment('BUILD_TIME').
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
exec flutter build "$@" --dart-define=BUILD_TIME="$BUILD_TIME" 
