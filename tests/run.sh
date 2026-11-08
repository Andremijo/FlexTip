#!/usr/bin/env bash
# Lint the addon and run the mock-based tests. Needs lua5.1 and luacheck.
set -euo pipefail
cd "$(dirname "$0")/.."
luacheck Core.lua Tooltip.lua Mover.lua Options.lua
for test in tests/test_*.lua; do
    lua5.1 "$test" tests .
done
