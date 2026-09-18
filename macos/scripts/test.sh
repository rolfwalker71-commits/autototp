#!/bin/zsh
# Compiles the core sources together with the test harness and runs it.
set -euo pipefail
cd "${0:A:h}/.."

out=build/tests
mkdir -p "$out"
swiftc -O -swift-version 5 -target arm64-apple-macos15.0 \
    -module-name AutototpCoreTests \
    Sources/AutototpCore/*.swift Tests/AutototpCoreTests/*.swift \
    -o "$out/autototp-tests"
"$out/autototp-tests"
