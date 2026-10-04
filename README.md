# Pi agent container hub

A container image that runs the [Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)
with a small set of everyday CLI tools, plus a launcher that mounts whichever
project you point it at.

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

`docker-compose.yml` is the only definition of a run: image, two mounts,
environment. `bin/pi` adds what compose cannot know and hands off.

```yaml
flow:
  - bin/pi: resolve DIR (default .); export PROJECT_DIR, AGENT_DIR, PI_IMAGE
  - bin/pi: --user only on rootful Docker; -T only when stdin or stdout is not a tty
  - build: docker compose build pi — runs only if the image is absent or --build was passed
  - run: docker compose run --rm pi — mode is pi or bash, leftover args go to the agent
  - entrypoint: HOME fallback; git config --global --add safe.directory $PI_WORKSPACE
  - entrypoint: stderr banner — workspace, agent dir, effective HOME, /login hint
  - exec: pi | bash
```

```yaml
bin/pi: launcher, POSIX sh, honours PI_IMAGE (default pi-agent:latest)
Dockerfile: sandbox image; ARG PI_VERSION=1.0.0 pins the agent
docker-compose.yml: the run definition — image, mounts, environment
docker-entrypoint.sh: container entrypoint, execs the agent or the shell
Makefile: help, build, install, uninstall, update, pin, clean, test
scripts/: build-time helpers only, copied in for the build stage and absent from the runtime image
  prune-platform-packages.js: drops the node_modules this platform cannot run
test/make-targets.sh: hermetic suite for the Makefile targets
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
`agent/AGENTS.md`, `agent/models.json`, and the `agent/skills/`,
`agent/prompts/` and `agent/extensions/` directories. Gitignored, because it is
machine-specific or generated: `agent/auth.json`, `agent/mcp-auth.json`,
`agent/sessions/`, `agent/bin/`, `agent/tools/`, `agent/models-store.json` and
`agent/mcp.log`.

Pi re-reads the committed files on every start. After editing them by hand, run
`/reload` inside the agent. `agent/` is excluded from the Docker build context,
so no credential can reach an image layer.

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

## Adding a service

`docker-compose.yml` holds only the `pi` service, and adding to it is additive:
compose creates a project network on the first run, so a new service is
reachable from the agent by name, and `pi` launches are unaffected because
`compose run` starts only the service you ask for. Give it a `profiles:` entry
so `docker compose up` leaves it alone until you name it.

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
`agent/`. Override the image with `make build image=my-pi:dev` and the install
directory with `make install install_dir=~/bin`; `bin/pi` also honors
`PI_IMAGE`.

## Tests

`make test` runs `test/make-targets.sh`, which executes every target in a
throwaway copy of the repository with recording stubs for `docker` and `npm` on
`PATH`. No daemon, no network, and the repository itself is never modified. It
reports each check in TAP style, then a per-target verdict, and exits non-zero
if any check fails or if a target exists without a case:

```
make test              # everything
make test filter=pin   # only the cases whose name contains "pin"
```

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

## Upstream

- Agent: <https://github.com/earendil-works/pi>
- Containerization patterns: <https://pi.dev/docs/latest>
