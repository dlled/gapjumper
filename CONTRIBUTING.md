# Contributing to gapjumper

Thanks for your interest in improving gapjumper. Bug reports, layout reports and
pull requests are all welcome.

## Reporting a bug

Please open an issue using the bug report template and include:

- Your macOS version and Mac model.
- The full output of `./doctor.sh`, which lists your display layout and what
  each edge does.
- What you expected the cursor to do, and what it did instead.
- Any `gapjumper:` lines or errors from the Hammerspoon console.

## Development setup

You need Lua 5.3 or later and, optionally, ShellCheck:

```bash
brew install lua shellcheck
./test.sh
```

On Linux, `sudo apt-get install lua5.4 shellcheck` works too. CI runs the tests
on a macOS runner, since the scripts target the Bash 3.2 that ships with macOS.
`./test.sh` runs every suite and lists the ones that failed at the end.

`./test.sh` runs:

- `tests/run.lua`: the Lua tests for the geometry and for the event handling
  against a fake Hammerspoon. No displays or Hammerspoon install are needed.
- `tests/install_test.sh`: the installer and uninstaller against temporary
  folders. It never touches your real Hammerspoon config.
- ShellCheck on every shell script, when it is installed.

The property tests use a fixed seed. To reproduce or explore a failure, set
`GAPJUMPER_SEED`:

```bash
GAPJUMPER_SEED=1234 ./test.sh
```

To try a change on your own Mac, run `./install.sh` (or `./install.sh --skip-app`
to only copy the files) and then `./doctor.sh`.

## Code layout

- `gapjumper/geometry.lua`: pure Lua, no Hammerspoon dependency. All layout
  decisions belong here so they can be tested without hardware.
- `gapjumper/init.lua`: the Hammerspoon glue (event tap, watchers, settings).
- `install.sh`, `uninstall.sh`, `doctor.sh` and `scripts/common.sh`: Bash that
  must stay compatible with the Bash 3.2 shipped with macOS.

## Pull requests

- Keep changes focused, and add or update tests for any behavior change. A new
  display layout that misbehaves makes a great test case in
  `tests/layouts_test.lua`.
- Make sure `./test.sh` passes and ShellCheck reports nothing.
- Update `README.md` when you change user-facing behavior or settings, and add
  an entry under `Unreleased` in `CHANGELOG.md`.
- Write everything (code, comments, docs, commit messages) in English.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>: <short summary in the imperative>

<optional body explaining why>
```

Common types are `feat`, `fix`, `refactor`, `test`, `docs`, `ci` and `chore`.
Mark breaking changes with `!` (for example `refactor!:`) and explain them in
the body.

## Security

Please report vulnerabilities privately, as described in
[SECURITY.md](SECURITY.md), not in a public issue.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
