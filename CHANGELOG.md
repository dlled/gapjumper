# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-03

First public release.

### Added

- Hammerspoon module that jumps the cursor across the gaps between displays of
  different sizes when you push against an edge with no adjacent display.
- Support for any number of displays in any arrangement, re-read whenever the
  display configuration changes or the Mac, its screens or the user session
  wake up.
- Target selection that only considers displays whose center lies past the
  edge, so pushing towards the Dock does not jump to a monitor beside it.
- Optional `gapjumper_config.lua` settings file (`MIN_PUSH`, `PUSH_TIMEOUT`,
  `COOLDOWN`, `ENTRY_MARGIN`, `EDGE_TOLERANCE`, `SIDE_PENALTY`) that survives
  reinstalls, with validation of unknown or invalid values.
- `install.sh`: installs Hammerspoon if missing (Homebrew, or the official
  release, verified to be signed by the Hammerspoon developers), keeps an
  existing `init.lua` with a backup, guides through the Accessibility permission and enables start at login (`--no-autostart`,
  `--skip-app`, `--help`). Running it again updates in place.
- `uninstall.sh`: removes the module while keeping Hammerspoon and your settings.
- `doctor.sh`: checks the installation and permissions, validates the live
  display layout and prints what every display edge does.
- Watchdog that restarts the event tap when macOS disables it.
- Protection against loading the module twice, a wall clock that jumps
  backwards, and invalid settings such as `NaN`.
- Test suite for the geometry (known layouts, common Mac and monitor
  combinations, randomized property tests), the event handling against a fake
  Hammerspoon, and the install scripts, run in CI on every push.

### Fixed

- The physical mouse no longer freezes for about 0.25 seconds after a jump: the
  cursor is moved by posting a mouse event instead of warping it.

[Unreleased]: https://github.com/dlled/gapjumper/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/dlled/gapjumper/releases/tag/v1.0.0
