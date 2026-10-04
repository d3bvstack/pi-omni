# Files

- [Agent configuration](agent-configuration.md) - The agent/ directory as shared setup that travels with the repository — which files are committed configuration, which are machine state, how a declared Pi package differs from its install tree, and how a local model provider is added.
- [Build context and secret hygiene](build-context-and-secrets.md) - How credentials and machine state are kept out of both images and commits — the .dockerignore allowlist and its parent-un-exclusion rule, the grouped .gitignore, and the .env versus .env.example split that mirrors Compose's conditional forwarding.
