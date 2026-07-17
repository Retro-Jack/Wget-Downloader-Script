# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-07-17

### Added
- Wayback Machine mode. A `web.archive.org/web/<timestamp>/<url>` snapshot URL is
  auto-detected and reconstructs the **original** site instead of mirroring the
  archive's wrapper: each resource is fetched through Wayback's `id_` identity
  endpoint (raw original bytes — no toolbar, original links) and rebuilt at
  `<output_dir>/<original-host>/…`.
  - **Adaptive rate-limiting** — `web.archive.org` hard-refuses bursts, so the
    fetch throttles, backs off on blocks, and converges on a sustainable pace.
  - **Nearest-capture recovery** — a page that 404s at the requested timestamp is
    refetched from its closest capture in time (Availability API, routed through
    the same throttle so a block can't masquerade as "no capture"), recovering
    content deleted before the snapshot.
  - **Resumable** — re-running skips assets already on disk.
  - Forum / session-id URLs are skipped to avoid infinite crawler traps.

### Requires
- `python3` (standard library only) for Wayback mode, as for the asset post-pass.

## [2.0.0] - 2026-07-17

### Added
- Python asset post-pass (requires `python3`, standard library only): after the
  Wget crawl, parses the saved HTML/CSS and fetches assets Wget can't discover —
  lazy-loaded images (`data-src`, `data-lazy-src`, `data-thumbnail`, `srcset`,
  CSS `url()`) and cross-host / CDN assets — from any host, rewrites the
  references to local relative paths, and injects a real `src` on lazy `<img>`
  tags so pages render offline without JavaScript. Re-scans until the asset set
  stabilises (e.g. assets referenced inside freshly fetched CSS).
- `/community/` (wpForo) added to the skip pattern, and the WordPress cruft
  filter expanded: login / registration, `wp-admin`, `wp-json`, `xmlrpc.php`,
  oEmbed, `wlwmanifest`, RSD, feeds, `?p=` short-link duplicates, and
  comment / share query noise.
- Usage header documenting the two-phase flow, requirements, and output layout.

### Changed
- Modernised the Wget request headers — a current Firefox user-agent and an
  `https` Google referer — so fewer sites serve degraded content or block the
  crawl outright.
- The crawl now stays on the site host; cross-host assets are back-filled by the
  post-pass instead of via `--span-hosts`, so a site's CDN hostnames no longer
  need to be known up front.

### Requires
- `python3` (standard library only) for the asset post-pass. The Wget mirror
  still runs without it, but lazy / CDN-hosted assets may be missing.

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
