#!/usr/bin/env bash
#
# tests/check-site.sh - validate the static site in site/.
# Checks that href/src links and assets in the HTML resolve to a file, and
# that each page is parseable by Python's HTMLParser. Does NOT check HTML
# well-formedness, nor assets referenced via CSS url(), @import, or srcset.
# External URLs, anchors, and mailto: links are skipped.
# Runs in CI on PRs that touch site/, and is runnable locally.
#
set -u

SOURCE="${BASH_SOURCE[0]}"
DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SITE="$(cd -P "$DIR/.." && pwd)/site"

if [ ! -d "$SITE" ]; then
  echo "No site/ directory at $SITE"
  exit 1
fi

python3 - "$SITE" <<'PY'
import sys, os
from html.parser import HTMLParser
from urllib.parse import urlparse

site = sys.argv[1]
site_root = os.path.realpath(site)
problems = []

class Collector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        for key in ("href", "src"):
            if d.get(key):
                self.refs.append(d[key])

html_files = sorted(f for f in os.listdir(site) if f.endswith(".html"))
if not html_files:
    problems.append("no HTML files found in site/")

for name in html_files:
    c = Collector()
    try:
        with open(os.path.join(site, name), encoding="utf-8") as f:
            text = f.read()
        c.feed(text)
    except Exception as e:
        problems.append("%s: HTML read/parse error: %s" % (name, e))
        continue
    for ref in c.refs:
        u = urlparse(ref)
        if u.scheme or u.netloc:                 # external URL
            continue
        if ref.startswith("#") or ref.startswith("mailto:"):
            continue
        target = ref.split("#")[0].split("?")[0]
        if not target:
            continue
        resolved = os.path.join(site, target.lstrip("/")) if target.startswith("/") \
            else os.path.join(site, target)
        real = os.path.realpath(resolved)
        if real != site_root and not real.startswith(site_root + os.sep):
            problems.append("%s: link escapes site/ -> %s" % (name, ref))
        elif not os.path.exists(real):
            problems.append("%s: broken link/asset -> %s" % (name, ref))

if problems:
    print("Site validation FAILED:")
    for p in problems:
        print("  - " + p)
    sys.exit(1)

print("Site validation OK: %d page(s), all href/src links resolve." % len(html_files))
PY
