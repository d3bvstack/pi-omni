---
type: operations
title: CI and troubleshooting
description: The operational surface outside a run — the path-filtered Makefile CI job, the scheduled OpenWiki update workflow, how file ownership differs between rootless and rootful Docker, and the failure modes the README maps to causes.
tags: [ci, github-actions, troubleshooting, file-ownership, operations, failure-modes]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-164e2da859b5277df81c7d94
    resource: repo://.github/workflows/ci.yml
  - id: openwiki-source-6d4b4e707b8d60b6ccfa3425
    resource: repo://.github/workflows/openwiki-update.yml
  - id: openwiki-source-afe52c853cc950b31949ac9d
    resource: repo://bin/pi
  - id: openwiki-source-446c852a4e7832726130c856
    resource: repo://Dockerfile.supermemory
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

This page covers what happens around a run rather than inside one: what CI
executes, what a scheduled workflow maintains, how the agent's file ownership
behaves on different Docker daemons, and how to read the common failures.

## Continuous integration

`ci.yml` runs exactly one thing: `make test` on `ubuntu-latest`
(`.github/workflows/ci.yml#L18-L25`). The reasoning is in the file's header — the
Makefile suite stubs `docker` and `npm`, needs no daemon and no network, and
never writes to the checkout, so there is one job, no services and no caching,
and "if it passes here it passes anywhere" (`.github/workflows/ci.yml#L3-L5`).

Both triggers are filtered to `paths: [Makefile]` on `main` and `master`
(`.github/workflows/ci.yml#L6-L12`), so the job runs when the Makefile changes
and not for an ordinary source change. Concurrency is grouped by workflow and
ref with `cancel-in-progress: true`, so a newer push supersedes an in-flight run
(`.github/workflows/ci.yml#L14-L16`).

The memory suite is deliberately not in CI on that path — it reads repository
files, and running it is a local `make test-memory`.

## The scheduled wiki update

`openwiki-update.yml` runs on `workflow_dispatch` and on a daily cron at 08:00
UTC (`.github/workflows/openwiki-update.yml#L1-L6`). Two details are load-bearing:

- **`fetch-depth: 0`.** The update diffs `HEAD` against the commit the wiki last
  documented; a shallow clone hides that commit and the update runs against an
  empty change summary (`.github/workflows/openwiki-update.yml#L17-L22`).
- **A pinned toolchain.** `openwiki@0.7.0` plus `mermaid` and `jsdom`, installed
  globally, with Node 22 (`.github/workflows/openwiki-update.yml#L24-L31`). The
  pin keeps a scheduled run reproducible, matching the repository's habit of
  pinning versions rather than tracking latest.

The job runs `openwiki code --update --print` with `continue-on-error: true`
(`.github/workflows/openwiki-update.yml#L33-L36`), so a failed regeneration
does not fail the workflow; the step's own outcome and the printed report are
what a maintainer reads. Provider and tracing keys come from repository secrets.

## File ownership

`bin/pi` asks the daemon whether it is rootless and adapts
(`README.md#L269-L272`):

- **Rootless Docker** maps container root onto the host user, so the container
  runs as root and no `--user` is passed. Passing a uid would make files appear
  on the host owned by a subordinate uid instead.
- **Rootful Docker** would leave files owned by real root, so the container runs
  as your own `uid:gid`. Because that uid usually has no passwd entry, the
  entrypoint then falls back to a writable scratch `HOME` at `/tmp/pi-home` for
  git, npm and Pi state — the mechanism itself is on the container entrypoint
  page.

Either way, files the agent writes into `/workspace` belong to you
(`README.md#L281`).

## Troubleshooting

The README's list is written as symptom-to-cause pairs, which is the useful way
to read it.

**`pi` behaves like a native install.** A global `pi` from
`npm install -g @earendil-works/pi-coding-agent` answers `--version` with a bare
number, while this launcher names itself and the image it will use. A native
install lands in `~/.nvm/versions/node/*/bin`, normally earlier on `PATH` than
`~/.local/bin`, so it wins in scripts, ssh sessions and `make` recipes — remove
it, or put this repository's `bin` first (`README.md#L326-L331`).

**`pi: cannot reach the Docker daemon`.** Docker is not running, or the user is
not in the `docker` group. This is exit 1, distinct from the usage errors.

**The image rebuilds on every launch.** It should build only when the image is
absent; check that `PI_IMAGE` is not set to something else.

**A change to `agent/` is ignored.** Pi re-reads committed files on every start,
so a live session needs `/reload`.

**`permission denied` on a mounted path.** The host directory is not readable by
the uid the container runs as, which on rootful Docker is your own uid.

**Changing the Pi version.** `make update` rewrites `ARG PI_VERSION` in the
`Dockerfile`, or edit that line by hand, then `make build`. The pin is deliberate,
so rebuilds stay reproducible.

**Memory-specific failures.** Each has its own signature: the engine unreachable
from the agent means checking `docker compose ps` first, and a `curl` from the
host failing is expected because the endpoint is network-only; a boot that never
becomes ready is the first-boot embedding download visible in
`docker compose logs -f supermemory`; and the two `401` shapes are distinct —
`{"error":"Unauthorized"}` means the key is missing or wrong and the current key
comes from `docker compose run --rm supermemory`, while `Either userId or orgId
not found` means the engine is still loading.

**Changing the Supermemory version.** Edit `ARG SUPERMEMORY_VERSION` in
`Dockerfile.supermemory`, then `make build supermemory`, and read the release
notes first: the self-hosting docs warn that 0.0.8 binds every interface and that
a later release changes both the bind address and whether the generated key is
required — which is what the no-`ports:` decision rests on.
