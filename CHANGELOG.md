# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-16

### Added
- `wget.sh` — interactive website mirror downloader: prompts for a URL and an
  output directory, refuses local / loopback / drive-letter / UNC targets, then
  mirrors the site with `wget` (page requisites, link conversion, `robots=off`,
  adjusted extensions, no-parent, forum paths skipped). A bash port of the
  original Windows `wget.cmd` interactive flow.
- Repository housekeeping to match the standard used across the author's other
  projects: `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, a
  `.gitignore`, GitHub issue / pull-request templates, a Dependabot config, and
  a ShellCheck CI workflow.

### Removed
- `wget.cmd` — the Windows batch version; `wget.sh` is the script now.
