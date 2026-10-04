---
type: runtime-component
title: Host launcher (bin/pi)
description: The POSIX sh launcher that turns a host invocation into a container run — symlink resolution to the repository root, argument grammar, directory validation, the rootless-versus-rootful uid decision, terminal detection and the final exec of compose.
tags: [launcher, posix-sh, cli, uid, docker, argument-parsing]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-afe52c853cc950b31949ac9d
    resource: repo://bin/pi
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

`bin/pi` is the only code in this repository that runs on the host. Everything
else is either baked into an image or read by the agent inside a container, so
this script owns the decisions Compose cannot make for itself: which directory
to mount, which uid to run as, whether to allocate a terminal, and whether an
image needs building.

It is written in POSIX `sh` deliberately. The launcher runs on whatever `/bin/sh`
the host happens to have, which is not always bash 5, so it uses no arrays and no
bash-only builtins (`bin/pi#L1-L9`). That constraint is visible in the code: the
symlink walk is unrolled by hand because `readlink -f` is not available
everywhere, and the final `exec` leaves `$tty` and `$user` unquoted so an empty
value disappears as an argument rather than becoming an empty one.

## Finding the repository

`make install` puts `bin/pi` on `PATH` as a symlink, so `$0` is not the file
itself and the repository root cannot be derived from it directly. The script
walks the symlink chain itself, handling absolute and relative link targets
(`bin/pi#L19-L26`), and derives `repo_root` from the parent of the resolved file
(`bin/pi#L27`). Everything downstream — the compose file, the agent directory, the
symlink check in the Makefile — is located relative to that root, which is what
lets the launcher be called from anywhere on `PATH`.

The two image names are resolved here and overridable from the environment:
`PI_IMAGE` defaults to `pi-agent:latest` and `SUPERMEMORY_IMAGE` to
`supermemory-server:local` (`bin/pi#L28-L31`). They are re-exported later so that
Compose resolves the same names the launcher checked for.

## Argument grammar

The loop accepts options in any position before `--`, and one optional
positional directory (`bin/pi#L37-L76`):

| Form | Effect |
|---|---|
| `-h`, `--help` | print usage, exit 0 |
| `-V`, `--version` | print launcher version, repo root and both image names, exit 0 |
| `--build` | force an image build before the run |
| `--shell` | run `bash` in the container instead of the agent |
| `--` | everything after belongs to the agent |
| `DIR` | the directory to mount at `/workspace` |

`--version` is worth noticing: it prints the image names, not just a version
number, which is how a user tells this launcher apart from a native `pi` install
that answers the same flag with a bare number.

Two argument errors are distinguished from operational failures by their exit
code. An unknown option and a second positional argument both print a message and
exit 2 (`bin/pi#L60-L74`), as does a target that is not a directory
(`bin/pi#L78-L83`) — the README frames that as a deliberate choice, "anything
else exits 2 rather than being silently ignored". Everything after `--` is left in
`"$@"` untouched for the agent.

## Deciding the uid

The launcher asks the daemon how it is configured rather than guessing:
`docker info --format '{{.SecurityOptions}}'` (`bin/pi#L89`). If that call fails,
there is no session to start, so it prints `pi: cannot reach the Docker daemon`
and exits 1 (`bin/pi#L89-L92`) — a different code from the argument errors,
because it is an environment problem rather than a usage problem.

The result branches on one word (`bin/pi#L93-L97`):

- **Rootless** (`*rootless*`): no `--user` is passed. Rootless Docker already maps
  container root onto the host user, so passing a uid would make files appear on
  the host owned by a subordinate uid.
- **Rootful**: `--user $(id -u):$(id -g)`. Container root is real root here, so
  the agent runs as the host user instead, and files it writes into `/workspace`
  belong to that user.

This is why the agent image declares no `USER` and why the entrypoint needs a
`HOME` fallback.

## Building only when needed

Images are built when `--build` was passed **or** when either image is absent
(`bin/pi#L100-L107`). The absence check uses `docker image inspect` rather than
the output of `compose run --rm`, which reports nothing useful after the
container is removed. Both services are built together when either is missing,
because on a fresh clone the memory engine is absent and `compose run pi` would
fail on `depends_on` without ever giving the agent a session.

## Handing off

Terminal allocation is decided the same way: `-T` is passed when stdin or stdout
is not a terminal (`bin/pi#L111-L114`), which is what makes the launcher usable
from scripts and pipes.

Then four variables are exported and Compose is execed
(`bin/pi#L116-L124`): `PROJECT_DIR` and `AGENT_DIR` become the two bind mounts,
`PI_IMAGE` and `SUPERMEMORY_IMAGE` resolve the image names. The compose file is
addressed by absolute path, the run is `--rm`, and the mode — `pi` or `bash` —
plus any leftover agent arguments follow as positional words.

`tty`, `user` and `mode` each hold at most one controlled word, so leaving them
unquoted drops the argument entirely when empty and cannot split; `"$@"` carries
the agent's own arguments through with their word boundaries intact. The script
ends in `exec`, so there is no wrapper process between the host shell and the
container command.
