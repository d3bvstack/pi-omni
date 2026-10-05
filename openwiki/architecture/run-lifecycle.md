---
type: workflow
title: Run lifecycle
description: The end-to-end path from a host `pi` invocation to a live agent session — argument resolution, image gating, compose run, container startup — and the mounts and environment the session inherits.
tags: [workflow, run-lifecycle, launcher, compose, mounts, session]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-05T18:30:00.638Z
sources:
  - id: openwiki-source-715dace563ef484b6e8bd1e2
    resource: repo://.dockerignore
  - id: openwiki-source-afe52c853cc950b31949ac9d
    resource: repo://bin/pi
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-8451388bda3e1da2037247f2
    resource: repo://docker-entrypoint.sh
  - id: openwiki-source-bb1ebe868e35e9e500714501
    resource: repo://Dockerfile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

A run has four stages with a clear owner each: the host launcher decides, the
image supplies, Compose wires, and the entrypoint prepares. This page is the
handoff between them; the launcher, the Compose file, the entrypoint and the
image each have their own page.

```text
host:  pi [DIR] [--build] [--shell] [-- ARGS]
          │  resolve repository root, parse arguments, validate DIR
          │  decide uid from the daemon, detect a terminal
          │  build either image only when one is missing
          ▼
docker compose run --rm [-T] [--user uid:gid] pi {pi|bash} ARGS
          │  two bind mounts, conditionally forwarded provider keys
          ▼
container: /usr/local/bin/pi-entrypoint
          │  writable HOME, git safe.directory, stderr banner
          ▼
agent session on /workspace
```

## Stage 1: the launcher decides

`bin/pi` is the only thing that touches the host. It resolves the repository root
through the symlink `make install` created, parses the argument grammar, rejects
anything that is not a mountable directory, asks the daemon whether it is
rootless, and passes `-T` only when stdin or stdout is not a terminal. It also
gates the build: images are built when `--build` was given or when either image
is missing according to `docker image inspect`, and in the missing case both
services are built together so a fresh clone cannot fail on `depends_on` before
the agent gets a session. Two failures are distinguished by exit code — usage
errors exit 2, an unreachable daemon exits 1 — because they call for different
responses from the user.

## Stage 2: Compose wires

The launcher exports exactly four variables — `PROJECT_DIR`, `AGENT_DIR`,
`PI_IMAGE`, `SUPERMEMORY_IMAGE` — and hands off to
`docker compose run --rm`, passing the mode (`pi` or `bash`) and the agent's own
arguments after it. Everything else about the run's shape is declared in
`docker-compose.yml`, including the two read-write bind mounts, the list of
provider variables forwarded only when set, and the memory service the agent
depends on with `service_started` rather than a health gate.

## Stage 3: the image supplies

The agent image contributes the runtime, not the setup: the Pi package at a
pinned version, a small tool set, the entrypoint, and the two environment
variables `PI_CODING_AGENT_DIR=/pi/agent` and `PI_WORKSPACE=/workspace`. It
declares no `USER`, because the uid is negotiated per run by the launcher.

## Stage 4: the entrypoint prepares

`pi-entrypoint` probes for a writable `HOME` and falls back to `/tmp/pi-home`,
marks the mounted project as a git `safe.directory` when it is a repository,
prints four lines to stderr naming the workspace, agent dir and effective
`HOME`, and then `exec`s whatever it was given. Under `--shell` the same
preparation runs and `sh` is execed instead, which is why both modes share the
home fallback.

## What the session inherits

Everything a session knows about itself comes from mounts and environment, never
from the image:

- the project at `/workspace`, read-write, so writes land on the host with no
  undo boundary;
- the repository's `agent/` directory at `/pi/agent`, the agent's committed
  configuration, which is why the setup travels with the repository;
- provider credentials, forwarded one at a time and only when set in the
  launching shell, or written by `/login` into the gitignored `agent/auth.json`;
- `SUPERMEMORY_API_KEY` for the memory engine, whose address is not a variable
  but the compose service name;
- `PI_OFFLINE` and `PI_TELEMETRY` as pass-through toggles;
- a `HOME` chosen at startup, which is the one piece of state that exists only
  because of how the container is run.

The separation is the point: `agent/` is excluded from the Docker build context,
so no credential and no session state can reach an image layer, and a rebuilt
image cannot quietly change how the agent behaves.
