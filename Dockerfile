# Sandbox image for the Pi coding agent.
#
# The agent's configuration is deliberately NOT baked in here: bin/pi bind-mounts
# this repository's agent/ directory at run time, so the repository stays the
# single source of truth for the agent's setup.
FROM node:24-bookworm-slim

# Pinned so that rebuilding is reproducible. Bump deliberately.
ARG PI_VERSION=1.0.0

# Debian ships the file finder as `fd-find` but installs the binary as `fdfind`,
# so the symlink below gives the agent the name it expects.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash ca-certificates curl fd-find file git jq less openssh-client \
        procps python3 ripgrep; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/pi-entrypoint

# No USER directive on purpose. Whether the agent runs as root or as the host
# user's uid depends on whether the Docker daemon is rootless, and bin/pi decides
# that per run.
ENV PI_CODING_AGENT_DIR=/pi/agent PI_WORKSPACE=/workspace

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/pi-entrypoint"]
CMD ["pi"]
