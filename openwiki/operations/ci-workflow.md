---
type: workflow
title: CI workflow
description: The ci.yml workflow runs the hermetic Makefile test suite (`make test`) on pushes and PRs to main/master when Makefile changes, with no services or caching.
tags: [workflow, ci, testing, hermetic]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-05T20:24:28.661Z
sources:
  - id: openwiki-source-164e2da859b5277df81c7d94
    resource: repo://.github/workflows/ci.yml
generated: { by: "pi", at: "2026-10-05T20:24:28.661Z" }
---

`.github/workflows/ci.yml` is a minimal, hermetic CI check:

- Triggers only when `Makefile` changes (`paths: [Makefile]`), on both `push` and `pull_request` to `main` or `master`.
- Uses `actions/checkout@v4` with no caching, no services, and no extra steps.
- Runs `make test`, which is documented in the Makefile as a hermetic suite that stubs `docker` and `npm`, needs no daemon, no network, and never writes to the checkout.

If the export or the build fails, the failure surfaces on the exact change (the `Makefile` PR) rather than after deployment.
