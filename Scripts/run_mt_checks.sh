#!/bin/zsh
# More Training routine and progression rules (Foundation-only). Needs the Swift toolchain.
set -e
cd "$(dirname "$0")/.."
swiftc -parse-as-library iOS/Private/MTModels.swift iOS/Private/MTProgression.swift Tests/MTChecks.swift -o /tmp/gymforge_mt_checks
/tmp/gymforge_mt_checks
