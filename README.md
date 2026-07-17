# Wget Downloader Script

`wget.sh` — an interactive website mirror downloader built on [GNU Wget](https://www.gnu.org/software/wget/).
It prompts for a URL and an output directory, blocks local / loopback /
drive-letter / UNC targets, then mirrors the site: page requisites, link
conversion (so it browses offline), `robots=off`, adjusted extensions, kept
within the starting path, and WordPress cruft / forum URLs skipped.

After the crawl, a Python post-pass makes the copy genuinely self-contained: it
fetches assets Wget can't see on its own — lazy-loaded images (`data-src`, …)
and files served from other hosts (CDNs) — rewrites their references to local
paths, and gives lazy `<img>` tags a real `src` so pages render offline.

## Requirements

- `bash` 4+
- `wget` (GNU Wget, built with `pcre` + `https`) on the `PATH`
- `python3` (standard library only) for the asset post-pass. Without it the
  Wget mirror still runs, but lazy-loaded and CDN-hosted assets may be missing.

## Usage

```sh
chmod +x wget.sh
./wget.sh
```

Answer the two prompts — the URL, then the output directory (created if it
doesn't exist). It shows what it's about to do and waits for confirmation;
`Ctrl-C` aborts there. A terminal bell rings on a rejected entry and when the
download finishes.

## Wayback Machine mode

Paste a Wayback Machine snapshot URL —
`https://web.archive.org/web/<timestamp>/http://example.com/` — and the script
auto-switches to a dedicated mode that reconstructs the **original** site rather
than mirroring the archive's wrapper. It fetches each resource through Wayback's
`id_` identity endpoint (raw original bytes — no toolbar, original links) and
rebuilds the site at `<output_dir>/<original-host>/…` so it browses offline like
the real thing.

- **Adaptive rate-limiting.** `web.archive.org` hard-refuses bursts, so the fetch
  throttles itself, backs off on blocks, and settles into a sustainable pace.
  Expect it to be slow — that's the archive, not the script.
- **Dead-link recovery.** A page that 404s at the requested timestamp is
  refetched from its nearest capture in time (via the Availability API), so you
  recover content deleted before the snapshot. This trades strict point-in-time
  fidelity for completeness.
- **Resumable.** Re-running skips assets already downloaded, so an interrupted
  crawl continues where it left off.
- Forum / session-id URLs are skipped to avoid infinite crawler traps.

Requires `python3` (standard library only).

## Notes

- **Local targets are refused.** `localhost`, `127.0.0.1`, `file://`, Windows
  drive letters (`C:\…`) and UNC paths (`\\…`) are rejected before anything runs.
- **Mirror settings** live in the `wget` invocation about midway down the script,
  with the `wp_cruft` skip pattern just above it — edit there to change depth, the
  skip pattern, the user-agent, and so on. The Python asset post-pass runs after.
- **python3 is required for the post-pass.** If it's missing the script says so
  and still produces the Wget mirror; lazy / CDN-hosted assets may just be blank.

## License

Licensed under the **GNU General Public License v3.0 or later** — see
[LICENSE](LICENSE).
