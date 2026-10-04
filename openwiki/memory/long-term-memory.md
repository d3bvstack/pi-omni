---
type: system-architecture
title: Long-term memory
description: The self-hosted Supermemory subsystem end to end — network-only reachability at http://supermemory:6767, the AGENTS.md contract the agent follows, first-boot key retrieval, ingestion and recall semantics, and the documented failure modes from warm-up to provider credit.
tags: [memory, supermemory, http-api, container-tag, failure-modes, contracts]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-5f5b95b3d6a215fa02ceb945
    resource: repo://.env.example
  - id: openwiki-source-4dd766881eeb1848d297e025
    resource: repo://agent/AGENTS.md
  - id: openwiki-source-b79fbbd921df689b4bbdc82f
    resource: repo://docker-compose.yml
  - id: openwiki-source-bb1ebe868e35e9e500714501
    resource: repo://Dockerfile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

The agent has a self-hosted [Supermemory](https://supermemory.ai/docs) server
beside it for memory that survives a session. It is a second Compose service on
the project network, and this page covers the whole path: how it is reached, how
the agent is told to use it, how a fresh machine gets a key, and how it fails.

## Reachability

The engine is reachable at `http://supermemory:6767` **on the compose network
only** (`agent/AGENTS.md#L22-L28`). It is not configurable and not on the host:
there is no `ports:` entry for the service, so a `curl` from the host failing is
expected rather than a symptom. The URL is written in two places — the Compose
file's comments and `agent/AGENTS.md` — deliberately, so the two cannot drift,
and it is not an environment variable because there is nothing to keep in sync.

## The contract is the whole interface

Self-hosting does not ship an MCP server, so the agent calls the HTTP API with
the `curl` and `jq` already in the image (`agent/AGENTS.md#L22-L24`). What
`agent/AGENTS.md` documents is therefore the entire integration surface:

- every request carries `Authorization: Bearer $SUPERMEMORY_API_KEY`; if that
  variable is empty, memory is simply not configured on this machine and the
  agent carries on without it rather than reporting an error
  (`agent/AGENTS.md#L29-L31`);
- `POST /v3/documents` ingests, `POST /v4/search` recalls semantically, and
  `POST /v4/profile` holds stable facts about the user or project
  (`agent/AGENTS.md#L38-L42`).

### containerTag is the project boundary

Every write and every read is scoped with `containerTag`, set to the name of the
directory under `/workspace` (`agent/AGENTS.md#L32-L36`). Tags must match
`^[a-zA-Z0-9_:-]+$`, so anything outside that is replaced. The instruction is
unconditional — never read or write a tag other than the current project's —
because that tag is the only boundary between projects, and crossing it leaks one
repository's context into another.

### Asynchronous writes

Ingestion returns a status, not a result, and search returns nothing for the new
document until extraction finishes (`agent/AGENTS.md#L43-L47`). A recall that
misses something just written is the queue, not a lost memory; the contract says
not to rewrite in a loop. When a memory must be searchable the moment it lands,
the write sends `"dreaming": "instant"`.

A queued write can still end as `status: "failed"`, and a failed document is
invisible to search afterwards — so status has to be checked before telling the
user something was remembered. The usual cause is the engine's own LLM provider,
not the request, and retrying does not fix it (`agent/AGENTS.md#L48-L51`).

`customId` makes a write idempotent: re-sending the same content updates it
rather than duplicating, so it should be a stable value derived from what is
being stored and not a timestamp (`agent/AGENTS.md#L52-L54`).

## Getting a key on a fresh machine

The engine has no wizard without a TTY, so it prints its API key on first boot:

```bash
docker compose run --rm supermemory
```

That key goes into `.env` as `SUPERMEMORY_API_KEY`, which Compose forwards to the
agent container on the next launch. It stays useful across restarts because the
engine's auth secret lives in the `supermemory` named volume rather than in the
image or the repository.

The engine also needs one LLM provider for extraction — summaries, contextual
chunking and memory extraction. It is configured entirely from the environment:
`SUPERMEMORY_MODEL` in `.env`, reached through OpenRouter's OpenAI-compatible
interface because the engine does not know OpenRouter as a provider. Embeddings
default to a local model (`Xenova/bge-base-en-v1.5`, 768d) and stay on the
machine; `.env.example` carries the three variables that move them, with the
warning that the dimension is locked to whatever the stored vectors already are.

## Failure modes worth knowing before changing any of this

- **First boot is slow.** A fresh volume downloads about 106 MB of embedding
  model before the engine can answer. `pi` waits only for `service_started`, never
  for health, so a launch is never blocked by it.
- **Ready is not the same as answering.** The healthcheck watches the welcome
  page, which starts answering a second or two before the API does; a call in
  that window returns `Unauthorized` with a valid key. This is observed, not
  inferred, and the agent's contract is to treat memory as unavailable and
  continue (`agent/AGENTS.md#L55-L60`).
- **The two 401s mean different things.** `{"error":"Unauthorized"}` means the key
  is missing or wrong; `Either userId or orgId not found` means the engine is
  still loading.
- **The provider needs credit.** Extraction is the one step that calls a model,
  and an exhausted provider lands the write as `status: "failed"` and drops it
  out of search. `supermemory-server doctor` reports all green in exactly this
  situation because it cannot see an account balance; the account error appears
  only in the logs, as `memory agent failed: Insufficient credits`.
- **State outlives `make clean`.** `docker compose down` does not remove the named
  volume; discarding memory deliberately means `docker compose down --volumes`.

What is asserted about all of this, and what deliberately is not, is covered by
the hermetic suites; the volume, provider and port rules belong to the Compose
run definition and the memory engine image.
