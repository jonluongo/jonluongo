#!/usr/bin/env python3
"""Generate the bundled exercise catalog.

Merges three sources, in increasing precedence:
  1. derivation-rules.json  - slug-token keyword tables
  2. free-exercise-db       - instructions and muscle data where names match
  3. overrides.json         - hand-authored entries and corrections

Usage:
    python3 Tools/build-catalog.py [--fedb path/to/exercises.json]

Writes LiftingPlan/Catalog/Resources/exercises.json and prints a coverage
report. Deterministic: the same inputs always produce byte-identical output.
"""
from __future__ import annotations
import argparse, difflib, json, re, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLUGS = ROOT / "docs/reference/movekit-exercise-slugs.txt"
RULES = ROOT / "Tools/derivation-rules.json"
OVERRIDES = ROOT / "Tools/overrides.json"
OUT = ROOT / "LiftingPlan/Catalog/Resources/exercises.json"
FEDB_URL = ("https://raw.githubusercontent.com/yuhonas/"
            "free-exercise-db/main/dist/exercises.json")


def normalize(text: str) -> str:
    """Lowercase, strip punctuation, and sort tokens for order-insensitive match."""
    text = text.lower().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(sorted(text.split()))


def longest_match(slug: str, table: dict[str, str]) -> str | None:
    """The value whose key is the longest substring of slug, or None."""
    best = None
    for key, value in table.items():
        if key in slug and (best is None or len(key) > len(best[0])):
            best = (key, value)
    return best[1] if best else None


def title_case(slug: str) -> str:
    small = {"a", "an", "and", "at", "for", "in", "of", "on", "or", "the", "to", "with"}
    words = slug.split("-")
    out = []
    for i, w in enumerate(words):
        out.append(w if (w in small and i > 0) else w.capitalize())
    return " ".join(out)


def load_fedb(path: str | None) -> list[dict]:
    if path:
        return json.loads(Path(path).read_text())
    with urllib.request.urlopen(FEDB_URL, timeout=90) as response:
        return json.loads(response.read())


def build() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fedb", help="local free-exercise-db exercises.json")
    args = parser.parse_args()

    slugs = [s.strip() for s in SLUGS.read_text().splitlines() if s.strip()]
    rules = json.loads(RULES.read_text())
    overrides = json.loads(OVERRIDES.read_text())
    fedb_index: dict[str, dict] = {}
    for entry in load_fedb(args.fedb):
        fedb_index.setdefault(normalize(entry["name"]), entry)

    catalog, enriched, overridden = [], 0, 0
    pattern_fallthrough, equipment_fallthrough = [], []

    for slug in slugs:
        words = slug.replace("-", " ")

        pattern_match = longest_match(slug, rules["pattern"])
        pattern = pattern_match or rules["defaultPattern"]
        if pattern_match is None:
            pattern_fallthrough.append(slug)

        equipment_match = longest_match(slug, rules["equipment"])
        equipment = equipment_match or rules["defaultEquipment"]
        if equipment_match is None:
            equipment_fallthrough.append(slug)
        primary = list(rules["patternMuscles"].get(pattern, []))
        hinted = longest_match(slug, rules["muscleHints"])
        if hinted:
            primary = list(hinted)
        force = rules["patternForce"].get(pattern)
        mechanic = "compound" if pattern in rules["compoundPatterns"] else "isolation"
        category = rules["patternCategory"].get(pattern, rules["defaultCategory"])
        secondary: list[str] = []
        instructions: list[str] = []
        aliases: list[str] = []

        # Source 2: free-exercise-db enrichment.
        key = normalize(words)
        match = fedb_index.get(key)
        if match is None:
            close = difflib.get_close_matches(key, fedb_index.keys(), n=1, cutoff=0.93)
            match = fedb_index[close[0]] if close else None
        if match is not None:
            enriched += 1
            instructions = match.get("instructions") or []
            if match.get("primaryMuscles"):
                primary = match["primaryMuscles"]
            secondary = match.get("secondaryMuscles") or []
            if match.get("mechanic"):
                mechanic = match["mechanic"]
            if match.get("force"):
                force = match["force"]
            if match["name"].lower() != words:
                aliases.append(match["name"].lower())

        entry = {
            "id": slug,
            "displayName": title_case(slug),
            "aliases": aliases,
            "primaryMuscles": primary or ["abdominals"],
            "secondaryMuscles": [m for m in secondary if m not in primary],
            "equipment": equipment,
            "pattern": pattern,
            "category": category,
            "mechanic": mechanic,
            "instructions": instructions,
        }
        if force:
            entry["force"] = force

        # Source 3: overrides win.
        if slug in overrides:
            overridden += 1
            entry.update(overrides[slug])
            # An override may replace primaryMuscles after secondaryMuscles was
            # already deduped against the pre-override list, so re-dedup here
            # or a muscle can end up listed as both primary and secondary.
            entry["secondaryMuscles"] = [
                m for m in entry["secondaryMuscles"] if m not in entry["primaryMuscles"]
            ]

        entry["aliases"] = sorted({a for a in entry["aliases"] if a and a != words})
        catalog.append(entry)

    catalog.sort(key=lambda e: e["id"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

    ids = [e["id"] for e in catalog]
    if len(set(ids)) != len(ids):
        print("FAIL: duplicate ids", file=sys.stderr)
        return 1

    print(f"wrote {len(catalog)} exercises to {OUT.relative_to(ROOT)}")
    print(f"  enriched from free-exercise-db: {enriched}")
    print(f"  hand-authored overrides:        {overridden}")
    print(f"  fell through to defaultPattern ({rules['defaultPattern']!r}): "
          f"{len(pattern_fallthrough)}")
    if pattern_fallthrough:
        print(f"    {', '.join(sorted(pattern_fallthrough))}")
    print(f"  fell through to defaultEquipment ({rules['defaultEquipment']!r}): "
          f"{len(equipment_fallthrough)}")
    if equipment_fallthrough:
        print(f"    {', '.join(sorted(equipment_fallthrough))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(build())
