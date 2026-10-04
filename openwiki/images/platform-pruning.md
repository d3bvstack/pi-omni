---
type: build-mechanism
title: Platform pruning
description: The build-time script that deletes node_modules entries the running platform cannot use — why a shrinkwrapped esbuild tree carries every platform, the os/cpu matching rule with negation, scope traversal, and the image size it recovers.
tags: [pruning, npm, esbuild, shrinkwrap, image-size, build-script]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-04T21:48:02.281Z
sources:
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-5475ce28059ef88d5b3fcf16
    resource: repo://scripts/prune-platform-packages.js
generated: { by: "pi", at: "2026-10-04T21:48:02.281Z" }
---

`scripts/prune-platform-packages.js` runs once, in the agent image's build stage,
and deletes the `node_modules` entries that cannot execute on the platform being
built. It exists because of one specific interaction between npm and esbuild.

## Why the tree is wrong in the first place

The Pi package ships an `npm-shrinkwrap.json`, and npm installs a shrinkwrap
verbatim rather than filtering optional dependencies by `os` and `cpu`. esbuild
declares one optional dependency per operating system and architecture, so all
twenty-six of them land in the installed tree — 285 MB of a 610 MB layer — and
exactly one is usable (`scripts/prune-platform-packages.js#L5-L8`).

Deleting the shrinkwrap would fix the size too. The script's header gives the
reason it does not: that would resolve every transitive dependency to a fresh `^`
range on each build, trading a reproducible pinned tree for a smaller one
(`scripts/prune-platform-packages.js#L9-L11`). So the tree stays exactly as
npm pinned it and is pruned afterwards **by the rule npm would have applied**.

## The matching rule

`fits(list, value)` reimplements npm's semantics for the `os` and `cpu` manifest
fields (`scripts/prune-platform-packages.js#L31-L44`):

- absent or `null` means no constraint, which every platform satisfies;
- an empty list also means no constraint;
- a scalar or array is flattened to strings;
- an entry may be negated with `!`, so `['!linux']` fits every platform except
  linux;
- otherwise the running `process.platform` or `process.arch` must appear in the
  list.

A package is removed when either `os` or `cpu` fails that test
(`scripts/prune-platform-packages.js#L61-L66`).

## What the script refuses to judge

Two conservative behaviours, both stated in the code:

- **An unparseable manifest is left alone.** `visit` catches a JSON parse failure
  and returns without touching the directory, because a manifest it cannot read
  is not a package it can judge (`scripts/prune-platform-packages.js#L59-L60`,
  `scripts/prune-platform-packages.js#L73-L76`).
- **Symlinks are never followed.** `sweep` skips any entry that is not a real
  directory and skips dot-prefixed names, so a symlinked package is not deleted
  through (`scripts/prune-platform-packages.js#L89-L113`).

`sweep` handles one `node_modules` level: a `@scope` directory is descended into
as a scope, not treated as a package itself, and its children are visited
(`scripts/prune-platform-packages.js#L104-L112`). Each visited package recurses
into its own `node_modules`, so the whole tree is covered.

## Accounting and interface

The size freed is computed by walking the directory before deleting it, summing
file sizes recursively (`scripts/prune-platform-packages.js#L46-L56`), and the
script prints one line per removed package plus a total
(`scripts/prune-platform-packages.js#L122`).

The interface is one optional argument, defaulting to the current directory, and
a missing directory is a non-zero exit rather than a silent no-op — so a wrong
argument fails the build instead of pruning nothing
(`scripts/prune-platform-packages.js#L13-L16`, `scripts/prune-platform-packages.js#L116-L119`).

## What it is worth

The README records the measured result of the whole mechanism — the shrinkwrapped
cross-platform binaries, the prune, and dropping the npm cache: 273 MB of
twenty-six platforms installed where one is usable, and a whole-image difference
between 1373 MB and 715 MB (`README.md#L96-L102`).
