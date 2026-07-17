#!/usr/bin/env bash
#
# wget.sh — interactive website mirror downloader for offline viewing.
# Version: 2.0.0
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Retro-Jack
#
# USAGE
#   ./wget.sh          then answer the two prompts:
#     Enter the URL:                e.g. https://example.com/
#     Enter the output directory:   where to save it (tip: use a fresh per-site
#                                   dir, not "." — running several mirrors into
#                                   one folder lets the post-pass re-scan and
#                                   clobber the others).
#
# WHAT IT DOES  (two phases)
#   1. wget crawl — recursive --mirror of the site host only, with page
#      requisites and link conversion. WordPress cruft (login/admin/API/feeds,
#      ?p= duplicates, forum trees) is skipped via a reject regex.
#   2. Python post-pass — wget can't run JS or (here) span hosts, so it misses
#      lazy-loaded images (data-src/…) and CDN-hosted assets. This pass parses
#      the saved HTML/CSS, fetches every referenced asset from ANY host,
#      rewrites the refs to local relative paths, and injects a real src onto
#      lazy <img> tags. Result: a self-contained, offline-viewable copy.
#
# REQUIREMENTS
#   wget (with pcre + https support) and python3 (stdlib only). Without python3
#   the wget mirror still runs, but lazy/cross-host images may be missing.
#
# OUTPUT LAYOUT
#   <output_dir>/<host>/...            the site
#   <output_dir>/<cdn-host>/...        each cross-host asset host, wget-style
#   Open <output_dir>/<host>/index.html (or a specific page) in a browser.
#
# NOTES
#   - Cannot bypass bot protection (Cloudflare JS challenges, CAPTCHAs, logins).
#   - Only mirror sites you're permitted to copy.
#
set -u

clear

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
        http://localhost*|https://localhost*|http://127.0.0.1*|https://127.0.0.1*|file://*|[A-Za-z]:*|\\\\*)
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

# Site host — used by the post-pass below to resolve root-relative links and
# set a referer. wget crawls this host only (no --span-hosts): that keeps
# recursion from wandering onto other domains, and cross-host assets (CDN
# images/CSS/JS, which most sites now use) are back-filled afterwards by the
# lazy/asset pass, which fetches requisites from ANY host. This avoids the old
# trap where you had to know a site's CDN hostnames up front or get a bare page.
host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"

mkdir -p "${output_dir}"

echo
echo "About to download ${url} to ${output_dir}"
read -rp "Press Enter to continue (Ctrl-C to abort)... " _

cd "${output_dir}" || { echo "Error: cannot enter ${output_dir}" >&2; exit 1; }

# WordPress cruft to skip. Learned from mirroring a WP comic site, where
# these accounted for ~40% of fetched files (all dead ends offline):
#   - login / registration:  wp-login.php, /sign-in/, /sign-up/, redirect_to=
#   - admin + APIs:           wp-admin, wp-json, xmlrpc.php, oembed, api.w.org
#   - feeds & manifests:      /feed/, wlwmanifest, ?rsd
#   - duplicate permalinks:   ?p=NNN short-links (redirect to the real slug)
#   - comment/share noise:    replytocom=, share=, like_comment=
#   - forum trees:            forum, /community/ (wpForo on niklascomics)
wp_cruft='forum|/community/|wp-login\.php|/sign-in/|/sign-up/|wp-admin|wp-json|xmlrpc\.php|oembed|wlwmanifest|api\.w\.org|\?rsd|/feed/?$|(\?|&)(replytocom|share|like_comment|redirect_to)=|[?&]p=[0-9]+'

wget \
    --execute robots=off \
    --mirror \
    --recursive \
    --regex-type=pcre \
    --reject-regex "${wp_cruft}" \
    --convert-links \
    --adjust-extension \
    --page-requisites \
    --no-parent \
    --progress=bar \
    --no-check-certificate \
    --show-progress \
    --referer=https://www.google.com/ \
    --user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" \
    "${url}"

beep
echo "Download complete"

# ---------------------------------------------------------------------------
# Post-pass: lazy-loaded / cross-host assets.
#
# wget only discovers assets in src/href/srcset — it never runs JavaScript, so
# lazy-loaded images (data-src, data-lazy-src, data-thumbnail, … — the norm for
# WordPress galleries and sliders) are missed. It also skipped cross-host assets
# entirely, since we don't let it span hosts. This pass parses the saved
# HTML/CSS for every asset reference — lazy attrs, srcset, CSS url(), on ANY
# host — downloads what's missing into a per-host layout (like wget's), rewrites
# the references to local relative paths, and gives lazy <img> tags a real src
# so they display without JS. Asset requisites are safe to fetch cross-host;
# only the crawl is kept on-site, so no CDN hostnames need to be known up front.
#
# Needs python3 (stdlib only). If absent, the mirror is still usable but images
# and styling may be missing — install python3 and re-run this block to fix them.
if command -v python3 >/dev/null 2>&1; then
    echo "Fetching lazy-loaded / cross-host assets..."
    python3 - "${host}" <<'PYLAZY'
import os, re, sys, glob, urllib.parse
from concurrent.futures import ThreadPoolExecutor
import ssl
try:
    from urllib.request import urlopen, Request
    SSL_CTX = ssl.create_default_context()
    SSL_CTX.check_hostname = False
    SSL_CTX.verify_mode = ssl.CERT_NONE   # match wget --no-check-certificate
except Exception:
    urlopen = None

SITE_HOST = sys.argv[1]   # only for root-relative resolution + referer

EXT = r'(?:jpe?g|png|gif|webp|svg|avif|bmp|ico|mp4|webm|m4v|ogg|ogv|mp3|wav|m4a|pdf|css|js|woff2?|ttf|otf|eot)'
EXT_RE = re.compile(r'\.' + EXT + r'$', re.I)
PROTECT = re.compile(r'(<script\b.*?</script>)', re.I | re.S)
# src/poster/href/content plus ANY data-* attribute (lazy loaders and lightbox
# galleries use many vendor names). classify()'s asset-extension filter keeps
# non-URL data-* values (JSON blobs, numbers) untouched. Quotes may be ' or ".
ATTR = re.compile(r'\b(src|poster|href|content|data-[\w-]+)\s*=\s*(["\'])(.*?)\2', re.I)
SRCSET = re.compile(r'\b(srcset|data-srcset|data-lazy-srcset)\s*=\s*(["\'])(.*?)\2', re.I)
CSSURL = re.compile(r'url\(\s*([\'"]?)([^\'")]+)\1\s*\)', re.I)
IMG = re.compile(r'<img\b[^>]*>', re.I)

existing = {os.path.normpath(p) for p in glob.glob("**/*", recursive=True) if os.path.isfile(p)}

def classify(ref, filedir):
    """Return (local_target, download_url, rewritable) or None to skip."""
    ref = ref.strip()
    if not ref or ref[0] in "#?" or ref.startswith(("data:", "javascript:", "mailto:", "tel:")):
        return None
    base = ref.split("#", 1)[0]
    path_noq = urllib.parse.unquote(base.split("?", 1)[0])
    query = base.split("?", 1)[1] if "?" in base else ""
    if not EXT_RE.search(path_noq):          # assets only — never page links
        return None
    m = re.match(r'(https?:)?//([^/]+)(/.*)?$', ref, re.I)
    if m:                                     # absolute/protocol-relative — any host
        host = m.group(2).lower()             # assets are requisites; fetch cross-host
        p = urllib.parse.unquote((m.group(3) or "/").split("?")[0]).lstrip("/")
        target = os.path.normpath(os.path.join(host, p))
        rewritable = True
    elif path_noq.startswith("/"):            # root-relative -> site host
        target = os.path.normpath(os.path.join(SITE_HOST, path_noq.lstrip("/")))
        rewritable = True
    else:                                     # document-relative -> leave ref, maybe fetch
        target = os.path.normpath(os.path.join(filedir, path_noq))
        rewritable = False
    parts = target.split(os.sep)
    dl = "https://" + parts[0] + "/" + "/".join(urllib.parse.quote(x) for x in parts[1:])
    if query:
        dl += "?" + query
    return target, dl, rewritable

# Discover + download, looping until the asset set stabilises. Files fetched
# mid-run (e.g. cross-host CSS) can reference more assets (fonts, backgrounds),
# so we re-scan after each download round rather than enumerating just once.
def enumerate_files():
    h = [f for f in glob.glob("**/*", recursive=True) if os.path.isfile(f) and f.endswith((".html", ".htm"))]
    c = [f for f in glob.glob("**/*.css", recursive=True) if os.path.isfile(f)]
    return h, c

def scan(text, filedir, want, in_css=False):
    refs = []
    if in_css:
        refs += [g[1] for g in CSSURL.findall(text)]
    else:
        for i, seg in enumerate(PROTECT.split(text)):
            if i % 2:            # inside <script> — skip
                continue
            refs += [m.group(3) for m in ATTR.finditer(seg)]
            for m in SRCSET.finditer(seg):
                refs += [c.strip().split()[0] for c in m.group(3).split(",") if c.strip()]
            refs += [g[1] for g in CSSURL.findall(seg)]
    for r in refs:
        c = classify(r, filedir)
        if c and c[0] not in existing:
            want[c[0]] = c[1]

def collect_want():
    h, c = enumerate_files()
    want = {}
    for f in h:
        scan(open(f, encoding="utf-8", errors="replace").read(), os.path.dirname(f), want)
    for f in c:
        scan(open(f, encoding="utf-8", errors="replace").read(), os.path.dirname(f), want, in_css=True)
    return want

def fetch(item):
    target, url = item
    try:
        os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
        req = Request(url, headers={"User-Agent": "Mozilla/5.0", "Referer": "https://" + SITE_HOST + "/"})
        data = urlopen(req, timeout=60, context=SSL_CTX).read()
        if not data:
            return (target, False)
        open(target, "wb").write(data)
        return (target, True)
    except Exception:
        try:
            if os.path.exists(target) and os.path.getsize(target) == 0:
                os.remove(target)
        except Exception:
            pass
        return (target, False)

fetched = 0
if urlopen:
    for _ in range(12):                 # safety cap; normally 1-2 rounds
        want = collect_want()
        if not want:
            break
        got = 0
        with ThreadPoolExecutor(max_workers=10) as ex:
            for target, ok in ex.map(fetch, list(want.items())):
                if ok:
                    existing.add(os.path.normpath(target)); fetched += 1; got += 1
        if got == 0:                     # only unreachable/404 left — stop
            break

html_files, css_files = enumerate_files()

# pass 3: rewrite refs to local + inject src on lazy imgs
def relq(target, filedir):
    return "/".join(urllib.parse.quote(s) for s in os.path.relpath(target, filedir or ".").split("/"))

rewritten = injected = 0
def process_html(text, filedir):
    global rewritten, injected
    out = []
    for i, seg in enumerate(PROTECT.split(text)):
        if i % 2:
            out.append(seg); continue
        def a_repl(m):
            global rewritten
            q = m.group(2); c = classify(m.group(3), filedir)
            if c and c[2] and os.path.isfile(c[0]):
                rewritten += 1
                return f'{m.group(1)}={q}{relq(c[0], filedir)}{q}'
            return m.group(0)
        seg = ATTR.sub(a_repl, seg)
        def ss_repl(m):
            global rewritten
            q = m.group(2); outc = []
            for cand in m.group(3).split(","):
                parts = cand.strip().split()
                if not parts:
                    continue
                c = classify(parts[0], filedir)
                if c and c[2] and os.path.isfile(c[0]):
                    parts[0] = relq(c[0], filedir); rewritten += 1
                outc.append(" ".join(parts))
            return f'{m.group(1)}={q}{", ".join(outc)}{q}'
        seg = SRCSET.sub(ss_repl, seg)
        def img_inject(m):
            global injected
            tag = m.group(0)
            if re.search(r'(?<![-\w])src\s*=', tag, re.I):
                return tag
            dm = re.search(r'\bdata(?:-lazy)?-src\s*=\s*(["\'])(.*?)\1', tag, re.I)
            if not dm:
                return tag
            injected += 1
            inner = tag[:-1].rstrip()
            if inner.endswith("/"):
                inner = inner[:-1].rstrip()
            return f'{inner} src="{dm.group(2)}" />'
        seg = IMG.sub(img_inject, seg)
        out.append(seg)
    return "".join(out)

for f in html_files:
    s = open(f, encoding="utf-8", errors="replace").read()
    o = process_html(s, os.path.dirname(f))
    if o != s:
        open(f, "w", encoding="utf-8").write(o)
for f in css_files:
    fdir = os.path.dirname(f)
    s = open(f, encoding="utf-8", errors="replace").read()
    def css_repl(m):
        global rewritten
        c = classify(m.group(2), fdir)
        if c and c[2] and os.path.isfile(c[0]):
            rewritten += 1
            return f'url({m.group(1)}{relq(c[0], fdir)}{m.group(1)})'
        return m.group(0)
    o = CSSURL.sub(css_repl, s)
    if o != s:
        open(f, "w", encoding="utf-8").write(o)

print(f"  {fetched} assets fetched, {rewritten} refs localized, {injected} lazy <img> src injected")
PYLAZY
    beep
    echo "Lazy-asset pass complete"
else
    echo "python3 not found — skipping lazy-asset pass (lazy images may be blank)." >&2
fi
