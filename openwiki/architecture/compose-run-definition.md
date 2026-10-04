---
type: system-architecture
title: Compose run definition
description: How docker-compose.yml defines every agent run — the pi and supermemory services, the shared project network, the two bind mounts, conditionally forwarded provider keys, the memory volume, and the healthcheck and restart policy.
tags: [docker-compose, run-definition, network, mounts, environment, services]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-afe52c853cc950b31949ac9d
    resource: repo://bin/pi
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

`docker-compose.yml` is the only definition of a run. `bin/pi` supplies what
Compose cannot know — which directory to mount, which image names to use, which
uid to run as, whether to allocate a terminal — by exporting variables and by
passing flags on the `compose run` command line. Everything else about the shape
of a session lives in this file.

The project is named `pi-agent`, so the network Compose creates for it is stable
and named after the project rather than after the working directory
(`docker-compose.yml#L26`).

## Services

Two services, and the second one is the pattern the rest follow.

`pi` names the agent image and builds it from `Dockerfile`
(`docker-compose.yml#L29-L33`). `supermemory` names the memory engine image and
builds it from `Dockerfile.supermemory` (`docker-compose.yml#L82-L90`). In both
cases the `image:` key names the built result — `${PI_IMAGE:-pi-agent:latest}`
and `${SUPERMEMORY_IMAGE:-supermemory-server:local}` — and neither carries a
version. Versions live only in the respective `ARG` line, so an image name never
becomes a second place that has to be bumped.

## The pi service

Three things are deliberately absent from it, and each absence moves a decision
somewhere it can actually be made.

- **No `tty` or `stdin_open`.** `compose run` allocates a terminal by itself
  unless it is told not to. The launcher knows whether stdin and stdout are
  terminals — it runs on the host and can see — so `bin/pi` passes `-T` only when
  one of them is not (`docker-compose.yml#L34-L35`).
- **No `USER`.** Whether the container runs as root or as the host user's own
  uid depends on whether the Docker daemon is rootless, and that is a per-run
  property of the host. `bin/pi` decides it and passes `--user`
  (`docker-compose.yml#L35`).
- **No health gate on `depends_on`.** The agent depends on the memory service
  with `condition: service_started`, not `service_healthy`
  (`docker-compose.yml#L42-L44`). A fresh volume downloads a local embedding
  model on first boot, and gating on health would make every launch wait for
  that. The engine is something the agent reaches only when it chooses to, so a
  slow warm-up must not cost a session. `agent/AGENTS.md` is what tells the
  agent to treat a call during warm-up as "memory unavailable, carry on".

`init: true` is the one thing added for the agent's benefit: it gives the
session a real init process, so signals and zombie reaping behave
(`docker-compose.yml#L36`).

## Mounts

Exactly two, both bind mounts, both read-write (`docker-compose.yml#L46-L53`):

| Source | Target | What it is |
|---|---|---|
| `${PROJECT_DIR:-.}` | `/workspace` | the project the agent works on |
| `${AGENT_DIR:-./agent}` | `/pi/agent` | the agent's configuration directory |

The defaults are what make `docker compose config`, `build` and `up` work from
this directory alone, while `bin/pi` overrides both on every real launch. The
project mount is read-write with no undo boundary, which is why the README tells
you to commit before large edits. The agent directory is the mechanism behind
the repository's central claim: the agent's setup is committed here and mounted
into every container, so it travels with the repository and is never baked into
an image.

`/pi/agent` is the path the agent image sets as `PI_CODING_AGENT_DIR`; Compose
does not configure it, it just agrees with the image about where it is.

## Environment

The `pi` service forwards provider credentials as a list of bare variable names
rather than assignments (`docker-compose.yml#L59-L79`). In that form Compose
forwards a variable only when it is set in the launching shell, so the list can
be long and complete without a single credential ever being stored in this
repository. The list covers Pi's own `PI_OFFLINE` and `PI_TELEMETRY` toggles,
every provider key `pi --help` documents, and `SUPERMEMORY_API_KEY`, the bearer
token the memory engine prints on its first boot. The memory endpoint is
deliberately *not* a variable: it is the service name on this network, fixed at
`http://supermemory:6767` and written down in `agent/AGENTS.md`, so there is
nothing to keep in sync.

Four variables Pi documents are intentionally left out of the list, as the
README records: `PI_CODING_AGENT_DIR`, which the image sets itself, and
`PI_CODING_AGENT_SESSION_DIR`, `PI_PACKAGE_DIR` and `PI_SHARE_VIEWER_URL`, which
have no use here.

## The supermemory service

Its configuration is mostly a set of refusals, and the reasons are in the file.

It has no `profiles:` entry. A profiled service is left out of `compose run pi`,
and then the agent's lookup of `supermemory` fails outright rather than
degrading — which is why the file's header documents the profile pattern for
tools the agent *may* reach instead (an Ollama server, for example) and why that
pattern is not used here (`docker-compose.yml#L91-L94`).

It publishes no `ports:`, and the file calls that load-bearing rather than
incidental: the pinned release binds every interface and its implicit local
authentication is unsafe on an untrusted network. The project network is the
isolation, and reachability by service name is the only exposure the agent gets
(`docker-compose.yml#L95-L101`).

It keeps state in a named volume mounted at `/var/lib/supermemory`, matching the
engine's own data directory, so the graph, the auth secret and the embedding
model cache outlive `docker compose down` and `make clean`
(`docker-compose.yml#L117`, `docker-compose.yml#L133-L136`). The volume is
named rather than bound into the repository precisely so that nothing under the
checkout is machine state.

Its LLM provider arrives through the `OPENAI_*` pair, because the engine has no
wizard without a TTY and OpenRouter — not a provider the server knows — is
OpenAI-compatible.

The healthcheck curls the server's browser welcome page, since no health endpoint
is published, with a 180-second `start_period` to cover the embedding download on
a fresh volume (`docker-compose.yml#L118-L127`). `restart: unless-stopped` keeps
the engine up because it holds the only copy of the memory graph
(`docker-compose.yml#L128-L131`).

## Adding a service

Compose creates the project network on the first run, so a new service is
reachable from the agent by name with nothing extra to configure, and `pi`
launches are unaffected because `compose run` starts only the service it is
asked for. Whether a new service needs a `profiles:` entry comes down to one
question: does the agent depend on it? If it does, no profile. If it may reach
it but does not need it, put it behind a profile and document it in the header of
this file, where the pattern is already written down.
