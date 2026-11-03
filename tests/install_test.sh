#!/bin/bash
# Tests install.sh and uninstall.sh against temporary config folders. Never
# touches the real Hammerspoon config.
# Checks are single-quoted on purpose: check() evaluates them.
# shellcheck disable=SC2016,SC2034
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=scripts/common.sh
source "$REPO_DIR/scripts/common.sh"

# Stand-ins for the macOS tools the scripts call, so the tests never find,
# reload or restart the Hammerspoon that is really running on this Mac.
STUBS="$WORK/stubs"
mkdir -p "$STUBS"
for tool in pgrep mdfind defaults osascript open; do
  printf '#!/bin/sh\nexit 1\n' >"$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done
export PATH="$STUBS:$PATH"
export GAPJUMPER_APP="$WORK/no such app"

passed=0
failed=0
check() {
  if eval "$2"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$1"
  fi
}

blocks() { grep -cF -- '-- >>> gapjumper >>>' "$1" || true; }

run() {
  (cd / && GAPJUMPER_CONFIG_DIR="$1" "$REPO_DIR/$2" "${@:3}") >/dev/null
}

# Fresh install, in a path with spaces
fresh="$WORK/a config dir"
run "$fresh" install.sh --skip-app
check "creates init.lua" '[ -f "$fresh/init.lua" ]'
check "copies the module" '[ -f "$fresh/gapjumper/init.lua" ] && [ -f "$fresh/gapjumper/geometry.lua" ]'
check "adds the block" '[ "$(blocks "$fresh/init.lua")" = 1 ]'
check "block found the way doctor.sh looks for it" 'grep -qF -- "$BLOCK_START" "$fresh/init.lua"'
check "no backup of a file that did not exist" '[ ! -e "$fresh/init.lua.gapjumper-backup" ]'

# Running it again changes nothing
before=$(cat "$fresh/init.lua")
run "$fresh" install.sh --skip-app
check "idempotent" '[ "$(cat "$fresh/init.lua")" = "$before" ]'

# An existing config survives
existing="$WORK/existing"
mkdir -p "$existing"
printf 'hs.alert.show("mine")' >"$existing/init.lua"
run "$existing" install.sh --skip-app
check "keeps existing lines" 'grep -qF "hs.alert.show(\"mine\")" "$existing/init.lua"'
check "block on its own line" 'grep -qxF -- "-- >>> gapjumper >>>" "$existing/init.lua"'
check "backs up the original" '[ "$(cat "$existing/init.lua.gapjumper-backup")" = "hs.alert.show(\"mine\")" ]'

# Reinstalling keeps user settings
printf 'return { MIN_PUSH = 20 }\n' >"$existing/gapjumper_config.lua"
run "$existing" install.sh --skip-app
check "keeps user settings" '[ -f "$existing/gapjumper_config.lua" ]'

# Updates replace stale files
touch "$existing/gapjumper/stale.lua"
run "$existing" install.sh --skip-app
check "removes stale files" '[ ! -e "$existing/gapjumper/stale.lua" ]'

# Uninstall removes only what install added
run "$existing" uninstall.sh
check "removes the module" '[ ! -e "$existing/gapjumper" ]'
check "removes the block" '[ "$(blocks "$existing/init.lua")" = 0 ]'
check "leaves existing lines" 'grep -qF "hs.alert.show(\"mine\")" "$existing/init.lua"'
check "leaves user settings" '[ -f "$existing/gapjumper_config.lua" ]'

# A dotfiles-managed init.lua stays a symlink
dotfiles="$WORK/dotfiles"
linked="$WORK/linked"
mkdir -p "$dotfiles" "$linked"
printf -- '-- dotfiles\n' >"$dotfiles/init.lua"
ln -s "$dotfiles/init.lua" "$linked/init.lua"
run "$linked" install.sh --skip-app
check "symlink preserved" '[ -L "$linked/init.lua" ]'
check "block written to the real file" '[ "$(blocks "$dotfiles/init.lua")" = 1 ]'
run "$linked" uninstall.sh
check "symlink preserved on uninstall" '[ -L "$linked/init.lua" ]'

# A config without a trailing newline keeps its last line intact
printf 'return 1' >"$WORK/nonl"
add_block "$WORK/nonl"
check "no trailing newline: last line intact" '[ "$(head -1 "$WORK/nonl")" = "return 1" ]'

# Lines after the block survive its removal
after="$WORK/after"
mkdir -p "$after"
printf 'first\n' >"$after/init.lua"
run "$after" install.sh --skip-app
printf 'last\n' >>"$after/init.lua"
run "$after" install.sh --skip-app
check "block not duplicated when lines follow it" '[ "$(blocks "$after/init.lua")" = 1 ]'
check "lines after the block are kept" 'grep -qxF last "$after/init.lua"'
check "backup is not overwritten" '[ "$(cat "$after/init.lua.gapjumper-backup")" = first ]'
run "$after" uninstall.sh
check "uninstall restores the original lines" '[ "$(cat "$after/init.lua")" = "$(printf "first\nlast")" ]'

# Uninstall is safe on a folder where nothing was installed, and twice
empty="$WORK/empty"
mkdir -p "$empty"
run "$empty" uninstall.sh
check "uninstall without an install creates nothing" '[ ! -e "$empty/init.lua" ]'
run "$empty" uninstall.sh
check "uninstall twice succeeds" 'true'

# The block loads what it should
check "block loads hs.ipc and the module" 'grep -qxF "require(\"hs.ipc\")" "$fresh/init.lua" \
  && grep -qxF "require(\"gapjumper\")" "$fresh/init.lua"'

# The installed module matches the checkout
check "installed files match the checkout" 'diff -rq "$REPO_DIR/gapjumper" "$fresh/gapjumper" >/dev/null'

# Bad options are rejected before anything is written
bad="$WORK/bad"
check "unknown option fails" '! run "$bad" install.sh --skip-app --nope 2>/dev/null'
check "unknown option writes nothing" '[ ! -e "$bad" ]'

# The config folder follows Hammerspoon's MJConfigFile preference
check "default config folder" '[ "$(unset GAPJUMPER_CONFIG_DIR; HOME=/h config_dir)" = /h/.hammerspoon ]'
printf '#!/bin/sh\necho "~/dots/hs/init.lua"\n' >"$STUBS/defaults"
check "custom MJConfigFile with a tilde" \
  '[ "$(unset GAPJUMPER_CONFIG_DIR; HOME=/h config_dir)" = /h/dots/hs ]'
printf '#!/bin/sh\nexit 1\n' >"$STUBS/defaults"
check "GAPJUMPER_CONFIG_DIR wins" '[ "$(GAPJUMPER_CONFIG_DIR=/x config_dir)" = /x ]'

# Nothing hard-codes a machine
check "no absolute home paths" '! grep -rIE "/(Users|home)/[a-z]" "$REPO_DIR" \
  --exclude-dir=.git --exclude=install_test.sh >/dev/null'

printf 'install: %d checks, %d failures\n' "$((passed + failed))" "$failed"
[ "$failed" -eq 0 ]
