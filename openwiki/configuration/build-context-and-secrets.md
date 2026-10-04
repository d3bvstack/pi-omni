---
type: security-configuration
title: Build context and secret hygiene
description: How credentials and machine state are kept out of both images and commits — the .dockerignore allowlist and its parent-un-exclusion rule, the grouped .gitignore, and the .env versus .env.example split that mirrors Compose's conditional forwarding.
tags: [security, secrets, dockerignore, gitignore, environment, hygiene]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-715dace563ef484b6e8bd1e2
    resource: repo://.dockerignore
  - id: openwiki-source-5f5b95b3d6a215fa02ceb945
    resource: repo://.env.example
  - id: openwiki-source-ea70eb6c045047448e446296
    resource: repo://.gitignore
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-9f48987939f2914d8aa0dbf5
    resource: repo://test/supermemory.sh
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

This repository holds two kinds of secret-adjacent material: live credentials
that must never be committed, and machine state that must never be baked into an
image. Both are handled by rules that are structural rather than conventional —
an allowlist and a forwarding convention — so a file added later is excluded by
default instead of by remembering to exclude it.

## The build context is an allowlist

`.dockerignore` starts by excluding everything (`*`) and then un-excludes the
three files the images actually need (`.dockerignore#L1-L15`):

| Entry | Why |
|---|---|
| `!docker-entrypoint.sh` | copied into the agent image as `pi-entrypoint` |
| `!Dockerfile.supermemory` | named by `build.dockerfile` for the memory service |
| `!scripts/`, `!scripts/prune-platform-packages.js` | copied into the build stage to prune the package tree |

The stated reason is size and safety together: an allowlist keeps the context
tiny and makes it "structurally impossible for a credential, a session transcript
or any other future file to reach an image layer" (`.dockerignore#L2-L4`).

Two rules in that file are easy to get wrong and are therefore spelled out.
First, a file below a directory that `*` matched stays out of the context, so the
parent has to be un-excluded too — that is why `!scripts/` precedes the file
inside it (`.dockerignore#L12-L15`). Second, a Dockerfile named by
`build.dockerfile` has to be in the context like any other build input, which is
what `!Dockerfile.supermemory` is for; without it the memory build fails on a
missing file and reads as a broken build rather than a broken ignore rule
(`.dockerignore#L7-L11`). The agent `Dockerfile` needs no such line because
Docker reads it outside the context.

Note what is *not* un-excluded: `agent/` is excluded along with everything else,
so the agent's configuration and its credentials cannot reach a layer.

## Version control groups by origin

`.gitignore` groups the agent directory's ignored entries by what Pi derives from
`PI_CODING_AGENT_DIR` rather than by an alphabetical list (`.gitignore#L1-L24`):
credentials, history, binaries, caches, the package install tree, logs. Grouping
by origin means a new piece of generated state has an obvious place to go, and
the comment doubles as documentation of what Pi writes where.

## `.env` versus `.env.example`

`.env` is gitignored; `.env.example` is committed by an explicit negation, so
the split between them is visible in the file itself (`.gitignore#L26-L29`).
`.env.example` holds no secrets — the OpenRouter key and `SUPERMEMORY_API_KEY`
are empty placeholders, and the embedding variables are commented out because
they are optional (`test/supermemory.sh#L320-L330`).

The empty lines are not placeholders to fill in blindly. Compose forwards a
variable into the agent container only when it is actually set, so an empty line
in `.env.example` means "this capability is off", not "this is broken" — and the
documented flow is to copy the file and fill in only what you have.

## The two mechanisms are the same mechanism

The Compose file forwards provider credentials as a list of bare variable names
rather than assignments, which passes each one through only when it is set in the
launching shell. That is the same split as `.env` versus `.env.example`: nothing
is stored in the repository, and the repository only records which capabilities
exist. Running `/login` inside the container is the alternative path and writes
the gitignored `agent/auth.json` instead.

## What guards this

The memory test suite reads these files and fails on regressions in the
decisions, so the hygiene is asserted rather than assumed:

- `context/un-excluded` requires `^!Dockerfile\.supermemory$` and
  `context/no-env` requires that `.env` is still excluded
  (`test/supermemory.sh#L310-L319`);
- `state/env-ignored`, `state/envexample-kept` and `state/envexample-no-key` pin
  the `.env` split and keep a live key out of the example file
  (`test/supermemory.sh#L321-L331`);
- `hygiene/no-secrets` greps the image file, the Compose file, the example
  environment, `agent/AGENTS.md` and the launcher for credential-shaped strings
  and fails if any of them match (`test/supermemory.sh#L333-L344`).

The hygiene assertion is a superset of the other two: whatever the layout, no
committed file may carry a credential.
