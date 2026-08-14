#!/usr/bin/env python3
"""Generate the bundled exercise catalog.

Merges three sources, in increasing precedence:
  1. derivation-rules.json  - slug-token keyword tables
  2. free-exercise-db       - instructions and muscle data where names match
  3. overrides.json         - hand-authored entries and corrections

Usage:
    python3 Tools/build-catalog.py [--fedb path/to/exercises.json]

Writes LiftingPlan/Catalog/Resources/exercises.json as
`{"version": CATALOG_VERSION, "exercises": [...]}` and prints a coverage
report. Deterministic: the same inputs always produce byte-identical output.
"""
from __future__ import annotations
import argparse, collections, difflib, json, re, sys, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLUGS = ROOT / "docs/reference/movekit-exercise-slugs.txt"
RULES = ROOT / "Tools/derivation-rules.json"
OVERRIDES = ROOT / "Tools/overrides.json"
OUT = ROOT / "LiftingPlan/Catalog/Resources/exercises.json"
FEDB_URL = ("https://raw.githubusercontent.com/yuhonas/"
            "free-exercise-db/main/dist/exercises.json")

# The catalog format version, written into the output alongside the exercise
# list. `ExerciseCatalog.bundled()` reads this into `ExerciseCatalog.version`
# and it gets stamped onto every `TrainingPlan` created from this catalog, so
# a later correction to exercise data (a reclassified muscle, a changed
# pattern) can be detected against plans/logged sets built under an older
# version instead of silently changing what they mean. Bump this constant in
# any change that alters catalog *data* (not the generator's mechanism), and
# say so in the commit message.
CATALOG_VERSION = 2

# free-exercise-db's `level` uses "expert" where our taxonomy uses "advanced".
FEDB_LEVEL_TO_DIFFICULTY = {
    "beginner": "beginner", "intermediate": "intermediate", "expert": "advanced",
}

# Ranks our own derivation against free-exercise-db's `level`. Mechanism, not
# data, so it lives here rather than in derivation-rules.json.
DIFFICULTY_RANK = {"beginner": 0, "intermediate": 1, "advanced": 2}


def normalize(text: str) -> str:
    """Lowercase, strip punctuation, and sort tokens for order-insensitive match."""
    text = text.lower().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(sorted(text.split()))


def longest_match(slug: str, table: dict[str, str]) -> str | None:
    """The value whose key matches slug on whole hyphen-separated tokens, or
    None.

    Slugs are token sequences ("plate-forward-lunge" -> ["plate", "forward",
    "lunge"]); so are keys ("hip-thrust" -> ["hip", "thrust"]). A key matches
    only when its full token sequence appears contiguously within slug's
    tokens at some position - not merely as a character run. That is what
    keeps "lat" out of "plate" (tokens ["plate", ...] never contain the
    token "lat") and "ring" out of "hamstring" (tokens ["hamstring", "curl"]
    never contain the token "ring"), while still letting "curl" match
    "barbell-curl" and "hip-thrust" match "barbell-hip-thrust" as intended.

    Preference among matching keys goes to more key tokens first (a
    multi-word key is more specific than a single-word one), then more key
    characters, then key text - so ties are broken the same way on every
    run regardless of dict iteration order.

    This does no stemming: "push-up" will not match "push-ups" and "row"
    will not match "rowing". That is deliberate - a stemmer that trims a
    trailing "s" or "ing" to catch plurals and gerunds would just as
    happily trim "press" down to "pres" or turn "run" into "running" via
    the wrong rule, and every such heuristic is another way to reopen the
    exact substring-accident bug this function exists to close. Slugs that
    are a plural or gerund of an existing key are instead listed as their
    own explicit key in derivation-rules.json (see the entries following
    "press": "vertical press" in the pattern table) - a handful of literal
    entries, checked against the real slug list, beats a general rule that
    would need re-auditing every time a new exercise is added.
    """
    tokens = slug.split("-")
    best = None  # (token_count, char_len, key, value)
    for key, value in table.items():
        key_tokens = key.split("-")
        span = len(key_tokens)
        if span > len(tokens):
            continue
        matched = any(
            tokens[i:i + span] == key_tokens
            for i in range(len(tokens) - span + 1)
        )
        if not matched:
            continue
        candidate = (span, len(key), key)
        if best is None or candidate > (best[0], best[1], best[2]):
            best = (span, len(key), key, value)
    return best[3] if best else None


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

    catalog, enriched, overridden, fedb_difficulty = [], 0, 0, 0
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
        # Default: secondary muscles are a property of the movement pattern.
        # free-exercise-db enrichment below overwrites this for matched
        # entries that actually carry secondary-muscle data; overrides.json
        # wins over both. Precedence order is unchanged.
        secondary: list[str] = list(rules.get("patternSecondaryMuscles", {}).get(pattern, []))
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
            if match.get("secondaryMuscles"):
                secondary = match["secondaryMuscles"]
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

        # Difficulty: derive from pattern > equipment > mechanic > default,
        # using entry's final (post-override) fields so a hand-authored
        # correction to pattern/equipment/mechanic is honored. free-exercise-db
        # is real human-authored data, but its `level` field is internally
        # inconsistent: "Barbell Squat" -> beginner while "Pushups" ->
        # beginner too, "Power Clean" -> intermediate while "Clean and Jerk"
        # -> expert for materially the same skill, "Barbell Deadlift" ->
        # intermediate while our own compound+barbell rule already says
        # intermediate. It is too noisy to let it lower a rating our own
        # derivation already established (it once dragged barbell-squat and
        # six other loaded barbell/trap-bar compounds down to "beginner").
        # So fedb may only RAISE difficulty above the derived value, never
        # lower it: we take the max rank of derived vs. fedb.
        if entry["pattern"] in rules["difficultyByPattern"]:
            derived_difficulty = rules["difficultyByPattern"][entry["pattern"]]
        elif entry["equipment"] in rules["difficultyByEquipment"]:
            derived_difficulty = rules["difficultyByEquipment"][entry["equipment"]]
        elif entry.get("mechanic") in rules["difficultyByMechanic"]:
            derived_difficulty = rules["difficultyByMechanic"][entry["mechanic"]]
        else:
            derived_difficulty = rules["defaultDifficulty"]

        fedb_difficulty_value = None
        if match is not None:
            fedb_difficulty_value = FEDB_LEVEL_TO_DIFFICULTY.get(match.get("level"))

        if (fedb_difficulty_value is not None
                and DIFFICULTY_RANK[fedb_difficulty_value] > DIFFICULTY_RANK[derived_difficulty]):
            entry["difficulty"] = fedb_difficulty_value
            fedb_difficulty += 1
        else:
            entry["difficulty"] = derived_difficulty

        entry["aliases"] = sorted({a for a in entry["aliases"] if a and a != words})
        catalog.append(entry)

    catalog.sort(key=lambda e: e["id"])
    output = {"version": CATALOG_VERSION, "exercises": catalog}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(output, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

    ids = [e["id"] for e in catalog]
    if len(set(ids)) != len(ids):
        print("FAIL: duplicate ids", file=sys.stderr)
        return 1

    print(f"wrote {len(catalog)} exercises to {OUT.relative_to(ROOT)}")
    print(f"  enriched from free-exercise-db: {enriched}")
    print(f"  hand-authored overrides:        {overridden}")
    print(f"  difficulty from free-exercise-db level: {fedb_difficulty}")
    difficulty_counts = collections.Counter(e["difficulty"] for e in catalog)
    print(f"  difficulty distribution: {dict(sorted(difficulty_counts.items()))}")
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
