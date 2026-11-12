#!/usr/bin/env python3
"""Baut den Song-Katalog (catalog/songs.json) aus dem Mutopia Project.

Mutopia (https://www.mutopiaproject.org) stellt ausschließlich gemeinfreie
oder Creative-Commons-lizenzierte Noten + MIDI-Dateien bereit.

Ablauf:
  1. Alle Klavierstücke aus der Mutopia-Suche lesen (Titel, Komponist, Lizenz, MIDI-URL)
  2. Jede MIDI-Datei laden (Cache) und mit `PianoFlow --parse` bewerten
     -> Schwierigkeit, Dauer, Takte, Taktart, unspielbare Griffe
  3. Nur Stücke behalten, die PianoFlow sauber lesen kann

Aufruf:  python3 tools/build_catalog.py [--limit N]
"""
import html
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".catalog-cache"
OUT = ROOT / "catalog" / "songs.json"
BIN = ROOT / ".build" / "debug" / "PianoFlow"
BASE = "https://www.mutopiaproject.org/cgibin/make-table.cgi?Instrument=Piano&startat={}"
UA = "PianoFlow-Katalog/1.0 (Lern-App, nicht-kommerziell)"


def get(url: str, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def clean(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def parse_page(page: str):
    out = []
    for block in page.split('<table class="table-bordered result-table">')[1:]:
        cells = re.findall(r"<td[^>]*>(.*?)</td>", block, re.S)
        mid = re.search(r'href="([^"]+\.mid)"', block)
        info = re.search(r'piece-info\.cgi\?id=(\d+)', block)
        if len(cells) < 10 or not mid:
            continue
        title, composer = clean(cells[0]), clean(cells[1])
        instrument, date, style = clean(cells[4]), clean(cells[5]), clean(cells[6])
        license_ = clean(cells[9])
        out.append({
            "id": int(info.group(1)) if info else None,
            "title": title,
            "composer": re.sub(r"^by\s+", "", composer),
            "instrument": re.sub(r"^for\s+", "", instrument),
            "date": date,
            "style": style,
            "license": license_,
            "midi": mid.group(1),
            "source": "Mutopia Project",
        })
    return out


def scrape(limit=None):
    pieces, start = [], 0
    while True:
        page = get(BASE.format(start))
        found = parse_page(page)
        if not found:
            break
        pieces += found
        print(f"  Seite {start // 10 + 1}: {len(pieces)} Stücke", flush=True)
        if limit and len(pieces) >= limit * 3:
            break
        start += 10
        time.sleep(0.4)
    return pieces


def analyze(piece):
    CACHE.mkdir(exist_ok=True)
    fn = CACHE / (re.sub(r"[^A-Za-z0-9_.-]", "_", piece["midi"].split("/ftp/")[-1]))
    if not fn.exists():
        fn.write_bytes(get(piece["midi"], binary=True))
        time.sleep(0.25)
    r = subprocess.run([str(BIN), "--parse", str(fn)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        return {"error": (r.stderr or r.stdout).strip()[-200:] or f"exit {r.returncode}"}
    bad = re.search(r"Haende: (\d+) unspielbare Griffe in (\d+) Anschlaegen, Score ([\d.]+)", r.stdout)
    ok = re.search(r"OK .*?: (\d+) Noten \(R (\d+) / L (\d+)\), ([\d.]+) s, (\d+/\d+), (\d+) BPM, (\d+) Takte, Schwierigkeit (\d)", r.stdout)
    if not ok:
        return {"error": r.stdout.strip()[-200:]}
    n, rr, ll, dur, ts, bpm, bars, diff = ok.groups()
    return {
        "notes": int(n), "right": int(rr), "left": int(ll), "seconds": float(dur),
        "timeSignature": ts, "bpm": int(bpm), "bars": int(bars), "difficulty": int(diff),
        "unplayable": int(bad.group(1)) if bad else 0,
        "onsets": int(bad.group(2)) if bad else 0,
        "score": float(bad.group(3)) if bad else 0,
    }


def main():
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None
    print("1) Mutopia-Klavierstücke lesen …")
    listing = CACHE / "pieces.json"
    if "--offline" in sys.argv and listing.exists():
        pieces = json.loads(listing.read_text())
    else:
        pieces = scrape(limit)
        CACHE.mkdir(exist_ok=True)
        listing.write_text(json.dumps(pieces, ensure_ascii=False))
    solo = [p for p in pieces if p["instrument"].lower() in ("piano", "piano solo", "pianoforte", "harpsichord, piano", "piano or harpsichord")]
    if limit:
        solo = solo[:limit]
    print(f"   {len(pieces)} gefunden, {len(solo)} reine Klavierstücke")
    print("2) MIDI laden und mit PianoFlow prüfen …")
    good, errors = [], []
    for k, p in enumerate(solo, 1):
        try:
            a = analyze(p)
        except Exception as e:  # Netzwerk, Timeout …
            a = {"error": str(e)[:200]}
        if "error" in a:
            errors.append({"title": p["title"], "midi": p["midi"], "error": a["error"]})
        elif a["onsets"] and a["unplayable"] / a["onsets"] > 0.10:
            errors.append({"title": p["title"], "midi": p["midi"], "error": "vermutlich vierhändig/Ensemble (zu viele unspielbare Griffe)"})
        elif a["notes"] >= 20 and a["seconds"] >= 10:
            good.append({**p, **a})
        if k % 25 == 0:
            print(f"   {k}/{len(solo)} geprüft, {len(good)} ok, {len(errors)} Fehler", flush=True)
    good.sort(key=lambda s: (s["difficulty"], s["seconds"]))
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps({"generated": time.strftime("%Y-%m-%d"), "songs": good}, ensure_ascii=False, indent=1))
    (OUT.parent / "errors.json").write_text(json.dumps(errors, ensure_ascii=False, indent=1))
    print(f"Fertig: {len(good)} Songs in {OUT}, {len(errors)} Fehler in catalog/errors.json")


if __name__ == "__main__":
    main()
