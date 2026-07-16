#!/usr/bin/env bash
#
# wget.sh — interactive website mirror downloader.
#
# Prompts for a URL and an output directory, refuses local / loopback /
# drive-letter / UNC targets, then mirrors the site with wget: page requisites,
# link conversion, robots off, forum paths skipped.
#
set -u

# Terminal bell — audible cue on a bad entry and on completion.
beep() { printf '\a'; }

while true; do
    read -rp "Enter the URL: " url
    if [[ -z "${url}" ]]; then
        beep
        echo "Please provide both the URL and output directory."
        echo
        continue
    fi

    # Reject local addresses, loopback, drive letters and UNC paths.
    case "${url}" in
        http://localhost*|https://localhost*|http://127.0.0.1*|https://127.0.0.1*|file://*|[A-Za-z]:*|'\\'*)
            echo "Error: Local addresses, drives, and network paths are not allowed."
            beep
            continue
            ;;
    esac

    read -rp "Enter the output directory: " output_dir
    if [[ -z "${output_dir}" ]]; then
        beep
        echo "Please provide both the URL and output directory."
        echo
        continue
    fi

    break
done

mkdir -p "${output_dir}"

echo
echo "About to download ${url} to ${output_dir}"
read -rp "Press Enter to continue (Ctrl-C to abort)... " _

cd "${output_dir}" || { echo "Error: cannot enter ${output_dir}" >&2; exit 1; }

wget \
    --execute robots=off \
    --mirror \
    --recursive \
    --reject-regex '.*forum.*' \
    --convert-links \
    --adjust-extension \
    --page-requisites \
    --no-parent \
    --progress=bar \
    --no-check-certificate \
    --show-progress \
    --referer=http://google.com \
    --user-agent="Mozilla/5.0 Firefox/4.0.1" \
    "${url}"

beep
echo "Download complete"
