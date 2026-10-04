# Sandbox image for the Pi coding agent.
#
# The agent's configuration is deliberately NOT baked in here: bin/pi bind-mounts
# this repository's agent/ directory at run time, so the repository stays the
# single source of truth for the agent's setup.
#
# Two stages, so that the build stage's layers never reach the image. The build
# stage resolves the Pi package and discards what this platform cannot use; the
# runtime stage keeps the agent's tools and the pruned package tree, nothing else.

# --- build -------------------------------------------------------------------

FROM node:24-bookworm-slim AS build

# Pinned so that rebuilding is reproducible. Bump deliberately.
ARG PI_VERSION=1.0.2

RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

# The shrinkwrap npm installs from pins a platform binary for every operating
# system esbuild supports, and the npm cache is another 143 MB. Neither is worth
# carrying, and neither is copied below, so both go here instead. npm's `pi` link
# is staged on its own, because COPY resolves a symlink given as its own source.
COPY prune-platform-packages.js /tmp/
RUN set -eux; \
    node /tmp/prune-platform-packages.js /usr/local/lib/node_modules; \
    mkdir -p /out/bin; \
    cp -a /usr/local/bin/pi /out/bin/; \
    rm -rf /tmp/prune-platform-packages.js /root/.npm

# --- runtime -----------------------------------------------------------------

FROM node:24-bookworm-slim

# Debian ships the file finder as `fd-find` but installs the binary as `fdfind`,
# so the symlink below gives the agent the name it expects.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash ca-certificates curl fd-find file git jq less openssh-client \
        procps python3 ripgrep; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/lib/node_modules/ /usr/local/lib/node_modules/
# npm's own link, which has to arrive as a link: cli.js locates the rest of itself
# relative to its own path. Only this entry is taken, because npm shares
# /usr/local/bin with node, npx and corepack and the base image ships those at the
# same paths already. The check below follows the link, so a package that moves
# its entry point fails the build here instead of at the first `pi`.
COPY --from=build /out/bin/ /usr/local/bin/
RUN test -x /usr/local/bin/pi

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/pi-entrypoint

# No USER directive on purpose. Whether the agent runs as root or as the host
# user's uid depends on whether the Docker daemon is rootless, and bin/pi decides
# that per run.
ENV PI_CODING_AGENT_DIR=/pi/agent PI_WORKSPACE=/workspace

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/pi-entrypoint"]
CMD ["pi"]
