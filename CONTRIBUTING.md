# Contributing

This is a small one-person tool, but bug reports, fixes, and sensible
improvements are welcome.

## Reporting problems

- **Something's broken** (a URL won't download, the guard rejects a valid site,
  an option misbehaves): open an issue with the bug-report template. The exact
  URL you entered, your OS and `wget --version`, and what happened make it
  reproducible.
- **Security concerns:** see [SECURITY.md](SECURITY.md) — please report
  privately.

## Ground rules for pull requests

Keep PRs small and focused. A few conventions:

1. **Every change gets a CHANGELOG bullet** under `## [Unreleased]` in
   [CHANGELOG.md](CHANGELOG.md).
2. **`wget.sh` must pass ShellCheck** — CI runs it on every push and pull
   request. Run `shellcheck wget.sh` locally before submitting.
3. Keep it POSIX-friendly `bash` and portable — no non-standard tools without a
   good reason.

## Licensing

By contributing you agree your contribution is licensed under the repo's terms:
the **GNU General Public License v3.0 or later** — see [LICENSE](LICENSE).
