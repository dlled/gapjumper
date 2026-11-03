#!/bin/bash
# Removes Gap Jumper. Hammerspoon itself, gapjumper_config.lua and the
# init.lua.gapjumper-backup made by the first install are kept.
#
# Usage: ./uninstall.sh [options]
#
# Options:
#   -h, --help  Show this help
#
# Environment:
#   GAPJUMPER_CONFIG_DIR  Uninstall from this folder instead of Hammerspoon's
if [ -z "${BASH_VERSION:-}" ]; then
  printf 'error: run this script with bash: bash %s\n' "$0" >&2
  exit 1
fi
set -euo pipefail

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

init=$(config_file)
config=$(dirname "$init")
remove_block "$init" || die "could not update $init"

installed=$( (cd "$config/gapjumper" 2>/dev/null && pwd -P) || true)
checkout=$(cd "$REPO_DIR/gapjumper" && pwd -P)
if [ -L "$config/gapjumper" ]; then
  rm -f "$config/gapjumper"
elif [ -n "$installed" ] && [ "$installed" = "$checkout" ]; then
  # Never delete the checkout this script runs from.
  warn "$config/gapjumper is this checkout, leaving it in place"
else
  rm -rf "$config/gapjumper"
fi
info "Removed from $config"

if [ -f "$config/gapjumper_config.lua" ]; then
  info "Kept your settings in $config/gapjumper_config.lua"
fi
if [ -e "$init.gapjumper-backup" ]; then
  info "Kept the backup of your original config in $init.gapjumper-backup"
fi

app=$(find_app)
if [ -n "$app" ] && app_running; then
  reload_app "$app"
fi
