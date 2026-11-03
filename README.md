# gapjumper

[![CI](https://github.com/dlled/gapjumper/actions/workflows/ci.yml/badge.svg)](https://github.com/dlled/gapjumper/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Stop the mouse getting stuck between displays of different sizes on macOS.**

macOS only lets the cursor move from one display to another along edges that touch. When your displays have different sizes or resolutions, parts of some edges have no display next to them, and the cursor stops there. gapjumper is a small, free, open-source [Hammerspoon](https://www.hammerspoon.org/) module: when you push against one of those dead edges, the cursor jumps to the nearest display in that direction.

- Works with any number of displays in any arrangement.
- Re-reads the layout when you plug in, unplug or rearrange displays. With a single display it does nothing.
- Leaves edges that macOS already crosses alone.
- Comes with a `doctor.sh` that checks your setup and prints what every display edge does.

## Requirements

- macOS 13 (Ventura) or later.
- [Hammerspoon](https://www.hammerspoon.org/). The installer installs it for you if it is missing.
- The Accessibility permission for Hammerspoon, so it can read and move the cursor. The installer opens the right settings page.

## Install

```bash
git clone https://github.com/dlled/gapjumper.git
cd gapjumper
./install.sh
```

The installer:

1. Installs Hammerspoon if it is missing, with Homebrew (`brew install --cask hammerspoon`) when available, or otherwise by downloading the latest official release from GitHub and verifying that it is signed by the Hammerspoon developers.
2. Copies the `gapjumper` module into your Hammerspoon config folder (`~/.hammerspoon`, or the folder of a custom `MJConfigFile` if you set one with `defaults write org.hammerspoon.Hammerspoon MJConfigFile ...`). An existing `init.lua` is kept: gapjumper backs it up once to `init.lua.gapjumper-backup` and appends a marked block that loads `hs.ipc` and the module.
3. Reloads Hammerspoon.
4. Opens System Settings > Privacy & Security > Accessibility and waits until you enable Hammerspoon. This is the one step you do yourself, because macOS requires it.
5. Sets Hammerspoon to start at login.
6. Runs `./doctor.sh` to check the result.

Options:

| Option | Effect |
| --- | --- |
| `--no-autostart` | Do not set Hammerspoon to start at login. |
| `--skip-app` | Only copy the files. Does not install, reload or check Hammerspoon. |
| `-h`, `--help` | Show the help, including the environment variables below. |

Environment variables, mainly for testing or unusual setups:

| Variable | Effect |
| --- | --- |
| `GAPJUMPER_CONFIG_DIR` | Use this folder instead of Hammerspoon's config folder. Also honored by `uninstall.sh` and `doctor.sh`. |
| `GAPJUMPER_APP` | Path to an existing `Hammerspoon.app`. |
| `GAPJUMPER_APP_DIR` | Where to put Hammerspoon when downloading it without Homebrew (default `/Applications`, or `~/Applications` if that is not writable). |

Running `./install.sh` again is safe: it replaces the module and the marked block, and leaves the rest of your `init.lua` untouched. Do not edit the installed copy of the module, since it is overwritten on every run; put your settings in `gapjumper_config.lua` instead.

The scripts need Bash. Run them as `./install.sh` or `bash install.sh`, not `zsh install.sh`.

### Update

```bash
cd gapjumper
git pull
./install.sh
```

### Uninstall

```bash
./uninstall.sh
```

This removes the module and the marked block from `init.lua`, then reloads Hammerspoon if it is running. If the installed module is a symlink, only the symlink is removed. Hammerspoon itself, your `gapjumper_config.lua` and the `init.lua.gapjumper-backup` file are kept; delete them by hand if you no longer want them.

To turn gapjumper off only until the next Hammerspoon reload, run `gapJumper.stop()` in the Hammerspoon console. `gapJumper.start()` turns it back on.

## Check your setup

```bash
./doctor.sh
```

It confirms that Hammerspoon is installed and running, that the installed files match your checkout, that the Accessibility permission is granted, that the mouse is being listened to, and that every jump on your current layout lands on its target display. It exits with a non-zero status if anything needs attention, and then prints what each display edge does:

```text
Laptop  x=0..1512  y=0..982
  up    x=0..1512  native
  down  x=0..1512  no exit
  left  y=0..982  JUMPS to Portrait (x=-1262)
```

`native` means macOS crosses that edge on its own, `JUMPS to` names the display gapjumper sends the cursor to, and `no exit` means there is no display in that direction.

## How it works

gapjumper listens to mouse-move and drag events. When the cursor is on a display edge that has no display right past it and you keep pushing in that direction, it adds up the push. Once the push reaches `MIN_PUSH`, it moves the cursor to the best display in that direction:

- Only displays whose center lies past the edge are candidates. Pushing down on a laptop does not jump to a tall monitor beside it, so the Dock stays reachable.
- Among candidates, the shortest distance wins, with `SIDE_PENALTY` added when the target is not straight ahead.
- The cursor keeps its position along the edge, clamped to the target display, and lands `ENTRY_MARGIN` points inside it.
- The jump is done by posting a mouse event rather than calling `hs.mouse.absolutePosition`. The latter uses `CGWarpMouseCursorPosition`, which ignores the physical mouse for about 0.25 seconds after each jump.
- A watchdog checks every 5 seconds that the event tap is still enabled, and the tap is restarted after the Mac, the screens or the user session wake up, because macOS can disable it.

### Choosing where an edge leads

The arrangement in System Settings > Displays > Arrange decides what each edge does. For example, a tall monitor placed beside a wider top monitor, overlapping it vertically, crosses natively to that monitor along its upper part and jumps to the laptop below along its lower part. Dragging the tall monitor up or down moves that split point. Run `./doctor.sh` after rearranging to see the result.

## Configuration

Create `gapjumper_config.lua` in your Hammerspoon config folder (usually `~/.hammerspoon`) and return a table with the settings you want to change. Reinstalling does not touch this file.

```lua
return {
  MIN_PUSH = 20,
}
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `MIN_PUSH` | `12` | Points of push against the edge needed to jump. Raise it if you jump by accident. Must be greater than 0. |
| `PUSH_TIMEOUT` | `0.35` | Seconds without pushing after which the accumulated push resets. |
| `COOLDOWN` | `0.15` | Seconds after a jump during which no new jump happens, to prevent bouncing. |
| `ENTRY_MARGIN` | `2` | Points inside the target display where the cursor lands. |
| `EDGE_TOLERANCE` | `1.5` | Points from the edge within which the cursor counts as being on it. |
| `SIDE_PENALTY` | `300` | Extra cost, in points, for a target display that is not straight ahead. |

Distances are in points (macOS screen coordinates), not physical pixels, so they behave the same on Retina and non-Retina displays. Every value must be a non-negative number. Unknown settings and invalid values are ignored (the default is kept) and reported in the Hammerspoon console and by `./doctor.sh`. Reload Hammerspoon from its menu bar icon to apply changes.

## Troubleshooting

**The cursor still gets stuck.** Run `./doctor.sh` and fix any `FAIL` line it prints. Check the edge map: if the edge says `no exit`, there is no display whose center lies in that direction, so gapjumper deliberately does nothing.

**"Accessibility permission missing".** Open System Settings > Privacy & Security > Accessibility and enable Hammerspoon. If it is already enabled but still not working, turn it off and on again, then quit and reopen Hammerspoon: it only notices the permission after a restart. After updating Hammerspoon, macOS sometimes needs the permission granted again.

**"Gap Jumper is not responding".** Open the Hammerspoon console (menu bar icon > Console) and look for errors, for example from your own `init.lua` or from `gapjumper_config.lua`. Fix them, then run `./install.sh` again.

**"start marker without an end marker".** The installer and uninstaller found a `-- >>> gapjumper >>>` line in `init.lua` without its closing `-- <<< gapjumper <<<` line, usually after a hand edit. They leave the file untouched so nothing is lost. Delete the leftover block by hand and run the script again.

**Jumps happen by accident.** Increase `MIN_PUSH` in `gapjumper_config.lua`.

**I see a "Gap Jumper active" alert.** It is shown each time Hammerspoon loads the module, to confirm it is running.

**Does it work with my own Hammerspoon config?** Yes. gapjumper only appends a marked block to `init.lua` and exposes a single global, `gapJumper`. If your `init.lua` is a symlink, for example managed by a dotfiles repo, it stays a symlink.

**Does it collect any data?** No. It runs locally and makes no network requests. Only the installer contacts the network, to install Hammerspoon when it is missing.

## Development

```bash
brew install lua shellcheck
./test.sh
```

`gapjumper/geometry.lua` is pure Lua with no Hammerspoon dependency, so all the layout logic is tested without real displays. The tests cover:

- Exact landing points on known layouts.
- Common Mac and monitor combinations, including fractional scaling, mirroring and displays that only touch at a corner.
- 400 random layouts checked for invariants. Set `GAPJUMPER_SEED` to reproduce a failure.
- The event handling, against a fake Hammerspoon.
- The installer and uninstaller, against temporary folders.

Lua 5.3 or later works. CI runs the same `./test.sh` on a macOS runner on every push and pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute, [CHANGELOG.md](CHANGELOG.md) for the release history and [SECURITY.md](SECURITY.md) for reporting vulnerabilities privately.

## Acknowledgements

gapjumper is an independent project. It is not affiliated with, endorsed by or derived from GapSucker or its developer. GapSucker is a separate product that addresses the same problem, and its name is mentioned only to describe what gapjumper does. GapSucker is a trademark of its respective owner. gapjumper is built on top of [Hammerspoon](https://www.hammerspoon.org/).

## License

[MIT](LICENSE) © dlled
