---
type: system-architecture
title: Agent configuration
description: The agent/ directory as shared setup that travels with the repository — which files are committed configuration, which are machine state, how a declared Pi package differs from its install tree, and how a local model provider is added.
tags: [configuration, agent-directory, settings, packages, models, gitignore]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-715dace563ef484b6e8bd1e2
    resource: repo://.dockerignore
  - id: openwiki-source-ea70eb6c045047448e446296
    resource: repo://.gitignore
  - id: openwiki-source-eed08757b01fd77ba180c394
    resource: repo://agent/models.json
  - id: openwiki-source-f951cc1c65c3e3f74a23c84e
    resource: repo://agent/settings.json
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-bb1ebe868e35e9e500714501
    resource: repo://Dockerfile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

`agent/` is the directory the agent treats as its own, mounted at `/pi/agent` on
every launch and named by `PI_CODING_AGENT_DIR` in the image. It is the reason
the agent behaves the same way in every project without per-project setup: the
configuration is committed here, and Compose bind-mounts it in rather than
baking it into the image.

The directory is split by one question — is this setup worth sharing, or is it
generated on one machine?

## Committed configuration

`agent/settings.json`, `agent/AGENTS.md`, `agent/models.json`, `agent/mcp.json`,
`agent/keybindings.json` and the `extensions/`, `skills/`, `prompts/` and
`themes/` directories. `.gitignore` states the list and the reason: "committed
because it is setup worth sharing" (`.gitignore#L12-L14`). All of these travel
with the repository, so a clone starts with the same tools, the same instructions
and the same model catalogue.

`settings.json` in this repository is short: the default tool set — the built-in
file and search tools plus `+codemode` — the last changelog version seen, the
system theme, and the package list (`agent/settings.json#L1-L17`).

## Machine state

Everything Pi derives from the agent directory that is generated rather than
authored is ignored, and the ignore file groups those entries by what they are:
credentials (`auth.json`, `mcp-auth.json`), history (`sessions/`), binaries
(`bin/`, plus `tools/`, which Pi migrates into `bin/` on startup), caches
(`models-store.json`), the package install tree (`npm/`) and logs (`mcp.log`)
(`.gitignore#L1-L24`). Credentials are the reason the split exists at all:
`/login` writes `agent/auth.json` inside the container, it persists between runs,
and it must never be committed.

## Packages: declaration versus install tree

`settings.json` can declare Pi packages, which is how extensions, skills, prompt
templates and themes are distributed as one unit. This repository declares
`npm:openwiki`, which loads an extension and a skill
(`agent/settings.json#L14-L16`).

Only the declaration is committed. Installing runs `npm install` into the package
directory, which is `agent/npm/` here because Pi derives it from the agent
directory, and that tree is gitignored and recreated per machine. A fresh clone
therefore declares the package without having installed it; the first run
installs it, and `pi list` reports what is actually present.

The spec is floating as written, so an update moves it forward; pinning it as
`npm:openwiki@0.7.0` would fix the version instead.

## Reading it back

Pi re-reads the committed files on every start, so a rebuild is never needed for
a configuration change. A hand edit inside a live session is the exception: run
`/reload`, which is also the answer to a change to `agent/` appearing to be
ignored (`README.md#L115-L117`).

## Adding a provider

`agent/models.json` is the extension point for model providers Pi does not already
know about. In this repository it ships empty (`{"providers": {}}`), and the
README's worked example is a local Ollama server:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://host.docker.internal:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [{ "id": "qwen2.5-coder:7b" }]
    }
  }
}
```

The address is `host.docker.internal`, not `localhost`, because inside the
container `localhost` is the container. The alternative is to run the model
server as a Compose service on the project network and use its service name,
which avoids `host.docker.internal` entirely.

## What does not live here

The agent's runtime — the Pi package, the tool set, the entrypoint — is baked into
the image, not configured here. `agent/` is excluded from the Docker build context
altogether, so nothing under it can reach an image layer.
