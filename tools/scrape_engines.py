#!/usr/bin/env python3
"""Regenerate priv/engines.json from the SearchApi documentation.

    python3 tools/scrape_engines.py

Downloads every page under searchapi.io/docs (cached in tools/.cache), parses
the "API Parameters" section of each, and writes the catalog compiled into
SearchApi.Engine. Run it when SearchApi adds engines or parameters, then
review the diff — this is a scraper, not an API, so it can break silently.
"""

import html as H
import json
import os
import pathlib
import re
import sys
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUT = ROOT / "priv" / "engines.json"
BASE = "https://www.searchapi.io"

# Set by the client itself, or global to every engine: not per-engine params.
GLOBAL = {"engine", "api_key", "zero_retention", "output", "json_restrictor"}

# Documented at /docs but not engines of the /search endpoint.
SKIP = {"account-api", "locations-api", "search-history-api", "search-analytics-api"}

# Parameters SearchApi's docs mark "Required" but whose own description says
# they are conditional -- either one of a pair, or required only for certain
# values of another parameter. Marking them required in the generated JSON
# Schema tells a model to invent a value it should be omitting, so they are
# demoted to optional. Their descriptions already spell out the condition.
CONDITIONAL = {
    ("airbnb", "q"),
    ("airbnb", "bounding_box"),
    ("ebay_product", "item_id"),
    ("ebay_product", "product_id"),
    ("ebay_search", "q"),
    ("google_flights", "outbound_date"),
    ("google_flights", "return_date"),
    ("google_maps_photos", "place_id"),
    ("google_maps_photos", "data_id"),
    ("google_maps_place", "place_id"),
    ("google_maps_place", "data_id"),
    ("google_maps_reviews", "place_id"),
    ("google_maps_reviews", "data_id"),
    ("google_product_page", "product_id"),
    ("google_product_page", "product_token"),
    ("google_trends", "q"),
}

INT_NAMES = {"page", "num", "limit", "offset", "start", "depth", "adults", "children",
             "infants", "max_results", "results_per_page", "page_size", "rooms",
             "nights", "quantity"}


def text(s):
    return re.sub(r"\s+", " ", H.unescape(re.sub(r"<[^>]+>", "", s))).strip()


def fetch(slug):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{slug}.html"
    if not path.exists():
        req = urllib.request.Request(f"{BASE}/docs/{slug}", headers={"User-Agent": "search_api_ex-scraper"})
        path.write_bytes(urllib.request.urlopen(req).read())
    return path.read_text()


def infer_type(name, doc):
    d = doc.lower()
    if name in INT_NAMES or re.search(r"\bnumber of\b|\binteger\b", d):
        return "integer"
    if re.search(r"\bboolean\b|\btrue\b.{0,12}\bfalse\b", d):
        return "boolean"
    return "string"


def parse(slug, page):
    engines = Counter(re.findall(r"engine=([a-z0-9_]+)", page))
    engines += Counter(re.findall(r'"engine":\s*"([a-z0-9_]+)"', page))
    if not engines or "api-parameters" not in page:
        return None
    engine = engines.most_common(1)[0][0]

    name = re.sub(r"\s*(API )?Documentation$|\s*Scraper API$|\s*API$", "",
                  text(re.search(r"<title>(.*?)</title>", page, re.S).group(1))).strip()
    dm = re.search(r'<meta name="description" content="(.*?)">', page, re.S)

    start, end = page.find('id="api-parameters"'), page.find('id="api-examples"')
    section = page[start:end if end > start else len(page)]

    params, seen, group = [], set(), "Parameters"
    pattern = r'<h3\s+id="api-parameters-[^"]*?"(.*?)</h3>|<li id="api-parameters-[^"]*?"[^>]*>(.*?)</li>'
    for m in re.finditer(pattern, section, re.S):
        if m.group(1) is not None:
            raw = m.group(1).split(">", 1)[1] if ">" in m.group(1) else m.group(1)
            group = text(re.sub(r"<svg.*?</svg>|<div.*?</div>", "", raw, flags=re.S)) or group
            continue
        block = m.group(2)
        cm = re.search(r"<code>([a-zA-Z0-9_\[\]]+)</code>", block)
        if not cm or cm.group(1) in seen or cm.group(1) in GLOBAL:
            continue
        pname = cm.group(1)
        rm = re.search(r'<dt class="sr-only">Required</dt>\s*<dd[^>]*>\s*(\w+)', block)
        dd = re.search(r'<dt class="sr-only">Description</dt>\s*<dd[^>]*>(.*)', block, re.S)
        doc = text(dd.group(1)) if dd else ""
        seen.add(pname)
        params.append({
            "name": pname,
            "required": bool(rm) and rm.group(1) == "Required" and (engine, pname) not in CONDITIONAL,
            "type": infer_type(pname, doc),
            "group": group,
            "doc": doc,
        })

    if not params:
        return None

    return engine, {
        "id": engine,
        "name": name,
        "description": H.unescape(dm.group(1)).strip() if dm else "",
        "docs_url": f"{BASE}/docs/{slug}",
        "params": params,
    }


def main():
    index = fetch("google")
    slugs = sorted({s for s in re.findall(r'href="/docs/([a-z0-9_/-]+)"', index)} - SKIP)
    print(f"{len(slugs)} documentation pages")

    with ThreadPoolExecutor(max_workers=8) as pool:
        pages = list(pool.map(fetch, slugs))

    catalog = {}
    for slug, page in zip(slugs, pages):
        parsed = parse(slug, page)
        if parsed:
            catalog[parsed[0]] = parsed[1]

    OUT.write_text(json.dumps(dict(sorted(catalog.items())), indent=1, ensure_ascii=False) + "\n")

    applied = {(e, p["name"]) for e, v in catalog.items() for p in v["params"]}
    stale = CONDITIONAL - applied
    if stale:
        print(f"WARNING: CONDITIONAL entries no longer in the docs: {sorted(stale)}", file=sys.stderr)

    print(f"wrote {OUT.relative_to(ROOT)}: {len(catalog)} engines, "
          f"{sum(len(v['params']) for v in catalog.values())} parameters")


if __name__ == "__main__":
    main()
