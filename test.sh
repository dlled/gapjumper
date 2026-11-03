#!/bin/bash
# Runs every test suite and exits non-zero if any of them fails.
# Needs Lua 5.3 or later (macOS: brew install lua, Debian/Ubuntu: apt install
# lua5.4). ShellCheck runs when it is installed.
# Set GAPJUMPER_SEED to reproduce a failure in the randomized layout tests.
set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$REPO_DIR" || exit 1

lua_bin=""
for candidate in lua lua5.4 lua5.3 lua54 lua53; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_bin=$(command -v "$candidate")
    break
  fi
done
if [ -z "$lua_bin" ]; then
  printf 'error: Lua not found. Install it with "brew install lua" (macOS) or "apt install lua5.4" (Linux)\n' >&2
  exit 1
fi

failed=""

"$lua_bin" tests/run.lua || failed="$failed lua"
/bin/bash tests/install_test.sh || failed="$failed install"

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck install.sh uninstall.sh doctor.sh test.sh scripts/common.sh tests/install_test.sh; then
    printf 'shellcheck: ok\n'
  else
    failed="$failed shellcheck"
  fi
else
  printf 'shellcheck: skipped (not installed)\n'
fi

if [ -n "$failed" ]; then
  printf 'FAILED:%s\n' "$failed" >&2
  exit 1
fi
printf 'all tests passed\n'
