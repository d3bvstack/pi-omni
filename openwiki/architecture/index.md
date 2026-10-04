# Files

- [Compose run definition](compose-run-definition.md) - How docker-compose.yml defines every agent run — the pi and supermemory services, the shared project network, the two bind mounts, conditionally forwarded provider keys, the memory volume, and the healthcheck and restart policy.
- [Container entrypoint](container-entrypoint.md) - What docker-entrypoint.sh does before the agent starts — choosing a writable HOME for a uid without a passwd entry, marking the mounted project as a safe git directory, printing the startup banner — and why it execs rather than supervising.
- [Host launcher (bin/pi)](host-launcher.md) - The POSIX sh launcher that turns a host invocation into a container run — symlink resolution to the repository root, argument grammar, directory validation, the rootless-versus-rootful uid decision, terminal detection and the final exec of compose.
- [Run lifecycle](run-lifecycle.md) - The end-to-end path from a host `pi` invocation to a live agent session — argument resolution, image gating, compose run, container startup — and the mounts and environment the session inherits.
