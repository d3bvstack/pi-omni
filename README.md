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

There is one definition of a run, in `docker-compose.yml`: the image, the two
mounts, the environment. `bin/pi` only supplies what compose cannot know — the
directory you named, the uid, whether to allocate a terminal — and execs
`docker compose run --rm pi`, building the image first if it is absent.

```
bin/pi                       the launcher
Dockerfile                   sandbox image
docker-compose.yml           the run definition: image, mounts, environment
docker-entrypoint.sh         container entrypoint
prune-platform-packages.js   build stage only: drops node_modules for other platforms
Makefile
agent/                       the agent's configuration directory (mounted)
```

| Path         | Contents                                   |
| ------------ | ------------------------------------------ |
| `/workspace` | the project, read-write                    |
| `/pi/agent`  | the agent directory (`PI_CODING_AGENT_DIR`) |

The image ships `bash`, `git`, `ripgrep` (`rg`), `fd`, `jq`, `curl`, `less`,
`file`, `procps`, `python3` and `openssh-client`. There is no compiler toolchain;
`agent/AGENTS.md` tells the agent so it does not assume otherwise. The
entrypoint prints the workspace, agent directory and effective `HOME` to stderr
on every start, then execs the agent or the shell.

The `Dockerfile` has two stages. The build stage installs Pi and discards what
cannot run on this machine, and the runtime stage copies in the result, so none of
the build-only layers ship. `pi-coding-agent` publishes an `npm-shrinkwrap.json`,
and npm installs a shrinkwrap verbatim instead of filtering optional dependencies
by `os` and `cpu` — so esbuild's binary for all twenty-six platforms it supports
is installed, 273 MB of which one is usable. `prune-platform-packages.js` removes
the rest by that same rule, and the npm cache is dropped with them. This takes
the image from 1373 MB to 715 MB.

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

`make help` lists them. `make build` builds the image, `make install` symlinks
`pi`, `make clean` removes the image, the project network and any stopped
containers, keeping `agent/`. Override the image with `make build image=my-pi:dev`
and the install directory with `make install install_dir=~/bin`; `bin/pi` also
honors `PI_IMAGE`.

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
- **Changing the Pi version.** Edit `ARG PI_VERSION` in the `Dockerfile`, then
  `make build`. The version is pinned deliberately, so rebuilds are
  reproducible.

## Upstream

- Agent: <https://github.com/earendil-works/pi>
- Containerization patterns: <https://pi.dev/docs/latest>
