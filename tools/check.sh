#!/usr/bin/env bash
# Dev-time checks for remedcu.com (no build step; this only verifies).
# Run from anywhere:  bash tools/check.sh
# Exit code 1 on any failure. Needs bash, python3, git; html-validate via npx if node is present.
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; fail=1; }
# Loops read from process substitution, never from a pipe: a piped "while"
# runs in a subshell and its fail=1 would be lost.

pages=(index.html work/index.html audits/index.html talks/index.html 404.html)
public=("${pages[@]}" README.md robots.txt sitemap.xml .well-known/security.txt)

# 1. Budgets: HTML <= 30 KB, CSS <= 15 KB, JS <= 3 KB.
for f in "${pages[@]}"; do
  s=$(wc -c < "$f"); [ "$s" -le 30720 ] || bad "$f is $s bytes (> 30 KB)"
done
s=$(wc -c < css/site.css); [ "$s" -le 15360 ] || bad "css/site.css is $s bytes (> 15 KB)"
s=$(wc -c < js/theme.js); [ "$s" -le 3072 ] || bad "js/theme.js is $s bytes (> 3 KB)"

# 2. Scripts: theme.js once per page, JSON-LD on the home page only, nothing else.
for f in "${pages[@]}"; do
  n=$(grep -o '<script' "$f" | wc -l)
  t=$(grep -o '<script src="/js/theme.js"></script>' "$f" | wc -l)
  j=$(grep -o '<script type="application/ld+json">' "$f" | wc -l)
  [ "$t" -eq 1 ] || bad "$f must load /js/theme.js exactly once"
  [ "$n" -eq $((t + j)) ] || bad "$f has an unexpected <script> element"
  if [ "$f" = index.html ]; then [ "$j" -eq 1 ] || bad "index.html needs its JSON-LD block"
  else [ "$j" -eq 0 ] || bad "$f: JSON-LD belongs on the home page only"; fi
done

# 3. CSP is self-only: no style attributes, <style> blocks or inline event handlers.
while IFS= read -r m; do bad "inline style or handler: $m"; done \
  < <(grep -nHE '<style|style="|[[:space:]]on[a-z]+="' "${pages[@]}")

# 4. No third-party resources, in HTML or CSS.
while IFS= read -r m; do bad "external resource: $m"; done \
  < <(grep -oHE '<(link|script|img|iframe|source|video|audio|embed|object)[^>]+(src|href|data)="(https?:)?//[^"]+"' "${pages[@]}" | grep -v 'rel="canonical"')
grep -nE '@import|url\(' css/site.css >/dev/null && bad "css/site.css uses @import or url(); the site loads no CSS resources"

# 5. Shared header and footer, internal links, theme colors (python).
python3 - <<'PY' || fail=1
import re, sys, os
ok = True
def fail(msg):
    global ok; print("FAIL: " + msg); ok = False
pages = {"index.html": "/", "work/index.html": "/work/", "audits/index.html": "/audits/",
         "talks/index.html": "/talks/", "404.html": None}
text = {p: open(p, encoding="utf-8").read() for p in pages}
ref = {}
for p, current in pages.items():
    for name in ("header", "footer"):
        m = re.search(rf"<!-- shared:{name} -->(.*?)<!-- /shared:{name} -->", text[p], re.S)
        if not m:
            fail(f"{p} has no shared:{name} block"); continue
        b = m.group(1)
        marks = re.findall(r'href="([^"]+)" aria-current="page"', b)
        want = [current] if (current and name == "header") else []
        if marks != want: fail(f"{p}: aria-current on {marks}, expected {want}")
        b = b.replace(' aria-current="page"', "")
        if ref.setdefault(name, b) != b: fail(f"shared {name} differs in {p}")
# Internal links and fragments resolve to files and ids in the repo.
def target(path):
    path = path.lstrip("/")
    return os.path.join(path, "index.html") if path == "" or path.endswith("/") else path
for p, t in text.items():
    for href in re.findall(r'href="(/[^"]*)"', t):
        path, _, frag = href.partition("#")
        f = target(path)
        if not os.path.isfile(f): fail(f"{p}: link {href} has no file {f}"); continue
        if frag and f.endswith(".html") and f'id="{frag}"' not in open(f, encoding="utf-8").read():
            fail(f"{p}: link {href} has no id {frag}")
# README (GitHub profile) must not embed images that are not in the repo.
for src in re.findall(r'\]\((\./[^)\s]+)\)|src="(\./[^"]+)"', open("README.md", encoding="utf-8").read()):
    s = src[0] or src[1]
    if not os.path.isfile(s): fail(f"README.md embeds {s}, which is not in the repo")
# theme.js and the theme-color meta use the same colors as --bg.
css, js = open("css/site.css").read(), open("js/theme.js").read().lower()
dark = re.search(r":root\s*\{[^}]*?--bg:\s*(#[0-9a-f]+)", css).group(1).lower()
light = re.search(r'\[data-theme="light"\]\s*\{[^}]*?--bg:\s*(#[0-9a-f]+)', css).group(1).lower()
for c in (dark, light):
    if c not in js: fail(f"js/theme.js does not use --bg {c}")
for p, t in text.items():
    if f'<meta name="theme-color" content="{dark}">' not in t.lower(): fail(f"{p}: theme-color meta is not {dark}")
    elif t.find('name="theme-color"') > t.find('src="/js/theme.js"'): fail(f"{p}: theme-color meta must come before theme.js")
sys.exit(0 if ok else 1)
PY

# 6. Nothing private or stray is tracked.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do bad "tracked file must not be committed: $f"; done \
    < <(git ls-files | grep -E '(^|/)\.DS_Store$|^_inputs/')
fi

# 7. Copy rules. Em dashes never appear in public text. Job-search phrases are
#    checked inline; internal names live in the git-ignored _inputs/denylist.txt
#    (one extended regex per line, no blank lines) so the list itself is never published.
while IFS= read -r m; do bad "em dash in public text: $m"; done \
  < <(LC_ALL=C grep -nH $'\xe2\x80\x94' "${public[@]}")
grep -niE "open to work|looking for a|currently exploring" "${public[@]}" && bad "job-search phrase found (above)"
if [ -f _inputs/denylist.txt ]; then
  grep -niEf _inputs/denylist.txt "${public[@]}" && bad "private denylist term found (above)"
else
  say "note: _inputs/denylist.txt not found, private denylist skipped"
fi

# 8. Dates: footer "Updated <Month> <Year>" matches the newest sitemap lastmod,
#    no lastmod in the future, security.txt Expires between today and a year out.
python3 - <<'PY' || fail=1
import re, sys, datetime as dt
ok = True
today = dt.date.today()
mods = [dt.date.fromisoformat(d) for d in re.findall(r"<lastmod>([\d-]+)</lastmod>", open("sitemap.xml").read())]
newest = max(mods)
if newest > today: print(f"FAIL: sitemap lastmod {newest} is in the future"); ok = False
foot = re.search(r"Updated ([A-Z][a-z]+ \d{4})", open("index.html", encoding="utf-8").read())
want = newest.strftime("%B %Y")
if not foot or foot.group(1) != want:
    print(f"FAIL: footer says {foot.group(1) if foot else 'nothing'}, newest sitemap lastmod is {newest} ({want})"); ok = False
m = re.search(r"^Expires: (\S+)$", open(".well-known/security.txt").read(), re.M)
days = (dt.date.fromisoformat(m.group(1)[:10]) - today).days if m else -1
if not 0 < days <= 366:
    print(f"FAIL: security.txt Expires is {days} days away (RFC 9116: in the future, under a year)"); ok = False
elif days < 45:
    print(f"note: security.txt expires in {days} days; move Expires forward")
sys.exit(0 if ok else 1)
PY

# 9. Markup validity (needs node; version pinned so results do not drift).
if command -v npx >/dev/null 2>&1; then
  npx --yes html-validate@11.16.2 "${pages[@]}" tools/og.html || bad "html-validate reported errors"
else
  say "note: node not found, skipped html-validate"
fi

[ "$fail" -eq 0 ] && say "all checks passed" || say "checks failed"
exit "$fail"
