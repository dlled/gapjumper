# shellcheck shell=bash
# Helpers shared by install.sh, uninstall.sh and doctor.sh. Compatible with the
# Bash 3.2 that ships with macOS.

# Prints the comment block at the top of a script (after the shebang) as its
# help text.
usage() {
  sed -n '2,/^[^#]/{/^#/{s/^# \{0,1\}//;p;};}' "$1"
}

BLOCK_START="-- >>> gapjumper >>>"
BLOCK_END="-- <<< gapjumper <<<"

info() { printf '==> %s\n' "$1"; }
warn() { printf 'warning: %s\n' "$1" >&2; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Hammerspoon's main config file, honoring a custom MJConfigFile preference
# (set with `defaults write org.hammerspoon.Hammerspoon MJConfigFile ...`).
config_file() {
  if [ -n "${GAPJUMPER_CONFIG_DIR:-}" ]; then
    printf '%s\n' "${GAPJUMPER_CONFIG_DIR%/}/init.lua"
    return
  fi
  local custom=""
  if command -v defaults >/dev/null 2>&1; then
    custom=$(defaults read org.hammerspoon.Hammerspoon MJConfigFile 2>/dev/null || true)
  fi
  if [ -n "$custom" ]; then
    printf '%s\n' "${custom/#\~/$HOME}"
  else
    printf '%s\n' "$HOME/.hammerspoon/init.lua"
  fi
}

# Hammerspoon's config folder: the folder that holds the main config file.
config_dir() {
  dirname "$(config_file)"
}

# Homebrew, even when it is installed but not on PATH (a fresh shell on Apple
# Silicon uses /opt/homebrew, Intel uses /usr/local).
find_brew() {
  local candidate
  if command -v brew 2>/dev/null; then
    return 0
  fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

find_app() {
  local candidate
  for candidate in "${GAPJUMPER_APP:-}" "/Applications/Hammerspoon.app" "$HOME/Applications/Hammerspoon.app"; do
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  # Spotlight may be off or still indexing, so its absence is not an error.
  if command -v mdfind >/dev/null 2>&1; then
    candidate=$(mdfind "kMDItemCFBundleIdentifier == 'org.hammerspoon.Hammerspoon'" 2>/dev/null \
      | grep -vE '/\.Trash/|^/Volumes/' | head -1 || true)
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
    fi
  fi
  return 0
}

app_running() {
  pgrep -x Hammerspoon >/dev/null 2>&1
}

# Runs Lua in Hammerspoon through its bundled CLI. The CLI blocks on stdin when
# that is not a terminal, and can hang while the app starts, so each attempt
# reads from /dev/null and has a timeout.
hs_eval() {
  local app="$1" code="$2" attempts="${3:-5}" output i
  for ((i = 1; i <= attempts; i++)); do
    if output=$(perl -e 'alarm 6; exec @ARGV' "$app/Contents/Frameworks/hs/hs" -c "$code" 2>/dev/null </dev/null) \
      && [ -n "$output" ]; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 1
  done
  return 1
}

restart_app() {
  local app="$1" i
  if app_running; then
    osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6 7 8; do
      app_running || break
      sleep 1
    done
  fi
  open -g "$app"
}

# hs.reload() tears down IPC mid-call, so its exit status means nothing. Confirm
# by asking for a value afterwards, and restart if the app cannot be reached.
reload_app() {
  local app="$1"
  if app_running; then
    perl -e 'alarm 4; exec @ARGV' "$app/Contents/Frameworks/hs/hs" -c 'hs.reload()' >/dev/null 2>&1 </dev/null || true
    sleep 2
    hs_eval "$app" 'return "ready"' 3 >/dev/null && return 0
  fi
  restart_app "$app"
}

# Removes the gapjumper block, writing through symlinks so a dotfiles-managed
# init.lua stays a symlink. A start marker without a matching end marker (for
# example after a hand edit) is left alone instead of deleting the rest of the
# file.
remove_block() {
  local file="$1" temp
  [ -f "$file" ] || return 0
  grep -qxF -- "$BLOCK_START" "$file" || return 0
  temp=$(mktemp "${TMPDIR:-/tmp}/gapjumper.XXXXXX") || return 1
  if ! awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    !skipping && $0 == start { skipping = 1; held = $0 ORS; next }
    skipping && $0 == end { skipping = 0; held = ""; next }
    skipping { held = held $0 ORS; next }
    { print }
    END { if (skipping) { printf "%s", held; exit 3 } }
  ' "$file" >"$temp"; then
    rm -f "$temp"
    warn "$file has a gapjumper start marker without an end marker; fix it by hand"
    return 1
  fi
  cat "$temp" >"$file"
  rm -f "$temp"
}

add_block() {
  local file="$1"
  remove_block "$file" || return 1
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
    printf '\n' >>"$file"
  fi
  {
    printf '%s\n' "$BLOCK_START"
    printf 'require("hs.ipc")\n'
    printf 'require("gapjumper")\n'
    printf '%s\n' "$BLOCK_END"
  } >>"$file"
}
