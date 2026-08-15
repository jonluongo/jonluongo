#!/usr/bin/env python3
"""Generate the bundled exercise catalog.

Merges three sources, in increasing precedence:
  1. derivation-rules.json  - slug-token keyword tables
  2. free-exercise-db       - instructions and muscle data where names match
  3. overrides.json         - hand-authored entries and corrections

Usage:
    python3 Tools/build-catalog.py [--fedb path/to/exercises.json]

Writes LiftingKit/Sources/LiftingKit/Catalog/Resources/exercises.json as
`{"version": CATALOG_VERSION, "exercises": [...]}` and prints a coverage
report.

Hermetic and deterministic: every input is a file in this repository, so the
same checkout always produces byte-identical output. No network access, at
build time or any other time. All three sources are versioned here — including
free-exercise-db, which is vendored at `Tools/vendor/` rather than fetched,
for the reason recorded on FEDB_SNAPSHOT below.
"""
from __future__ import annotations
import argparse, collections, difflib, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLUGS = ROOT / "docs/reference/movekit-exercise-slugs.txt"
RULES = ROOT / "Tools/derivation-rules.json"
OVERRIDES = ROOT / "Tools/overrides.json"
OUT = ROOT / "LiftingKit/Sources/LiftingKit/Catalog/Resources/exercises.json"

# free-exercise-db, vendored rather than fetched.
#
# This file supplies primaryMuscles, secondaryMuscles, mechanic, force,
# instructions, and (via FEDB_LEVEL_TO_DIFFICULTY) difficulty to the entries
# whose names it matches — a large share of the shipped catalog. It used to be
# read live from that repository's `main` branch, which meant an edit by a
# third party silently changed our catalog data on the next regeneration
# without touching a single file here and without bumping CATALOG_VERSION. The
# version stamp on every TrainingPlan would then record a version whose
# contents had drifted, which is the exact confusion the stamp exists to
# prevent.
#
# Vendoring, rather than pinning a commit SHA in the URL, because a pinned URL
# still leaves the build dependent on the network and on someone else's
# hosting, and — more importantly — leaves the data itself invisible to review.
# Vendored, an upstream refresh is an ordinary commit: the reviewer sees the
# input diff, the regenerated catalog diff, and the CATALOG_VERSION bump
# together. The snapshot is ~1 MB of JSON against a ~3 MB repository, which is
# a cheap price for a hermetic, reviewable build.
#
# To refresh: download FEDB_UPSTREAM_URL, replace FEDB_SNAPSHOT, update
# FEDB_SHA256 and FEDB_UPSTREAM_COMMIT, bump CATALOG_VERSION, regenerate, and
# review the catalog diff entry by entry.
FEDB_SNAPSHOT = ROOT / "Tools/vendor/free-exercise-db-exercises.json"
FEDB_UPSTREAM_COMMIT = "5197c055b356498944328bd00178b64a5e9f422c"
FEDB_UPSTREAM_URL = ("https://raw.githubusercontent.com/yuhonas/free-exercise-db/"
                     f"{FEDB_UPSTREAM_COMMIT}/dist/exercises.json")
FEDB_SHA256 = "d68a817484964095e6af0be2cdcbcc2c2504168d1d190c7d5c725ce52f3ae1f4"

# The catalog format version, written into the output alongside the exercise
# list. `ExerciseCatalog.bundled()` reads this into `ExerciseCatalog.version`
# and it gets stamped onto every `TrainingPlan` created from this catalog, so
# a later correction to exercise data (a reclassified muscle, a changed
# pattern) can be detected against plans/logged sets built under an older
# version instead of silently changing what they mean. Bump this constant in
# any change that alters catalog *data* (not the generator's mechanism), and
# say so in the commit message.
#
# Because every input is now a file in this repository (see FEDB_SNAPSHOT),
# "catalog data changed" is always visible as a diff in this commit, so the
# instruction above is one a reviewer can actually enforce.
CATALOG_VERSION = 5

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


def load_json_strict(path: Path) -> dict:
    """Parse a rules/overrides file, rejecting duplicate keys.

    `json.load` silently keeps the last of two identical keys, so a second
    `"jump-rope"` block would discard the first — including any field the
    second block does not repeat — with no error anywhere. These files are
    hand-authored per-exercise facts, which is exactly where that happens.
    """
    def no_duplicates(pairs: list[tuple[str, object]]) -> dict:
        seen: dict[str, object] = {}
        for key, value in pairs:
            if key in seen:
                raise ValueError(f"{path.name}: duplicate key {key!r}")
            seen[key] = value
        return seen
    return json.loads(path.read_text(), object_pairs_hook=no_duplicates)


def title_case(slug: str) -> str:
    small = {"a", "an", "and", "at", "for", "in", "of", "on", "or", "the", "to", "with"}
    words = slug.split("-")
    out = []
    for i, w in enumerate(words):
        out.append(w if (w in small and i > 0) else w.capitalize())
    return " ".join(out)


def load_fedb(path: str | None) -> list[dict]:
    """The vendored free-exercise-db snapshot, verified against FEDB_SHA256.

    `path` overrides which file is read (used when re-vendoring), but the
    checksum is still enforced: an input that does not hash to the pinned
    value is a *different* dataset, and silently building the catalog from it
    is the failure mode this function exists to make impossible. Refreshing
    the data is a deliberate act that edits FEDB_SHA256 alongside the
    snapshot, not a side effect of running the generator.
    """
    source = Path(path) if path else FEDB_SNAPSHOT
    if not source.exists():
        raise FileNotFoundError(
            f"free-exercise-db snapshot missing: {source}\n"
            f"Restore it from {FEDB_UPSTREAM_URL}")
    payload = source.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != FEDB_SHA256:
        raise ValueError(
            f"free-exercise-db snapshot checksum mismatch for {source}\n"
            f"  expected {FEDB_SHA256}\n"
            f"  actual   {digest}\n"
            "The exercise data this build depends on is not the reviewed data. "
            "If you meant to refresh it, update FEDB_SHA256 and "
            "FEDB_UPSTREAM_COMMIT, bump CATALOG_VERSION, and review the "
            "regenerated catalog diff entry by entry.")
    return json.loads(payload)


def build() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fedb", help="local free-exercise-db exercises.json")
    args = parser.parse_args()

    slugs = [s.strip() for s in SLUGS.read_text().splitlines() if s.strip()]
    rules = load_json_strict(RULES)
    overrides = load_json_strict(OVERRIDES)
    fedb_index: dict[str, dict] = {}
    for entry in load_fedb(args.fedb):
        fedb_index.setdefault(normalize(entry["name"]), entry)

    catalog, enriched, overridden, fedb_difficulty = [], 0, 0, 0
    pattern_fallthrough, equipment_fallthrough = [], []

    for slug in slugs:
        words = slug.replace("-", " ")

        override = overrides.get(slug, {})

        # A fallthrough is only recorded when the *shipped* value is a guess:
        # no keyword matched and overrides.json does not state the fact. If a
        # slug matches nothing but the fact is written down, the catalog is not
        # guessing and the slug does not belong on the acknowledged list. This
        # is what makes the lists below shrink as facts get recorded, instead
        # of being a permanent inventory of every slug the keyword tables miss.
        pattern_match = longest_match(slug, rules["pattern"])
        pattern = pattern_match or rules["defaultPattern"]
        if pattern_match is None and "pattern" not in override:
            pattern_fallthrough.append(slug)

        equipment_match = longest_match(slug, rules["equipment"])
        equipment = equipment_match or rules["defaultEquipment"]
        if equipment_match is None and "equipment" not in override:
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

        # Difficulty: an explicit override wins outright, same as every other
        # field overrides.json touches — overrides.json is documented above
        # as the highest-precedence source, and a per-exercise exception
        # (e.g. jump rope and jumping jacks are beginner even though the
        # plyometric pattern is advanced for the box jumps and burpees
        # alongside them) is exactly the kind of genuine, isolated fact that
        # belongs there rather than forking the pattern rule. Without this
        # check, `entry.update(overrides[slug])` above sets entry["difficulty"]
        # only for it to be silently clobbered by the derivation below, which
        # made a "difficulty" key in overrides.json dead data.
        if "difficulty" in overrides.get(slug, {}):
            pass  # entry.update(overrides[slug]) above already set it.
        else:
            # Derive from pattern > equipment > mechanic > default, using
            # entry's final (post-override) fields so a hand-authored
            # correction to pattern/equipment/mechanic is honored.
            # free-exercise-db is real human-authored data, but its `level`
            # field is internally inconsistent: "Barbell Squat" -> beginner
            # while "Pushups" -> beginner too, "Power Clean" -> intermediate
            # while "Clean and Jerk" -> expert for materially the same skill,
            # "Barbell Deadlift" -> intermediate while our own
            # compound+barbell rule already says intermediate. It is too
            # noisy to let it lower a rating our own derivation already
            # established (it once dragged barbell-squat and six other
            # loaded barbell/trap-bar compounds down to "beginner"). So fedb
            # may only RAISE difficulty above the derived value, never lower
            # it: we take the max rank of derived vs. fedb.
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

    # Every gate runs BEFORE the write, so a rejected build leaves the
    # previous catalog on disk untouched rather than a fabricated one plus a
    # non-zero exit code nobody reads. This ordering is what makes
    # report_fallthrough's promise ("cannot be written at all") literally true.
    ids = [e["id"] for e in catalog]
    if len(set(ids)) != len(ids):
        print("FAIL: duplicate ids", file=sys.stderr)
        return 1

    print(f"  fell through to defaultPattern ({rules['defaultPattern']!r}): "
          f"{len(pattern_fallthrough)}")
    if pattern_fallthrough:
        print(f"    {', '.join(sorted(pattern_fallthrough))}")
    print(f"  fell through to defaultEquipment ({rules['defaultEquipment']!r}): "
          f"{len(equipment_fallthrough)}")
    if equipment_fallthrough:
        print(f"    {', '.join(sorted(equipment_fallthrough))}")

    failures = report_fallthrough(
        "pattern", pattern_fallthrough, rules["acknowledgedPatternFallthrough"])
    failures += report_fallthrough(
        "equipment", equipment_fallthrough, rules["acknowledgedEquipmentFallthrough"])
    if failures:
        print(f"FAIL: refusing to write {OUT.relative_to(ROOT)}", file=sys.stderr)
        return 1

    output = {"version": CATALOG_VERSION, "exercises": catalog}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(output, indent=2, sort_keys=True, ensure_ascii=False) + "\n")

    print(f"wrote {len(catalog)} exercises to {OUT.relative_to(ROOT)}")
    print(f"  enriched from free-exercise-db: {enriched}")
    print(f"  hand-authored overrides:        {overridden}")
    print(f"  difficulty from free-exercise-db level: {fedb_difficulty}")
    difficulty_counts = collections.Counter(e["difficulty"] for e in catalog)
    print(f"  difficulty distribution: {dict(sorted(difficulty_counts.items()))}")
    return 0


def report_fallthrough(field: str, actual: list[str], acknowledged: list[str]) -> int:
    """Compare the slugs that took a default against the acknowledged list.

    A default is a guess wearing the same clothes as a real classification: a
    slug that matches no keyword receives a complete, plausible-looking entry
    (`defaultPattern` alone brings a pattern, a mechanic, a primary muscle, a
    force, and a category with it) and nothing downstream can tell it apart
    from a fact. The generator is where that must be caught, not a test: the
    guess is fabricated here, and failing here means the wrong value cannot be
    written to `exercises.json` at all, let alone committed, shipped, or
    stamped with a catalog version. A test would only catch it after the bad
    data was already in the tree, and only if someone ran the suite.

    Both directions fail. An *unacknowledged* slug means a new exercise
    silently inherited a guess — record the fact in overrides.json, or add a
    keyword rule, or add the slug here to say the default is genuinely right
    for it. A *stale* entry means an acknowledged slug no longer takes the
    default, so the list would otherwise rot into a list of slugs nobody has
    checked in years.
    """
    unexpected = sorted(set(actual) - set(acknowledged))
    stale = sorted(set(acknowledged) - set(actual))
    if not unexpected and not stale:
        return 0
    print(f"FAIL: {field} fallthrough does not match "
          f"acknowledged{field.capitalize()}Fallthrough in "
          f"{RULES.relative_to(ROOT)}", file=sys.stderr)
    if unexpected:
        print(f"  matched no {field} keyword and states no {field} override, "
              f"so it shipped a guessed value:", file=sys.stderr)
        for slug in unexpected:
            print(f"    {slug}", file=sys.stderr)
    if stale:
        print(f"  acknowledged but no longer falls through (remove):", file=sys.stderr)
        for slug in stale:
            print(f"    {slug}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(build())
