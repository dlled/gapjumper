#!/bin/bash
# Checks that Gap Jumper works on this Mac and prints its map of display edges.
# Exits non-zero if anything needs attention.
#
# Usage: ./doctor.sh [options]
#
# Options:
#   -h, --help  Show this help
#
# Environment:
#   GAPJUMPER_CONFIG_DIR  Check this folder instead of Hammerspoon's
if [ -z "${BASH_VERSION:-}" ]; then
  printf 'error: run this script with bash: bash %s\n' "$0" >&2
  exit 1
fi
# No -e: every check should run and report, even after one fails.
set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$REPO_DIR/scripts/common.sh"

for option in "$@"; do
  case "$option" in
    -h | --help)
      usage "$0"
      exit 0
      ;;
    *) die "unknown option: $option (see --help)" ;;
  esac
done

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n        %s\n' "$1" "$2"; failures=$((failures + 1)); }

printf 'macOS %s on %s\n' "$(sw_vers -productVersion)" "$(uname -m)"

init=$(config_file)
config=$(dirname "$init")
app=$(find_app)

if [ -n "$app" ]; then
  pass "Hammerspoon $(defaults read "$app/Contents/Info" CFBundleShortVersionString) at $app"
else
  fail "Hammerspoon is not installed" "Run ./install.sh"
  exit 1
fi

if [ -f "$config/gapjumper/init.lua" ] && grep -qxF -- "$BLOCK_START" "$init" 2>/dev/null; then
  pass "Installed in $config"
else
  fail "Not installed in $config" "Run ./install.sh"
  exit 1
fi

if diff -rq "$REPO_DIR/gapjumper" "$config/gapjumper" >/dev/null; then
  pass "Installed files match this checkout"
else
  fail "Installed files differ from this checkout" "Run ./install.sh to update them"
fi

if app_running; then
  pass "Hammerspoon is running"
else
  fail "Hammerspoon is not running" "Open it, or run ./install.sh"
  exit 1
fi

status=$(hs_eval "$app" 'return gapJumper.status()') || {
  fail "Gap Jumper is not responding" "Check the Hammerspoon console for errors, then run ./install.sh"
  exit 1
}

value() { printf '%s\n' "$status" | sed -n "s/^$1=//p"; }

if [ "$(value accessibility)" = "true" ]; then
  pass "Accessibility permission granted"
else
  fail "Accessibility permission missing" \
    "Enable Hammerspoon in System Settings > Privacy & Security > Accessibility, then restart it"
fi

if [ "$(value tap)" = "true" ]; then
  pass "Listening to the mouse"
else
  fail "Not listening to the mouse" "Restart Hammerspoon"
fi

pass "$(value displays) display(s) detected"

if [ "$(value autostart)" = "true" ]; then
  pass "Starts at login"
else
  printf '  note  Does not start at login\n'
fi

problems=$(value problem)
if [ -z "$problems" ]; then
  pass "Layout validated: every jump lands on its target and every display is reachable"
else
  while IFS= read -r problem; do
    fail "Problem found" "$problem"
  done <<<"$problems"
fi

printf '\nDisplay edges:\n'
hs_eval "$app" 'return gapJumper.report()' || printf '  (could not read the report)\n'

if [ "$failures" -gt 0 ]; then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
printf '\nAll checks passed\n'
