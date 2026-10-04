---
type: system-architecture
title: Memory engine image
description: How the self-hosted Supermemory engine is built — a pinned non-open-source release fetched from its manifest and checksum-verified instead of piped into a shell, architecture mapping from dpkg, a pre-created data directory, and an image that publishes nothing.
tags: [dockerfile, supermemory, checksum, supply-chain, release-pin, image]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-446c852a4e7832726130c856
    resource: repo://Dockerfile.supermemory
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

The memory engine is a second image, `Dockerfile.supermemory`, built on
`debian:bookworm-slim`. It is separate from the agent image for two reasons: the
agent image spends a documented effort on size and the engine's own bulk — its
graph database and local embedding model — has no business inside the sandbox the
model runs in; and a Supermemory version bump then rebuilds one image and leaves
the other's layer cache alone (`Dockerfile.supermemory#L1-L8`).

It needs nothing from the repository, which is why the `.dockerignore` allowlist
stays closed for it: the Dockerfile itself is un-excluded and that is all
(`Dockerfile.supermemory#L10-L11`).

## The version, and what pinning buys

`ARG SUPERMEMORY_VERSION=0.0.8` is the only place the version lives
(`Dockerfile.supermemory#L22-L27`). 0.0.8 is specifically the release the
self-hosting documentation describes, including the two properties the Compose
file's isolation rests on: it binds every interface, and its implicit local
authentication is unsafe on an untrusted network.

The file is equally explicit about what verification does *not* buy. The binary
is not open source — the public repository holds the SDKs and components, while
the server artefact is built from a separate, non-public codebase
(`Dockerfile.supermemory#L13-L15`). Checking the checksum catches a truncated,
corrupted or CDN-swapped download; it does not make an unreviewable binary
reviewable. The instruction that follows is to read a release note before bumping.

## Fetching without piping into a shell

The upstream install path is `curl -fsSL https://supermemory.ai/install | bash`.
The build refuses that shape and performs the same two downloads explicitly
(`Dockerfile.supermemory#L34-L59`):

1. `dpkg --print-architecture` maps the build platform to a release asset name —
   `amd64` to `linux-x64`, `arm64` to `linux-arm64`, anything else fails the
   build (`Dockerfile.supermemory#L44-L50`). Architecture comes from dpkg rather
   than buildx's `TARGETARCH` so that a plain `docker build` without BuildKit
   resolves the platform the runtime will actually execute on
   (`Dockerfile.supermemory#L41-L43`).
2. `manifest.json` is fetched from the `server-v$VERSION` release and the
   sha256 for that platform is read out with `jq`
   (`Dockerfile.supermemory#L51-L53`).
3. The checksum is constrained to exactly 64 hex characters before it is trusted,
   and a missing or malformed value fails the build rather than producing an
   unchecked binary (`Dockerfile.supermemory#L54-L55`).
4. The asset is downloaded and verified with `sha256sum -c` *before* `chmod 0755`
   makes it executable (`Dockerfile.supermemory#L56-L59`), so the ordering is
   wrong in exactly the way that would matter.
5. A separate `RUN test -x /usr/local/bin/supermemory-server` repeats the agent
   image's own entry-point check, so a bad download fails the build rather than
   the first launch (`Dockerfile.supermemory#L61-L64`).

`curl` and `jq` stay in the runtime image on purpose: the Compose healthcheck uses
`curl`, and nothing else needs to reach the engine (`Dockerfile.supermemory#L66-L67`).

## State and environment

`SUPERMEMORY_DATA_DIR=/var/lib/supermemory`, `SUPERMEMORY_DISABLE_TELEMETRY=1`
and `PORT=6767` are set in the image (`Dockerfile.supermemory#L69-L71`), and the
data directory is created during the build so the named volume mounts onto a
directory that already exists instead of one Docker creates root-owned over
nothing (`Dockerfile.supermemory#L73-L77`).

There is deliberately **no `EXPOSE`**. It would bind nothing, but naming the port
in the image as well as in the healthcheck and the Compose service name would make
it easier to misread; keeping it in exactly two places is the point
(`Dockerfile.supermemory#L85-L87`).

## No USER

The image declares no `USER`, for a slightly different reason than the agent
image: this is a service the Compose network isolates rather than a sandbox whose
uid is negotiated per run, and its data directory is a root-owned named volume.
The comment adds the condition — if a port is ever published, fix this first
(`Dockerfile.supermemory#L79-L83`).

How the resulting container is configured, reached and kept out of version control
belongs to the long-term memory page and the Compose run definition.
