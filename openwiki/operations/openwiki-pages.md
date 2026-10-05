---
type: workflow
title: OpenWiki Pages workflow
description: The openwiki-pages.yml workflow renders the committed openwiki/ tree as a static site via openwiki visualize --export, uploads the artifact, and deploys to GitHub Pages only on pushes to main.
tags: [workflow, openwiki, github-pages, static-export]
verified:
  - by: openwiki/0.7.0
    at: 2026-10-05T20:23:24.626Z
sources:
  - id: openwiki-source-33403bcef8aaabc7af1eb005
    resource: repo://.github/workflows/openwiki-pages.yml
generated: { by: "pi", at: "2026-10-05T20:23:24.626Z" }
---

`.github/workflows/openwiki-pages.yml` runs on pushes to `main` or `master` that touch `openwiki/**`, on pull requests with the same paths, and via `workflow_dispatch`. It never deploys on PR.

The `build` job:

- Checks out the repository at pinned action versions.
- Installs `openwiki@0.7.0` globally (matching the vendored agent/npm version).
- Runs `openwiki visualize openwiki --export site` to produce a static reader, graph (`graph.json`), and client (`client.js`). All references are relative so the site works from a project Pages URL (`/<repo>/`).
- Verifies the export is non-empty (`site/index.html`, `site/graph.json`, `site/client.js` are all non-zero size) and writes `site/.nojekyll` to prevent Jekyll from dropping special paths.
- Uploads `site/` as a pages artifact with hidden files included.

The `deploy` job (`if: github.event_name != 'pull_request'`) deploys the artifact to GitHub Pages using `actions/deploy-pages` in the `github-pages` environment.

```yaml
permissions:
  contents: read
  pages: write
  id-token: write
```
