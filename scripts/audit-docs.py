#!/usr/bin/env python3
"""Every type a document names, checked against the sources.

Run it beside the suites:

    python3 scripts/audit-docs.py

**Why this exists.** Three times in one week a document named something that no
longer existed, and once — worse — it named live code as deleted, which is the
direction that gets working code removed. Prose has no compiler and no test, so
it is the only part of this project with no forcing function at all; every other
drift the standards guard against is caught by one. This is that guard.

**What it does not do.** It checks that a backticked capitalised name resolves to
a declared type or a source file. It cannot tell whether a sentence is true, and
it deliberately does not try — `decided.md` is *supposed* to name dead types,
because recording what was killed is its job. What it catches is the name that
nobody meant to be historical.

Exit code is 1 when a document outside the historical set names something that
is gone, so it can fail a check rather than merely print.
"""

import os
import re
import sys

SOURCE_ROOTS = [
    "LiftingKit/Sources", "LiftingMCP/Sources",
    "LiftingPlan", "LiftingPlanTests",
    "LiftingKit/Tests", "LiftingMCP/Tests",
]

# **Documents whose job is to name dead things.** `decided.md` records what was
# tried and killed; the rebuild pair were written before the rebuild and describe
# what was replaced. Naming a corpse is correct in these and a defect anywhere
# else, so they are reported and not failed on.
HISTORICAL = {
    "decided.md",            # records what was tried and killed
    "rebuild-spec.md",       # written before the rebuild, describes what it replaced
    "rebuild-inventory.md",  # a verdict per file, taken before anything was built
    # Audits the catalog, which the rebuild did not touch, so its findings are
    # live — but some of its reasoning argues from types that went with the
    # profile, and its own banner says so. Exempt because it names them
    # knowingly; a check that is permanently red is a check nobody reads.
    "audit-data.md",
}


def source_vocabulary():
    """Every identifier declared, and every source file's base name."""
    names = set()
    for root in SOURCE_ROOTS:
        for directory, _, filenames in os.walk(root):
            if ".build" in directory:
                continue
            for filename in filenames:
                if not filename.endswith(".swift"):
                    continue
                names.add(filename[: -len(".swift")])
                text = open(os.path.join(directory, filename)).read()
                names |= set(re.findall(r"\b[A-Za-z_]\w*\b", text))
    return names


def main():
    if not os.path.isdir("docs"):
        sys.exit("run this from the repository root")
    vocabulary = source_vocabulary()
    failed = False

    for document in sorted(os.listdir("docs")):
        if not document.endswith(".md"):
            continue
        # A lowercase second letter is what distinguishes a type from an
        # environment variable or a mark the coach picks — `RENDER` and
        # `SUPERSET` are neither dead nor types, and flagging them would train
        # the reader to ignore this.
        named = set(re.findall(r"`([A-Z][a-z][A-Za-z0-9]*)`", open("docs/" + document).read()))
        gone = sorted(name for name in named if name not in vocabulary)
        if not gone:
            continue
        historical = document in HISTORICAL
        print(f"{'note' if historical else 'STALE'}  {document}: {len(gone)} of "
              f"{len(named)} named types are gone")
        for name in gone:
            print(f"        {name}")
        failed = failed or not historical

    if failed:
        print("\nA document names a type that does not exist. Either the type went "
              "and the document did not, or the name was never right.")
    else:
        print("Every name in every current document resolves.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
