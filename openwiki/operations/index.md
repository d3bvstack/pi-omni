# Files

- [CI workflow](ci-workflow.md) - The ci.yml workflow runs the hermetic Makefile test suite (`make test`) on pushes and PRs to main/master when Makefile changes, with no services or caching.
- [OpenWiki Pages workflow](openwiki-pages.md) - The openwiki-pages.yml workflow renders the committed openwiki/ tree as a static site via openwiki visualize --export, uploads the artifact, and deploys to GitHub Pages only on pushes to main.
