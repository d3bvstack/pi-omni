---
type: system-architecture
title: Agent image
description: What the Pi agent image contains and why — the two-stage build, the pinned Pi version, the runtime tool set and fd symlink, the separately staged pi entry point, the deliberate absence of a USER directive, and the agent-directory environment.
tags: [dockerfile, image, two-stage-build, toolchain, pin, runtime]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-715dace563ef484b6e8bd1e2
    resource: repo://.dockerignore
  - id: openwiki-source-4dd766881eeb1848d297e025
    resource: repo://agent/AGENTS.md
  - id: openwiki-source-afe52c853cc950b31949ac9d
    resource: repo://bin/pi
  - id: openwiki-source-bb1ebe868e35e9e500714501
    resource: repo://Dockerfile
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

The agent image is the sandbox the model runs in. It carries the agent and a
small set of everyday CLI tools and nothing else — in particular not the agent's
configuration, which is bind-mounted from the repository on every launch
(`Dockerfile#L1-L9`). That separation is why a rebuilt image cannot quietly change
how the agent behaves, and why `agent/` is excluded from the build context.

## Two stages, so build-only work does not ship

The build stage installs the Pi package globally with
`--ignore-scripts`, prunes the package tree, stages npm's `pi` link, and deletes
the npm cache and the prune script itself (`Dockerfile#L14-L29`). The runtime
stage then copies only `/usr/local/lib/node_modules` and the staged `bin`
directory across (`Dockerfile#L33-L52`). Nothing the build stage needed
exclusively — the cache, the prune helper, the shrinkwrapped binaries for other
platforms — survives into the image.

Both stages are `node:24-bookworm-slim`.

## The version pin

`ARG PI_VERSION=1.0.2` sits in the build stage and is used as
`npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}"`
(`Dockerfile#L16-L18`). It is pinned deliberately so that rebuilding is
reproducible, and it is the single place the version lives: `make update` rewrites
that one line, and neither the Compose file nor the launcher carries a version.
The build never installs a `latest` tag.

## The runtime tool set

The runtime stage installs `bash ca-certificates curl fd-find file git jq less
make openssh-client procps python3 ripgrep` in one `apt-get` layer
(`Dockerfile#L37-L43`). Two details in that line matter beyond the list itself:

- **`fd` is a symlink.** Debian ships the finder as `fd-find` but installs the
  binary as `fdfind`, so the image adds `ln -sf /usr/bin/fdfind
  /usr/local/bin/fd` to give the agent the name it expects
  (`Dockerfile#L35-L43`). Without it, `fd` simply does not exist.
- **There is no compiler toolchain.** No `gcc`, no `build-essential`. `make` is
  present so the agent can drive build recipes, but there is nothing in the image
  for it to compile, and `agent/AGENTS.md#L14` says so explicitly so the agent does
  not assume otherwise.

## The entry point is staged, not copied directly

npm installs `pi` as a symlink into `/usr/local/bin`, which it shares with node,
npx and corepack — paths the base image already occupies. `COPY` resolves a
symlink given as its own source, so the build stage copies the link out to
`/out/bin` and the runtime stage copies that directory instead
(`Dockerfile#L22-L29`, `Dockerfile#L51`). `cli.js` locates the rest of the
installation relative to its own path, so the link has to arrive as a link.

The copy is then checked with `RUN test -x /usr/local/bin/pi`
(`Dockerfile#L52`): a package that moved its entry point fails the build here
instead of at the first `pi`.

The entrypoint script itself is copied in with `--chmod=755` as
`/usr/local/bin/pi-entrypoint` (`Dockerfile#L54`) and declared as `ENTRYPOINT`,
with `CMD ["pi"]` (`Dockerfile#L63-L64`).

## No USER, on purpose

The image declares no `USER` directive, and the comment gives the reason: whether
the agent runs as root or as the host user's uid depends on whether the Docker
daemon is rootless, and `bin/pi` decides that per run (`Dockerfile#L56-L58`). A
`USER` baked into the image would make that decision for every run and would be
wrong for one of the two cases.

## Environment and workdir

`ENV PI_CODING_AGENT_DIR=/pi/agent PI_WORKSPACE=/workspace` names the agent's own
directory and the workspace, and `WORKDIR /workspace` matches the mount target
(`Dockerfile#L59-L61`). Compose does not set either: it only bind-mounts
`agent/` at `/pi/agent` and the project at `/workspace`, so image and Compose have
to agree, and they do by construction.
