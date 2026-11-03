# Security policy

## Supported versions

Only the latest commit on `main` is supported. Please update before reporting.

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report them privately through
[GitHub Security Advisories](https://github.com/dlled/gapjumper/security/advisories/new),
or by email to dlled.dev@gmail.com. Include the steps to reproduce and the
impact you see.

You can expect an acknowledgement within a week. Once a fix is ready, it is
released on `main` and the advisory is published, crediting you unless you
prefer otherwise.

## Scope

gapjumper runs inside Hammerspoon with its permissions (Accessibility), and its
scripts edit your Hammerspoon config and may install Hammerspoon. Relevant
reports include, for example, the install scripts writing outside the
Hammerspoon config folder, downloading or running unverified code, or the
module doing anything beyond moving the cursor.
