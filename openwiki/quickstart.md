---
type: overview
title: Quickstart
description: Task-routing map for the Pi agent container hub — install the launcher, start a session, configure a provider, reach long-term memory, run the tests, and jump to the page that owns each question.
tags: [quickstart, overview, orientation, launcher, testing, memory]
sources:
  - id: openwiki-source-5f5b95b3d6a215fa02ceb945
    resource: repo://.env.example
  - id: openwiki-source-4dd766881eeb1848d297e025
    resource: repo://agent/AGENTS.md
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "pi", at: "2026-10-05T20:23:24.626Z" }
verified:
  - by: openwiki/0.7.0
    at: 2026-10-05T20:23:24.626Z
---

This repository is a container image that runs the Pi coding agent with a small
set of everyday CLI tools, a launcher that mounts whichever project you point it
at, and a self-hosted memory server beside it. The `agent/` directory is the
point of the whole thing: it holds the agent's configuration and is mounted into
every launch, so the agent behaves the same way in every project and the setup
travels with the repository.

## Get a session

Requires Docker on Linux or macOS.

```bash
make install          # symlink bin/pi into ~/.local/bin
pi                   # mount the current directory and start the agent
pi ~/src/myproject   # work on another directory
pi --shell            # same mounts, but a shell instead of the agent
pi --build            # rebuild the image first
pi . -- -p "add tests"   # one-shot, non-interactive
```

The argument must be a directory; anything else exits `2` rather than being
silently ignored. Both mounts are read-write, so anything the agent writes under
`/workspace` goes straight to the host — commit before large edits.

## Authenticate

Two options, and they compose:

1. Export a provider key in your host shell (`export OPENROUTER_API_KEY=...`, or
   any other the Compose file forwards). The Compose `environment:` list forwards
   a variable only when it is actually set, so nothing is stored in the
   repository. `cp .env.example .env` is the file-based form.
2. Run `/login` inside the container. Pi writes the credential to the gitignored
   `agent/auth.json`, which persists between runs; `/logout` removes it.

Then pick a model with `/model`. For a provider Pi does not know about — a local
Ollama server, for example — add it to `agent/models.json`.

## Turn on memory

```bash
docker compose run --rm supermemory   # first boot prints the API key
```

Paste that key into `.env` as `SUPERMEMORY_API_KEY`. The engine's address is not
a variable: it is the Compose service name, `http://supermemory:6767`, reachable
only from inside the project network. Memory is then available to the agent
through plain HTTP — there is no MCP server for it.

## Run the tests

```bash
make test            # Makefile targets, in a throwaway repo copy, docker/npm stubbed
make test-memory     # memory wiring: reads files only, never reads .env
make test filter=pin # narrow either suite by substring
make test test-memory
```

Both are hermetic: no daemon, no network, no API key. Neither proves the memory
engine works — that needs a boot and a real round trip.

## Where things live

| Path | What it is |
|---|---|
| `bin/pi` | the only host-side code: the launcher |
| `docker-compose.yml` | the definition of a run: services, mounts, network, environment |
| `Dockerfile` | the agent image: pinned Pi version, tools, entrypoint |
| `Dockerfile.supermemory` | the memory engine image: pinned, checksummed binary |
| `docker-entrypoint.sh` | container startup: writable `HOME`, git safe.directory, banner |
| `Makefile` | developer tooling and the test entry points |
| `test/` | the two hermetic suites |
| `scripts/` | build-time helper, copied in for the build stage only |
| `agent/` | the agent's committed configuration, mounted on every launch |

## Pages

**Architecture**

- [Run lifecycle](architecture/run-lifecycle.md) — from a host `pi` invocation to
  a live session, and what the session inherits.
- [Host launcher](architecture/host-launcher.md) — `bin/pi`: argument grammar,
  the rootless-versus-rootful uid decision, terminal detection, the exec.
- [Compose run definition](architecture/compose-run-definition.md) — services,
  mounts, the shared network, conditionally forwarded credentials.
- [Container entrypoint](architecture/container-entrypoint.md) — the `HOME`
  fallback, `git safe.directory`, the banner, and why it execs.

**Images**

- [Agent image](images/agent-image.md) — two-stage build, the version pin, the
  tool set, the staged entry point, no `USER`.
- [Memory engine image](images/memory-engine-image.md) — the pinned release, the
  checksum verification, and what it deliberately does not publish.
- [Platform pruning](images/platform-pruning.md) — why a shrinkwrapped esbuild
  tree carries every platform, and the npm rule the build script reimplements.

**Configuration and memory**

- [Agent configuration](configuration/agent-configuration.md) — committed setup
  versus machine state, packages, providers.
- [Build context and secret hygiene](configuration/build-context-and-secrets.md) —
  the `.dockerignore` allowlist, the `.gitignore` groups, `.env` versus
  `.env.example`.
- [Long-term memory](memory/long-term-memory.md) — the contract in `AGENTS.md`,
  `containerTag` scoping, asynchronous ingestion, and the documented failure
  modes.

**Tooling and operations**

- [Make targets](tooling/make-targets.md) — target versus service word, generated
  help, symlink-safe install, `pin` and `update`.
- [Hermetic test suites](testing/hermetic-suites.md) — how each suite is fake, and
  what neither one proves.
- [OpenWiki Pages workflow](operations/openwiki-pages.md) — the static export and GitHub Pages deploy workflow (`openwiki visualize --export`) that runs on PR and push.
- CI uses `.github/workflows/ci.yml`; the previous `openwiki-update.yml` workflow has been removed.
