#!/usr/bin/env bash
#
# wget.sh — interactive website mirror downloader for offline viewing.
# Version: 2.1.0
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
#   Wayback mode — a web.archive.org/web/<TS>/<url> snapshot is auto-detected and
#   handled differently: it rebuilds the ORIGINAL site from the archive (raw
#   `id_` bytes, toolbar stripped, links localised), with adaptive rate-limiting
#   and nearest-capture recovery of dead links. Needs python3; see the block below.
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

# --- Wayback Machine mode ---------------------------------------------------
# A web.archive.org/web/<TS>/<url> snapshot needs special handling: pages carry
# an injected toolbar and rewritten links, and assets sit at sibling timestamp
# paths. Instead of mirroring that mess, fetch each resource through Wayback's
# `id_` identity endpoint (raw original bytes, original links) and rebuild the
# site at <original-host>/... . Forum/session URLs are skipped so the crawl
# doesn't fall into an infinite session-id trap. web.archive.org is heavily
# rate-limited, so the fetch is throttled with exponential backoff. Needs python3.
if [[ "${url}" =~ ^https?://web\.archive\.org/web/[0-9]+ ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Wayback mode requires python3 — not found." >&2
        exit 1
    fi
    echo "Wayback Machine snapshot detected — rebuilding the original site (id_ mode)..."
    python3 - "${url}" <<'PYWB'
import os, re, sys, time, json, urllib.parse
import ssl
from urllib.request import urlopen, Request
from urllib.error import HTTPError, URLError

WB = re.compile(r'^https?://web\.archive\.org/web/(\d+)(?:[a-z]{2}_|id_)?/(.*)$', re.I)
m = WB.match(sys.argv[1])
if not m:
    sys.exit("not a Wayback Machine URL")
TS = m.group(1)
start = m.group(2)
if not start.startswith(("http://", "https://")):
    start = "http://" + start
ORIG_HOST = urllib.parse.urlparse(start).netloc.lower()
OUT = sys.argv[2] if len(sys.argv) > 2 else "."
PAGE_CAP = 800

ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

PAGE_EXT = re.compile(r'\.(html?|php|phtml|shtml|asp|aspx|jsp|cgi)$', re.I)
# URLs to never crawl: forum trees and the dynamic/session/auth links that make
# them an infinite crawler trap (session ids, register/login/profile actions),
# plus the usual WordPress cruft. Keeps the rebuild to real content.
SKIP = re.compile(
    r'/forum/|/wwwboard/|/phpbb|/viewtopic|/viewforum|/memberlist|/ucp\.php'
    r'|[?&](sid|s|PHPSESSID)=|[?&](mode|action|do|view)='
    r'|/wp-login\.php|/wp-admin/|/wp-json|xmlrpc\.php|[?&]replytocom=|[?&]p=\d+',
    re.I)
REF = re.compile(r'''(href|src|action|background)\s*=\s*(["'])(.*?)\2''', re.I)
CSSURL = re.compile(r'url\(\s*(["\']?)([^"\')]+)\1\s*\)', re.I)

def normalize(orig):
    """Canonicalise an original URL so trivial variants dedupe to one fetch:
    lowercase scheme/host, drop default port, empty path -> '/'."""
    u = urllib.parse.urlsplit(orig)
    host = u.hostname or ""
    if u.port and not ((u.scheme == "http" and u.port == 80) or (u.scheme == "https" and u.port == 443)):
        host += f":{u.port}"
    path = u.path or "/"
    return urllib.parse.urlunsplit((u.scheme.lower(), host, path, u.query, ""))

def id_url(orig, ts=None):
    return f"https://web.archive.org/web/{ts or TS}id_/{orig}"

def closest_ts(orig):
    """Nearest-in-time capture timestamp for a URL that 404s at our snapshot, or
    None. Uses the Wayback Availability API, routed through the throttled/retrying
    fetch (_get) so the lookup itself survives rate-limiting — otherwise a block
    masquerades as "no capture" and recovery silently fails under load. Recovers
    pages deleted before the snapshot but archived earlier."""
    api = f"https://archive.org/wayback/available?url={urllib.parse.quote(orig, safe='')}&timestamp={TS}"
    try:
        snap = json.loads(_get(api)[2]).get("archived_snapshots", {}).get("closest")
        if snap and snap.get("available") and str(snap.get("status", "200")).startswith("2"):
            return snap["timestamp"]
    except Exception:
        pass
    return None

def local_path(orig):
    """Map an original URL to a local file path under OUT/<host>/..."""
    u = urllib.parse.urlparse(orig)
    path = urllib.parse.unquote(u.path)
    if path == "" or path.endswith("/"):
        path += "index.html"
    rel = (u.netloc + "/" + path.lstrip("/"))
    if u.query:                                   # keep query-string pages distinct
        safe = re.sub(r'[^A-Za-z0-9._-]', "_", u.query)
        rel += "@" + safe + ("" if PAGE_EXT.search(path) else ".html")
    return os.path.normpath(os.path.join(OUT, rel))

def same_site(orig):
    return urllib.parse.urlparse(orig).netloc.lower() == ORIG_HOST

def to_original(ref, page_orig):
    """Resolve a page reference to an absolute original URL, or None to leave."""
    ref = ref.strip()
    if not ref or ref[0] in "#" or ref.lower().startswith(("javascript:", "mailto:", "tel:", "data:")):
        return None
    # unwrap any Wayback rewriting that slipped through (/web/TS<mod>/<origurl>)
    w = re.match(r'^(?:https?:)?//web\.archive\.org/web/\d+[a-z_]*/(.*)$', ref, re.I)
    if w:
        ref = w.group(1)
        if ref.lower().startswith("mailto:"):
            return None
    if not re.match(r'[a-z][a-z0-9+.-]*:', ref, re.I) and not ref.startswith("//"):
        return urllib.parse.urljoin(page_orig, ref)      # relative -> absolute
    if ref.startswith("//"):
        ref = "http:" + ref
    return normalize(ref) if ref.startswith(("http://", "https://")) else None

def relpath(target, from_file):
    r = os.path.relpath(target, os.path.dirname(from_file))
    return "/".join(urllib.parse.quote(s) for s in r.split("/"))

# Adaptive pacing. The id_ endpoint tolerates a short burst then refuses
# connections for ~30-60s. Every time a request has to survive a block we raise
# the steady delay, so the crawl converges on a rate that stops tripping the wall
# rather than paying a backoff every few files. Observed sustainable rate is
# ~8-10s between requests, so we start at 5s (converges in ~2 steps instead of
# ~6 from cold, skipping most ramp-up blocks). Backoff starts at 45s because a
# 20s wait was observed to almost always still fail — skip straight to what clears.
_delay = [5.0]          # adaptive base seconds between requests (mutable)
_last = [0.0]
DELAY_MAX = 15.0

def _get(url):
    """Throttled GET with adaptive backoff. Raises HTTPError(404/403) or URLError."""
    backoff = [45, 90, 120]
    blocked = False
    for attempt in range(len(backoff) + 1):
        wait = _delay[0] - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.time()
        try:
            with urlopen(Request(url, headers={"User-Agent": UA}), timeout=90, context=ctx) as r:
                out = (r.status, r.headers.get_content_type(), r.read())
            if blocked:                            # survived a block — slow down for good
                _delay[0] = min(_delay[0] * 1.4, DELAY_MAX)
            return out
        except HTTPError as e:
            if e.code in (404, 403):
                raise                              # real miss — don't retry
            reason = f"HTTP {e.code}"              # 429/503/etc — retry
        except (URLError, TimeoutError) as e:
            reason = getattr(e, "reason", e)       # connection refused/reset — retry
        blocked = True
        if attempt < len(backoff):
            b = backoff[attempt]
            print(f"    ...throttled ({reason}); backing off {b}s (pace now {_delay[0]:.1f}s)")
            time.sleep(b)
    raise URLError("retries exhausted")

_recovered = [0]

def fetch(orig):
    """Fetch via id_ at the snapshot timestamp; on a 404, fall back to the
    nearest-in-time capture so pages deleted before the snapshot are recovered."""
    try:
        return _get(id_url(orig))
    except HTTPError as e:
        if e.code != 404:
            raise
        alt = closest_ts(orig)
        if not alt or alt == TS:
            raise                                  # never captured — genuinely gone
        out = _get(id_url(orig, alt))              # fetch the nearest capture (may raise)
        _recovered[0] += 1
        print(f"       recovered {orig} from nearest capture {alt[:8]}")
        return out

def looks_like_page(orig):
    p = urllib.parse.urlparse(orig).path
    return p in ("", "/") or p.endswith("/") or bool(PAGE_EXT.search(p))

start = normalize(start)
ORIG_HOST = urllib.parse.urlparse(start).netloc.lower()
queue = [start]
seen = {start}
saved = failed = skipped = 0

while queue and (saved + failed) < PAGE_CAP:
    orig = queue.pop(0)
    lp = local_path(orig)
    # resume / re-run: skip assets already on disk. Pages are always re-fetched
    # so their links get re-discovered, letting an interrupted crawl continue.
    if not looks_like_page(orig) and os.path.isfile(lp) and os.path.getsize(lp) > 0:
        skipped += 1
        continue
    try:
        status, ctype, body = fetch(orig)
    except (HTTPError, URLError, TimeoutError) as e:
        failed += 1
        print(f"  MISS {getattr(e,'code','err')}  {orig}")
        continue
    os.makedirs(os.path.dirname(lp) or ".", exist_ok=True)
    is_html = ctype == "text/html" or (PAGE_EXT.search(urllib.parse.urlparse(orig).path or "") and b"<" in body[:512])
    if not is_html:
        with open(lp, "wb") as fh:
            fh.write(body)
        saved += 1
        continue
    html = body.decode("latin-1")

    def sub_ref(mm):
        attr, q, ref = mm.group(1), mm.group(2), mm.group(3)
        o = to_original(ref, orig)
        if o is None or not same_site(o):
            return mm.group(0)               # external / anchor / mailto — leave
        if SKIP.search(o):                    # forum/session/cruft — don't crawl,
            return f'{attr}={q}{o}{q}'        # point the link at the original URL
        t = local_path(o)
        if o not in seen:
            seen.add(o); queue.append(o)
        return f'{attr}={q}{relpath(t, lp)}{q}'
    html = REF.sub(sub_ref, html)

    def sub_css(mm):
        o = to_original(mm.group(2), orig)
        if o is None or not same_site(o) or SKIP.search(o):
            return mm.group(0)
        t = local_path(o)
        if o not in seen:
            seen.add(o); queue.append(o)
        return f'url({mm.group(1)}{relpath(t, lp)}{mm.group(1)})'
    html = CSSURL.sub(sub_css, html)

    with open(lp, "w", encoding="latin-1") as fh:
        fh.write(html)
    saved += 1
    print(f"  ok   {orig}")
    time.sleep(0.2)                     # be gentle to web.archive.org

print(f"\nWayback rebuild: {saved} saved ({_recovered[0]} recovered from nearby captures), "
      f"{skipped} already-on-disk, {failed} missing "
      f"(snapshot {TS}, host {ORIG_HOST}, final pace {_delay[0]:.1f}s) -> {os.path.join(OUT, ORIG_HOST)}/")
PYWB
    beep
    echo "Wayback reconstruction complete"
    exit 0
fi

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
