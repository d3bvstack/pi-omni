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

## Working agreement

- Read before writing. Inspect the existing code and match its conventions
  instead of introducing a new style.
- Prefer the narrowest change that solves the problem. Leave unrelated
  formatting, renaming and cleanup out of a fix.
- Run the project's own tests and linters to verify a change, and report the
  actual output rather than an assumption that it passed.
- If a task is ambiguous, state the interpretation you are proceeding with
  instead of guessing silently.
