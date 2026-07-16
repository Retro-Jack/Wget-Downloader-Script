# Wget Downloader Script

Interactive website mirror downloader built on `wget` (`wget.sh`). It prompts
for a URL and an output directory, blocks local / loopback / drive-letter / UNC
targets, then mirrors the site — page requisites, link conversion, `robots=off`,
and forum paths skipped.

## Usage

```sh
chmod +x wget.sh
./wget.sh
```

Answer the two prompts (URL, then output directory). It confirms before
starting; `Ctrl-C` aborts at that point.
