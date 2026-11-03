#!/bin/bash
# Installs Gap Jumper and, if needed, Hammerspoon. Safe to run again to update.
#
# Usage: ./install.sh [options]
#
# Options:
#   --no-autostart  Do not start Hammerspoon at login
#   --skip-app      Only install the files: no app install, launch or checks
#   -h, --help      Show this help
#
# Environment:
#   GAPJUMPER_CONFIG_DIR  Install into this folder instead of Hammerspoon's
#   GAPJUMPER_APP         Path to an existing Hammerspoon.app
#   GAPJUMPER_APP_DIR     Where to download Hammerspoon without Homebrew
#                         (default: /Applications, or ~/Applications)
if [ -z "${BASH_VERSION:-}" ]; then
  printf 'error: run this script with bash: bash %s\n' "$0" >&2
  exit 1
fi
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$REPO_DIR/scripts/common.sh"

MIN_MACOS=13
HAMMERSPOON_RELEASES="https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest"
HAMMERSPOON_DOWNLOADS="https://github.com/Hammerspoon/hammerspoon/releases/download/"
# The Developer ID team that signs official Hammerspoon releases.
HAMMERSPOON_TEAM_ID="VQCYSNZB89"
ACCESSIBILITY_PANE="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

autostart=true
skip_app=false
for option in "$@"; do
  case "$option" in
    --no-autostart) autostart=false ;;
    --skip-app) skip_app=true ;;
    -h | --help)
      usage "$0"
      exit 0
      ;;
    *) die "unknown option: $option (see --help)" ;;
  esac
done

check_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "Gap Jumper only runs on macOS"
  local major
  major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$major" -ge "$MIN_MACOS" ] || die "Hammerspoon needs macOS $MIN_MACOS or later"
}

# Used on Macs without Homebrew. Runs in a command substitution, so the EXIT
# trap cleans up the download however this subshell ends.
download_app() {
  local destination="${GAPJUMPER_APP_DIR:-/Applications}" url app team
  [ -d "$destination" ] && [ -w "$destination" ] || destination="$HOME/Applications"
  mkdir -p "$destination"
  url=$(curl -fsSL --proto '=https' --retry 3 "$HAMMERSPOON_RELEASES" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4 || true)
  [ -n "$url" ] || die "could not find the latest Hammerspoon release (GitHub may be rate limiting; try again later or install Homebrew)"
  case "$url" in
    "$HAMMERSPOON_DOWNLOADS"*) ;;
    *) die "unexpected Hammerspoon download URL: $url" ;;
  esac
  download_work=$(mktemp -d "${TMPDIR:-/tmp}/gapjumper.XXXXXX")
  trap 'rm -rf "$download_work"' EXIT
  info "Downloading $url" >&2
  curl -fsSL --proto '=https' --retry 3 "$url" -o "$download_work/hammerspoon.zip"
  ditto -x -k "$download_work/hammerspoon.zip" "$download_work/app"
  app="$download_work/app/Hammerspoon.app"
  [ -d "$app" ] || die "the downloaded archive does not contain Hammerspoon.app"
  codesign --verify --deep --strict "$app" \
    || die "the downloaded Hammerspoon failed its signature check"
  # Captured first: `grep -q` can exit early and SIGPIPE codesign under pipefail.
  team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)
  [ "$team" = "$HAMMERSPOON_TEAM_ID" ] \
    || die "the downloaded Hammerspoon is not signed by the Hammerspoon developers"
  spctl --assess --type execute "$app" >/dev/null 2>&1 \
    || warn "Gatekeeper did not accept the downloaded Hammerspoon; macOS may ask before opening it"
  ditto "$app" "$destination/Hammerspoon.app"
  printf '%s\n' "$destination/Hammerspoon.app"
}

ensure_app() {
  local app brew
  app=$(find_app)
  if [ -n "$app" ]; then
    printf '%s\n' "$app"
    return
  fi
  brew=$(find_brew)
  if [ -n "$brew" ]; then
    info "Installing Hammerspoon with Homebrew" >&2
    "$brew" install --cask hammerspoon >&2
    find_app
  else
    info "Homebrew not found, downloading Hammerspoon" >&2
    download_app
  fi
}

# Prints a folder's physical path, or nothing if it does not exist.
physical_dir() {
  (cd "$1" 2>/dev/null && pwd -P) || true
}

install_files() {
  local dir init src installed requires
  init=$(config_file)
  dir=$(dirname "$init")
  mkdir -p "$dir"
  src=$(physical_dir "$REPO_DIR/gapjumper")
  installed=$(physical_dir "$dir/gapjumper")
  if [ -n "$installed" ] && [ "$installed" = "$src" ]; then
    # The checkout itself (or a symlink to it) is the installed copy. Deleting
    # it would delete the source.
    info "$dir/gapjumper already points at this checkout, leaving it in place"
  else
    rm -rf "$dir/gapjumper"
    cp -R "$REPO_DIR/gapjumper" "$dir/gapjumper"
  fi
  if [ -e "$init" ] && [ ! -e "$init.gapjumper-backup" ]; then
    cp "$init" "$init.gapjumper-backup"
  fi
  touch "$init"
  add_block "$init" || die "could not update $init"
  requires=$(grep -cE "require *\(? *[\"']gapjumper[\"']" "$init" || true)
  if [ "$requires" -gt 1 ]; then
    warn "$init loads gapjumper more than once; remove your own require(\"gapjumper\") line"
  fi
}

ensure_accessibility() {
  local app="$1" state
  while :; do
    state=$(hs_eval "$app" 'return tostring(hs.accessibilityState(false))' || true)
    [ "$state" = "true" ] && return 0
    open "$ACCESSIBILITY_PANE" || true
    info "Enable Hammerspoon in System Settings > Privacy & Security > Accessibility"
    if [ ! -t 0 ]; then
      warn "run ./doctor.sh once it is enabled"
      return 0
    fi
    if ! read -r -p "Press Enter once it is enabled (Ctrl-C to finish later)... "; then
      printf '\n'
      warn "run ./doctor.sh once it is enabled"
      return 0
    fi
    # Hammerspoon does not notice the new permission until it restarts.
    restart_app "$app"
    sleep 2
  done
}

config=$(config_dir)

if [ "$skip_app" = true ]; then
  install_files
  info "Files installed in $config"
  exit 0
fi

check_macos
app=$(ensure_app)
[ -n "$app" ] || die "Hammerspoon could not be installed"
info "Using $app"

install_files
info "Files installed in $config"

reload_app "$app"
ensure_accessibility "$app"

if [ "$autostart" = true ]; then
  hs_eval "$app" 'return tostring(hs.autoLaunch(true))' >/dev/null || warn "could not enable start at login"
fi

"$REPO_DIR/doctor.sh"
