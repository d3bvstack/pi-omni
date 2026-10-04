# Pi agent container hub

A container image that runs the [Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
with a small set of everyday CLI tools, plus a launcher that mounts whichever
project you point it at, plus a self-hosted memory server the agent can read and
write.

The point of the repository is the `agent/` directory: it holds the agent's
configuration and is mounted into every launch, so the agent behaves the same
way in every project without per-project setup. Commit it and the setup travels
with the repository.

## Install and use

Requires Docker on Linux or macOS. `make install` symlinks `bin/pi` into
`~/.local/bin`; restart your shell, or call `./bin/pi` directly.

```
pi                    mount the current directory read-write, start the agent
pi DIR                mount DIR read-write, start the agent
pi --shell [DIR]      same mounts, but a shell instead of the agent
pi --build [DIR]      rebuild the image first
pi [DIR] -- ARGS...   forward ARGS to the agent
pi --version          identify the launcher, without starting a container
pi --help
```

```bash
pi ~/src/myproject    # work on another directory
pi --build            # rebuild the image, then start
pi . -- -p "add tests" # one-shot, non-interactive
```

The argument must be a directory; anything else exits `2` rather than being
silently ignored. Both forms mount read-write, so anything the agent writes
under `/workspace` goes straight to the host. There is no undo boundary, so
`git commit` before large edits.

## How a run is put together

`docker-compose.yml` is the only definition of a run: two services, and for the
agent an image, two mounts and an environment. `bin/pi` adds what compose cannot
know and hands off.

```yaml
flow:
  - bin/pi: resolve DIR (default .); export PROJECT_DIR, AGENT_DIR, PI_IMAGE, SUPERMEMORY_IMAGE
  - bin/pi: --user only on rootful Docker; -T only when stdin or stdout is not a tty
  - build: docker compose build pi supermemory — runs only if either image is absent, or --build was passed
  - run: docker compose run --rm pi — mode is pi or bash, leftover args go to the agent
  - entrypoint: HOME fallback; git config --global --add safe.directory $PI_WORKSPACE
  - entrypoint: stderr banner — workspace, agent dir, effective HOME, /login hint
  - exec: pi | bash
```

```yaml
bin/pi: launcher, POSIX sh, honours PI_IMAGE (default pi-agent:latest) and SUPERMEMORY_IMAGE
Dockerfile: sandbox image; ARG PI_VERSION=1.0.0 pins the agent
Dockerfile.supermemory: memory engine; ARG SUPERMEMORY_VERSION=0.0.8 pins it, sha256-checked
docker-compose.yml: the run definition — image, mounts, environment, and the supermemory service
docker-entrypoint.sh: container entrypoint, execs the agent or the shell
Makefile: help, build, install, uninstall, update, pin, clean, test, test-memory
scripts/: build-time helpers only, copied in for the build stage and absent from the runtime image
  prune-platform-packages.js: drops the node_modules this platform cannot run
test/make-targets.sh: hermetic suite for the Makefile targets
test/supermemory.sh: hermetic suite for the memory wiring
agent/: agent configuration; mounted at run time, never baked into the image
```

```yaml
workdir: /workspace
uid: host uid:gid on rootful Docker, root on rootless (see "File ownership")
home: $HOME when writable, else /tmp/pi-home — rootful Docker only, git and npm
      need it because the host uid usually has no passwd entry
mounts:
  /workspace:
    source: ${PROJECT_DIR:-.}
    access: read-write        # writes land on the host, no undo boundary
  /pi/agent:
    source: ${AGENT_DIR:-./agent}
    access: read-write        # PI_CODING_AGENT_DIR; set by the image, not the host
```

```yaml
tools: [bash, git, rg, fd, jq, curl, less, file, procps, python3, openssh-client,
        make]
from base image: [node, npm]
absent:
  - "no compiler toolchain: no gcc and no build-essential. `make` is present, but
     only for driving build recipes -- there is nothing for it to compile"
  - "`fd` is a symlink to Debian's `fdfind`, not a binary of that name"
notes:
  - "agent/AGENTS.md states the missing toolchain so the agent does not assume otherwise"
```

The `Dockerfile` has two stages, so no build-only layer ships. `pi-coding-agent`
publishes an `npm-shrinkwrap.json`, and npm installs a shrinkwrap verbatim rather
than filtering optional dependencies by `os` and `cpu` — so esbuild's binary for
all twenty-six platforms it supports is installed, 273 MB of which one is usable.
`scripts/prune-platform-packages.js` removes the rest by that same rule and drops
the npm
cache. That is the whole difference between 1373 MB and 715 MB.

## Configuration versus state

Committed, because it is the setup worth sharing: `agent/settings.json`,
`agent/AGENTS.md`, `agent/models.json`, `agent/mcp.json`, and the
`agent/skills/`, `agent/prompts/` and `agent/extensions/` directories.
Gitignored, because it is machine-specific or generated: `agent/auth.json`,
`agent/mcp-auth.json`, `agent/sessions/`, `agent/bin/`, `agent/tools/`,
`agent/npm/`, `agent/models-store.json` and `agent/mcp.log`. `.env` is
gitignored and `.env.example` is committed, which is the same split for the
credentials Compose resolves.

Pi re-reads the committed files on every start. After editing them by hand, run
`/reload` inside the agent. `agent/` is excluded from the Docker build context,
so no credential can reach an image layer.

## Packages

`agent/settings.json` declares the Pi packages to load:

```json
"packages": ["npm:openwiki"]
```

[openwiki](https://pi.dev/packages/openwiki) loads an extension and a skill that
maintain a Markdown wiki of a repository. The spec is floating, so the gallery
page's `pi update` picks up new versions; pin it as `npm:openwiki@0.7.0` if you
would rather it did not move.

Only the declaration is committed. Installing runs `npm install` into the
package directory, which is `agent/npm/` here because Pi derives it from the
agent directory, and that is 300 MB of dependencies, so it is gitignored and
recreated per machine. A fresh checkout therefore declares the package without
having installed it; the first run in a new clone installs it, and `pi list`
reports what is present.

## Authentication

Two options, and they compose.

1. Export a provider key in your host shell. The `environment:` list in
   `docker-compose.yml` forwards all 43 provider variables Pi documents, plus
   its `PI_OFFLINE` and `PI_TELEMETRY` toggles, and only when they are actually
   set, so nothing is stored in this repository. Four variables Pi also
   documents are deliberately not forwarded: `PI_CODING_AGENT_DIR`, which the
   image sets itself, and `PI_CODING_AGENT_SESSION_DIR`, `PI_PACKAGE_DIR` and
   `PI_SHARE_VIEWER_URL`, which have no use here. The list is kept in sync with
   `pi --help`; it was taken from Pi 1.0.0.

   ```bash
   export ANTHROPIC_API_KEY=...   # or OPENROUTER_API_KEY, GEMINI_API_KEY, ...
   pi
   ```

2. Run `/login` inside the container. Pi writes the credential to
   `agent/auth.json`, which is gitignored but persists between runs; `/logout`
   removes it.

Then pick a model with `/model`. For anything Pi does not already know about,
add a provider to `agent/models.json`, for example a local Ollama server:

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

Note `host.docker.internal`, not `localhost`: inside the container, `localhost`
is the container.

## Long-term memory

The agent has a self-hosted [Supermemory](https://supermemory.ai/docs) server
beside it, reachable only at `http://supermemory:6767` on the project network.
There is no MCP server for it — self-hosting does not ship one — so the agent
calls the HTTP API with the `curl` and `jq` already in the image.
`agent/AGENTS.md` is the contract: the endpoint, the three endpoints worth
knowing, and the `containerTag` rule that keeps one repository's memory out of
another's.

```bash
docker compose run --rm supermemory   # first boot prints the API key
```

Put that key in `.env` as `SUPERMEMORY_API_KEY` and it is forwarded to the agent
container on the next launch. The endpoint itself is not a variable: it is the
service name, and it is written in both `docker-compose.yml` and
`agent/AGENTS.md` so the two cannot drift.

The engine needs one LLM provider for extraction — summaries, contextual chunking
and memory extraction. It has no wizard without a TTY, so it is configured from
the environment: `SUPERMEMORY_MODEL` in `.env`, reached through OpenRouter's
OpenAI-compatible interface. Embeddings default to a local model and stay on the
machine; `.env.example` has the variables to change that.

Four things worth knowing before changing any of it:

- **No published port, on purpose.** The pinned release (0.0.8) binds every
  interface and its implicit local authentication is unsafe on an untrusted
  network — Supermemory's own self-hosting docs say so. The compose network is
  the isolation. `test/supermemory.sh` fails if a `ports:` line appears under the
  service.
- **State outlives `make clean`.** The graph, the auth secret and the embedding
  model live in the `supermemory` named volume, which `docker compose down` does
  not remove. To discard the memory on purpose:
  `docker compose down --volumes`.
- **The binary is not open source.** `Dockerfile.supermemory` pins the version and
  verifies the sha256 against the release manifest, which catches a corrupted
  download and nothing more. Read a version bump before making one.
- **First boot is slow.** A fresh volume downloads a local embedding model
  (about 106 MB) before it can answer. `pi` deliberately waits only for the
  engine to *start*, not to become healthy, so a launch is never blocked by it.
- **Ready is not the same as answering.** The healthcheck watches the engine's
  welcome page, and that page starts answering a second or two before the API
  does. A call made in that window returns `Unauthorized` even with a valid key.
  This is observed, not inferred, and it is why `depends_on` is `service_started`
  rather than `service_healthy` — a health gate would still let the first session
  through early.
- **The LLM provider needs credit.** Extraction is the one step that calls a
  model, and if that provider has no balance the write lands as
  `status: "failed"` and drops out of search. `supermemory-server doctor` checks
  the configuration and reports all green in exactly this situation, because it
  cannot see an account balance; the account error is only in the logs, as
  `memory agent failed: Insufficient credits`.

To move the extraction model onto your own hardware instead of OpenRouter, drop
the `OPENAI_BASE_URL` line and point it at a local OpenAI-compatible server on the
same network, per the next section.

## Adding a service

Adding to `docker-compose.yml` is additive: compose creates a project network on
the first run, so a new service is reachable from the agent by name, and `pi`
launches are unaffected because `compose run` starts only the service you ask for.

Whether a service needs a `profiles:` entry depends on whether the agent depends
on it. `supermemory` does, so it has none — a profiled service is left out of
`compose run pi` and the agent's lookup of `supermemory` then fails outright
instead of degrading. A tool the agent may reach but that need not exist on every
launch goes behind a profile, and `docker-compose.yml` documents the pattern:

```yaml
  ollama:
    image: ollama/ollama
    profiles: [tools]
    ports: ["11434:11434"]
```

```bash
docker compose --profile tools up -d   # docker compose run --rm ollama also works
```

A model server added this way is then `baseUrl: http://ollama:11434/v1` in
`agent/models.json`, which avoids `host.docker.internal` entirely.

To build only the new one, name it as a service word: `make build supermemory`.
Every word in the Makefile's `SERVICES` gets a no-op rule so it can be named at
all, which is why that list and `TARGETS` have to be kept apart.

## File ownership

`bin/pi` checks whether the Docker daemon is rootless and adapts.

- **Rootless Docker** already maps container root onto your host user, so the
  container runs as root. Passing a uid would make files show up on the host
  owned by a subordinate uid instead, so it does not.
- **Rootful Docker** would leave files owned by real root, so the container runs
  as your own `uid:gid`. Because that uid often has no passwd entry, the
  entrypoint falls back to a writable scratch `HOME` at `/tmp/pi-home` for git,
  npm and Pi state.

Either way, files the agent writes into `/workspace` belong to you.

## Make targets

`make help` lists the targets and the variables they read. `make build` builds
the image, `make install` symlinks `pi` and `make uninstall` removes that
symlink, `make update` pins the latest published agent version in the
`Dockerfile` (`make pin version=x.y.z` for a specific one), and `make clean`
removes the image, the project network and any stopped containers, keeping
`agent/` and the memory volume. Override the image with
`make build image=my-pi:dev` and the install directory with
`make install install_dir=~/bin`; `bin/pi` also honors `PI_IMAGE` and
`SUPERMEMORY_IMAGE`, and builds either image when it is missing.

## Tests

Two suites, because they are hermetic in different ways.

`make test` runs `test/make-targets.sh`, which executes every target in a
throwaway copy of the repository with recording stubs for `docker` and `npm` on
`PATH`. No daemon, no network, and the repository itself is never modified. It
reports each check in TAP style, then a per-target verdict, and exits non-zero
if any check fails or if a target exists without a case:

```
make test              # everything
make test filter=pin   # only the cases whose name contains "pin"
```

`make test-memory` runs `test/supermemory.sh`, which only reads files: no daemon,
no network, no API key, and it never reads `.env`. It guards the decisions that
are expensive to get wrong and invisible once they are — no published port, a
pinned and checksummed binary, a named volume, the key forwarded, the contract in
`AGENTS.md` matching the compose service name.

```
make test test-memory   # both
```

Both read `filter=` as a substring and pass it to their own suite. What neither
suite does is prove the engine works; that needs a boot, a first-boot API key
and a real round trip, so it is not written yet.

## Troubleshooting

A native `pi` (`npm install -g @earendil-works/pi-coding-agent`) also accepts
`--version`, but prints only its version number, so `pi --version` tells the two
apart: the launcher names itself and the image it will use. A native install
lands in `~/.nvm/versions/node/*/bin`, normally *earlier* on `PATH` than
`~/.local/bin`, and therefore wins in scripts, `ssh` sessions and `make`
recipes. Remove it, or put this repository's `bin` earlier on `PATH`.

- **`pi: cannot reach the Docker daemon`.** Docker is not running, or your user
  is not in the `docker` group.
- **The image rebuilds on every launch.** It should only build when the image is
  absent; check that `PI_IMAGE` is not set to something else.
- **A change to `agent/` is ignored.** Run `/reload`, or start a new session.
- **`permission denied` on a mounted path.** The host directory is not readable
  by the uid the container runs as, which on rootful Docker is your own uid.
- **Changing the Pi version.** `make update` pins the latest published version in
  `ARG PI_VERSION` in the `Dockerfile`, or edit that line by hand, then
  `make build`. The version is pinned deliberately, so rebuilds are
  reproducible.
- **The memory engine is unreachable from the agent.** `docker compose ps` first.
  If it is not running, `docker compose logs supermemory`. It is reachable at
  `http://supermemory:6767` only from inside the project network, so a `curl` from
  the host failing is expected and not the problem.
- **The engine boots but never becomes ready.** A fresh volume downloads a local
  embedding model on first boot. `docker compose logs -f supermemory` shows it.
- **Every memory call fails with 401.** Two different causes, and the message
  tells them apart. `{"error":"Unauthorized"}` means the key is missing or wrong;
  re-run `docker compose run --rm supermemory` for the current one.
  `Either userId or orgId not found` means the engine is still loading right after
  a start — wait a second and try again.
- **Changing the Supermemory version.** Edit `ARG SUPERMEMORY_VERSION` in
  `Dockerfile.supermemory`, then `make build supermemory`. Read the release notes
  first: the self-hosting docs warn that 0.0.8 binds every interface and that a
  later release changes both the bind address and whether the generated key is
  required, which is what the no-`ports:` decision rests on.

## Upstream

- Agent: <https://github.com/earendil-works/pi>
- Containerization patterns: <https://pi.dev/docs/latest>
- Memory: <https://supermemory.ai/docs> — self-hosting at [/docs/self-hosting](https://supermemory.ai/docs/self-hosting/overview)
