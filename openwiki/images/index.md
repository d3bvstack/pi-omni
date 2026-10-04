# Files

- [Agent image](agent-image.md) - What the Pi agent image contains and why — the two-stage build, the pinned Pi version, the runtime tool set and fd symlink, the separately staged pi entry point, the deliberate absence of a USER directive, and the agent-directory environment.
- [Memory engine image](memory-engine-image.md) - How the self-hosted Supermemory engine is built — a pinned non-open-source release fetched from its manifest and checksum-verified instead of piped into a shell, architecture mapping from dpkg, a pre-created data directory, and an image that publishes nothing.
- [Platform pruning](platform-pruning.md) - The build-time script that deletes node_modules entries the running platform cannot use — why a shrinkwrapped esbuild tree carries every platform, the os/cpu matching rule with negation, scope traversal, and the image size it recovers.
