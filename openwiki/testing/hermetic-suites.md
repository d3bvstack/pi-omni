---
type: testing
title: Hermetic test suites
description: The two repository test suites and what they deliberately do not prove — the stub-and-copy harness with target-coverage enforcement in make-targets.sh, the comment-stripped file assertions in supermemory.sh, and the filters and TAP-like output they share.
tags: [testing, hermetic, tap, stubs, coverage, assertions]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-d78c31b3a02775aa3ebe56d7
    resource: repo://test/make-targets.sh
  - id: openwiki-source-9f48987939f2914d8aa0dbf5
    resource: repo://test/supermemory.sh
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

Two suites, because they are hermetic in different ways. Both read only files
and never touch a daemon, a network or an API key, which is what lets CI run one
of them anywhere with no services.

| | `test/make-targets.sh` | `test/supermemory.sh` |
|---|---|---|
| Runs | real `make`, in a throwaway copy | nothing; reads repository files |
| Fakes | recording `docker` and `npm` on `PATH` | none needed |
| Verdict per | Makefile target | aspect group |
| Filter variable | `MAKE_TEST_FILTER` | `MEMORY_TEST_FILTER` |

## make-targets.sh: copy the repository, stub the world

Every target executes for real in a temporary copy of the repository with
recording stubs at the front of `PATH`, so no daemon and no network are involved
and the checkout the developer is standing in is never written to
(`test/make-targets.sh#L1-L10`).

The harness copies only what the Makefile actually reads — the Makefile, the
Dockerfiles, the Compose file, the entrypoint, `bin/`, `scripts/`, the README —
and deliberately leaves out `.git`, `agent/` sessions and `.env`, both because
copying them is slow and because leaking local state into assertions is worse
(`test/make-targets.sh#L35-L43`). The `docker` stub appends every invocation to a
log and fails for `image rm` the way the daemon does when the image is already
gone, so `clean` has to cope with a real failure; the `npm` stub returns a canned
version so `update` is deterministic (`test/make-targets.sh#L45-L67`).

Cases are registered with `case_add NAME DESCRIPTION FUNCTION`, and the name's
prefix before the slash is the target it covers (`test/make-targets.sh#L140-L162`).
A case whose body returns non-zero is reported as *aborted* rather than passed,
which distinguishes a helper that never got to assert from one that asserted.

The suite's own exhaustiveness is asserted at the end: it asks make which targets
exist via `make -qp` and fails if any target has no case naming it
(`test/make-targets.sh#L580-L596`). That is what makes "the Makefile grew a
target and nobody noticed" a failure rather than a silent gap.

## supermemory.sh: read the files, believe the code

This suite guards the decisions that are expensive to get wrong and invisible
once they are — no published port, a pinned and checksummed binary, a named
volume, the key forwarded, the contract in `AGENTS.md` matching the Compose
service name. It reads `.env.example` and never `.env`, which holds a live key
(`test/supermemory.sh#L1-L20`).

Its distinguishing move is `strip_comments`, applied with
`sed 's/[[:space:]]*#.*$//'` to every file it asserts against
(`test/supermemory.sh#L42-L46`). The reason is stated in the file: these files
argue their choices in prose right next to the code, so a comment saying "no
`ports:`" is exactly the sentence a naive substring match would find — "a test
that reads the documentation as the behaviour is worse than no test". Assertions
therefore run against comment-free text.

Scope is by indentation, not grep: `service_block NAME` extracts one service's
body by indentation so that "no `ports:`" is a real assertion about that service
rather than a match somewhere in the file (`test/supermemory.sh#L51-L69`).
Aspects are grouped as `image`, `compose`, `context`, `state`, `hygiene`,
`launcher` and `contract`, and only `agent/AGENTS.md` is left un-stripped,
because there `#` is a markdown heading that the contract assertions check
(`test/supermemory.sh#L47-L49`, `test/supermemory.sh#L83`).

The launcher aspect additionally runs `shellcheck --shell=sh` over `bin/pi` when
it is installed, and records a pass when it is not rather than failing — the
missing tool is reported, not hidden (`test/supermemory.sh#L363-L380`).

## Shared output and filtering

Both suites emit one `OK n - description` or `NOT OK n - description` line per
assertion, print a per-group verdict (`# pin: OK`, `# compose: FAILED`), and end
with a TAP plan line `1..N` plus a summary, exiting non-zero on any failure.

Both accept a substring filter, from an argument or their own environment
variable, and skip non-matching groups entirely — including the coverage check's
targets, so a filtered run reports a verdict only for the groups that ran. The
Makefile passes the same `filter=` variable to both, but under different names,
and there is a case asserting they do not cross: a filter arriving under the
other suite's name would silently run everything.

## What neither suite proves

Neither starts Docker, builds an image, or makes a request to the memory engine.
`test/supermemory.sh` says so itself: it "says nothing about whether the engine
actually works", and the suite that would need a boot, a first-boot API key and a
real round trip **is not written yet**. What is verified is the set of decisions,
not the running system.
