# Wget Downloader Script

`wget.sh` — an interactive website mirror downloader built on [GNU Wget](https://www.gnu.org/software/wget/).
It prompts for a URL and an output directory, blocks local / loopback /
drive-letter / UNC targets, then mirrors the site: page requisites, link
conversion (so it browses offline), `robots=off`, adjusted extensions, kept
within the starting path, and forum URLs skipped.

## Requirements

- `bash` 4+
- `wget` (GNU Wget) on the `PATH`

## Usage

```sh
chmod +x wget.sh
./wget.sh
```

Answer the two prompts — the URL, then the output directory (created if it
doesn't exist). It shows what it's about to do and waits for confirmation;
`Ctrl-C` aborts there. A terminal bell rings on a rejected entry and when the
download finishes.

## Notes

- **Local targets are refused.** `localhost`, `127.0.0.1`, `file://`, Windows
  drive letters (`C:\…`) and UNC paths (`\\…`) are rejected before anything runs.
- **Mirror settings** live in one `wget` invocation near the foot of the script —
  edit there to change depth, the forum-skip pattern, the user-agent, and so on.

## License

Licensed under the **GNU General Public License v3.0 or later** — see
[LICENSE](LICENSE).
