---
type: runtime-component
title: Container entrypoint
description: What docker-entrypoint.sh does before the agent starts — choosing a writable HOME for a uid without a passwd entry, marking the mounted project as a safe git directory, printing the startup banner — and why it execs rather than supervising.
tags: [entrypoint, home, git, ownership, startup, container-runtime]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-8451388bda3e1da2037247f2
    resource: repo://docker-entrypoint.sh
  - id: openwiki-source-bb1ebe868e35e9e500714501
    resource: repo://Dockerfile
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

`docker-entrypoint.sh` is the whole of the container's startup behaviour: three
short steps and an `exec`. It is copied into the agent image as
`/usr/local/bin/pi-entrypoint` with mode 755 (`Dockerfile#L54`) and is the image's
`ENTRYPOINT`; the default `CMD` is `pi` itself (`Dockerfile#L63-L64`). Because it
is an entrypoint rather than a wrapper script, everything `bin/pi` passes after
the service name — the mode and the agent's own arguments — arrives as `"$@"`.

## A writable HOME

The first step exists because of a specific combination: on rootful Docker the
launcher runs the container as the host user's own uid, and that uid usually has
no `/etc/passwd` entry in the image and therefore inherits a `HOME` it cannot
write. The check is a probe rather than a guess — `mkdir -p` plus a `-w` test on
the current `HOME` (`docker-entrypoint.sh#L8`) — and when it fails the script
falls back to a scratch home at `/tmp/pi-home`, creating and exporting it
(`docker-entrypoint.sh#L9-L11`).

The fallback matters because git, npm and Pi all need somewhere to put state, and
a container that cannot write its own home fails in three separate places rather
than one. Only the probe is tolerant: it is inside an `if !` with stderr
discarded, so a failing `mkdir` is an answer rather than an error. The fallback
`mkdir -p` is not tolerant, and `set -eu` at the top of the script
(`docker-entrypoint.sh#L3`) means any remaining failure aborts the container
rather than starting an agent that will fail later and less legibly.

## A safe git directory

If the mounted project has a `.git`, the entrypoint adds it to git's global
`safe.directory` list (`docker-entrypoint.sh#L16-L18`). The mounted project is
usually owned by someone other than the process running in the container, and git
refuses to work with such a repository by default. This one is guarded twice: the
directory test skips projects that are not repositories at all, and the
`git config` call ends in `|| true`, so a missing or unusable git config cannot
stop a session. The tolerance is deliberate in the same direction as the home
probe: a session that can work should start.

## The banner

Before exec, the script prints four lines to stderr (`docker-entrypoint.sh#L20-L25`):
the workspace, the agent directory, the effective `HOME`, and a reminder that
`/login` authenticates a provider. Stderr rather than stdout because stdout is
the agent's own channel, and printed rather than silent because the three values
are the ones that vary per run and per host — in particular the `HOME`, which was
just chosen by the probe above. `PI_WORKSPACE` and `PI_CODING_AGENT_DIR` come from
the image's `ENV`, not from Compose (`Dockerfile#L59`), and they agree with the
two mount targets in the Compose file.

## Why it execs

The last line is `exec "$@"` (`docker-entrypoint.sh#L27`). The entrypoint becomes
the requested program instead of sitting in front of it, so no intermediate
process has to relay signals or hold stdio, and there is no extra shell whose
failure would be reported as the session's. Compose's own `init: true` supplies
the init process underneath, so reaping and signal handling are handled one level
lower than this script.

Under `--shell` the same entrypoint prepares the environment and then execs `sh`
instead, which is why both modes share the home fallback and the git fix.
