---
type: tooling
title: Make targets
description: The Makefile as developer tooling — the two-word grammar of targets and Compose service words, the overridable variables, help generated from inline comments, symlink-safe install and uninstall, and the pin versus update version workflow.
tags: [makefile, targets, variables, service-words, pin, uninstall]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

The Makefile wraps the tools the project already uses — Docker Compose, npm,
`ln` — and adds the conventions around them: one place to pin the agent version,
one safe way to install the launcher, and a test entry point. Every target is
phabetic: none writes a file worth declaring, so none can go stale, and the
`.PHONY` list is split across two declarations purely so one `sed` can read the
whole thing (`Makefile#L1-L4`, `Makefile#L57-L59`).

`SHELL` is bash with `-eu -o pipefail` for the recipes, while the launcher
itself stays POSIX sh — the strictness here is about recipes failing early, not
about the shipped script (`Makefile#L10-L13`).

## Two words, two meanings

`make <target> [service...] [var=value ...]` is the whole grammar, and it is
what lets `make build pi` read the way `make build` does
(`Makefile#L6-L8`).

`MAKECMDGOALS` holds every word after `make`. Make consumes the ones naming a
target; the rest are Compose service names. `TARGETS` and `SERVICES` are declared
once, each word of `SERVICES` gets a no-op rule so it can be named at all, and:

```make
SERVICE := $(or $(filter-out $(TARGETS),$(MAKECMDGOALS)),$(firstword $(SERVICES)))
```

(`Makefile#L36-L55`). Three subtleties are commented at the definition and are
each load-bearing:

- **`SERVICES` is deliberately absent from the filter list.** Filtering it out too
  would look harmless while `SERVICES` held only `pi`, because the default
  happens to be `pi` anyway — and would silently redirect `make build supermemory`
  to `pi` the moment a second service existed.
- **An empty result means the default service**, so `make build` and `make build
  pi` do the same thing.
- **A word that is neither fails on the no-op rule**, rather than reaching Compose
  as a service that does not exist.

## Variables

All overridable on the command line, each with an inline `##` comment that feeds
`help`: `image`, `install_dir`, `compose`, `pi_package`, `dockerfile`, `version`
and `filter` (`Makefile#L15-L25`). Make keeps the alignment padding in front of a
`##` comment as part of the value, which is why every recipe reads variables
through `$(strip)`.

`image` is also exported as `PI_IMAGE` once, because both `bin/pi` and Compose
read that name — exporting it in one place keeps every target consistent instead
of repeating it per command line (`Makefile#L27-L29`).

`help` is the default goal and is generated from the file itself with two `awk`
passes: one over `:.*?## ` for targets, one over `## ` for variables, printing
each variable's current value or `<empty>` (`Makefile#L61-L72`). Adding a target
with a `##` comment is therefore the whole documentation step.

## install and uninstall

`install` symlinks `$(CURDIR)/bin/pi` into `install_dir`, creating the directory
and reporting the path. It is idempotent: if the existing link already resolves
to the same file it says so instead of relinking (`Makefile#L80-L88`).

`uninstall` is the interesting half, because it deletes something outside the
repository. It refuses in three cases, each with its own message: nothing there
at all, a path that is not a symlink, and a symlink that points somewhere else.
Only a link pointing at this repository's `bin/pi` is removed
(`Makefile#L90-L100`).

## pin and update

`pin version=x.y.z` rewrites exactly one line: it requires a non-empty version
and a file containing an `ARG PI_VERSION=` line, then rewrites that line with
`sed` through a temporary file it moves into place (`Makefile#L110-L119`).

`update` is `pin` with the version discovered for you — `npm view` on
`pi_package`, with distinct errors for npm being unreachable and npm reporting
nothing, after which it re-enters `pin` and ends by telling you to rebuild
(`Makefile#L102-L108`). The version therefore lives in exactly one place, and
rebuilding stays reproducible.

## clean

`clean` runs `compose down --remove-orphans` and then `docker image rm`, with
the leading `-` on both so a missing image is tolerated and the target still
succeeds (`Makefile#L132-L134`). It removes the image and the project network but
keeps `agent/` and the memory volume, because that volume is a named volume
holding the only copy of the memory graph.

## Tests as targets

`test` and `test-memory` run the two suites with `filter=` passed through under
each suite's own environment variable (`Makefile#L126-L130`). Both can be asked
for in one command — `make test test-memory` — which works precisely because
`MAKECMDGOALS` holds both words and only `build` and `shell` need a service name.
