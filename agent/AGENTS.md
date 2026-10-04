# Agent instructions

These instructions are part of the agent configuration in this repository and
are mounted into every container the `pi` launcher starts, so they apply in
every project the agent is pointed at.

## Environment

- The project under work is mounted read-write at `/workspace`. This is the
  agent's working directory.
- This directory is mounted at `/pi/agent` and is the agent directory, so
  settings, skills, prompts, extensions and sessions all live here.
- The container has `git`, `ripgrep` (`rg`), `fd` (`fd`), `jq`, `curl`, `less`
  and `python3`. It does not have a compiler toolchain; if a task needs one,
  say so rather than assuming it is available.
- Writes under `/workspace` go straight to the host. There is no undo boundary,
  so confirm before rewriting or deleting anything that is not clearly
  reproducible from version control.

## Long-term memory

A self-hosted Supermemory server runs alongside this container and is reachable
only on the compose network. There is no MCP server for it, so the interface is
HTTP through the `curl` and `jq` already installed here.

- Base URL: `http://supermemory:6767`. Not configurable and not on the host. If
  the name does not resolve, the engine is not running; the last bullet says
  what to do about that.
- Every request needs `Authorization: Bearer $SUPERMEMORY_API_KEY`. If that
  variable is empty, memory is not configured on this machine — carry on
  without it rather than reporting an error.
- Scope every write and every read with `containerTag`, set to the name of the
  directory under `/workspace`. Tags match `^[a-zA-Z0-9_:-]+$`, so replace
  anything outside that. Never read or write a tag other than the current
  project's: that is the only boundary between projects, and crossing it leaks
  one repository's context into another.

  | Call | Purpose |
  |---|---|
  | `POST /v3/documents` | Ingest. Takes `content`, `containerTag`, and `customId`. |
  | `POST /v4/search` | Semantic recall. Takes `q`, `containerTag`. |
  | `POST /v4/profile` | Stable facts about the user or project. |
- Ingestion is asynchronous. A write returns with a status, not a result, and
  `POST /v4/search` returns nothing for it until extraction finishes. If a
  recall misses something you just wrote, that is the queue, not a lost memory —
  do not rewrite it in a loop. Send `"dreaming": "instant"` when a memory has to
  be searchable the moment it lands.
- A queued write can still end in `status: "failed"`, and a failed document is
  invisible to search afterwards. Check the status before telling the user
  something was remembered. The usual cause is the engine's own LLM provider
  rather than anything in the request, and it is not something retrying fixes.
- `customId` makes a write idempotent, so re-sending the same content updates it
  instead of duplicating it. Use a stable value derived from what you are
  storing, not a timestamp.
- The engine is a separate container that boots independently and, on a fresh
  volume, downloads a local embedding model before it can answer. Just after it
  starts, API calls can briefly return `Unauthorized` while it finishes loading,
  even though its welcome page already answers. Treat memory as unavailable and
  continue the task; do not retry in a loop and do not treat it as a reason to
  stop.

Use memory for decisions and conventions that are expensive to rediscover —
why a choice was made, what was already ruled out, how the user wants things
done. Do not use it to store file contents that git already tracks, and do not
store anything the user has not asked you to remember.

## Working agreement

- Read before writing. Inspect the existing code and match its conventions
  instead of introducing a new style.
- Prefer the narrowest change that solves the problem. Leave unrelated
  formatting, renaming and cleanup out of a fix.
- Run the project's own tests and linters to verify a change, and report the
  actual output rather than an assumption that it passed.
- If a task is ambiguous, state the interpretation you are proceeding with
  instead of guessing silently.
