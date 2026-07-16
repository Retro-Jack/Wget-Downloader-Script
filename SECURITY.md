# Security Policy

## Scope

`wget.sh` is a small local shell script with no server, no network service, and
no stored data. It runs GNU Wget against a URL you type in. The realistic
surface is:

- the URL-safety guard that refuses local / loopback / drive-letter / UNC
  targets before `wget` runs — a way to bypass it would be a genuine issue;
- shell-injection or argument-handling flaws in the script itself.

The site you point it at, and GNU Wget's own behaviour, are out of scope here.

## Supported versions

Only the latest release is maintained. Older tags are not patched.

## Reporting a vulnerability

Please report privately rather than opening a public issue:

- **Preferred:** GitHub's private vulnerability reporting — the
  **Report a vulnerability** button on the repository's **Security → Advisories**
  page (<https://github.com/Retro-Jack/Wget-Downloader-Script/security/advisories>).
- **Email:** retrojack68@gmail.com

Include what you found, where, and how to reproduce it. This is a one-person
hobby project, so responses are best-effort — but genuine reports will be looked
at, and credited if you'd like.
