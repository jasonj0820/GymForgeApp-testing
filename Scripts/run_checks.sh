#!/bin/zsh
# Compiles the platform-independent logic (Shared/) with the checks and runs them. Needs Xcode command line tools.
set -e
cd "$(dirname "$0")/.."
swiftc -parse-as-library Shared/*.swift Widgets/Cluck.swift Widgets/QuoteLibrary.swift Tests/ProgressionEngineTests.swift -o /tmp/gymforge_checks
/tmp/gymforge_checks
