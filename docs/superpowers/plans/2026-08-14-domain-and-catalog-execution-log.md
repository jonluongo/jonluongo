# SDD ledger — plan: docs/superpowers/plans/2026-08-14-domain-and-catalog.md

Branch: claude/ios-lifting-plan-app-w531jb
Start commit: 67175a5

Pre-flight scan: found and fixed one plan defect before dispatch — machine and
cable exercises whose slugs name no equipment (lat-pulldown, leg-press) would
have defaulted to bodyweight. Fixed in 67175a5. Verified Task 8's coverage
assertions hold against the real slug list (~370 resistance entries; every
asserted pattern has bodyweight options).

## Tasks

Task 1: dispatched (implementer a6a796a4ba13f7397, base 67175a5)
Task 1: BLOCKED on dispatch 1 — pre-existing baseline break. The test target
  has never compiled: PlanMappingTests.swift:61 `func epley()` calls
  `try #require` without `throws`. Verified independently by the controller.
  Not a Task 1 defect; the plan assumed a green baseline.
Task 1: resumed implementer with authorization to fix the baseline as a
  separate prerequisite commit, then continue with the build settings.
Task 1: prerequisite commit 3e77cad (added `throws` to `func epley()`).
  Test target now compiles for the first time: 22/23 pass.
Task 1: BLOCKED again on a second, different pre-existing defect —
  ProgressionEngineTests.swift:106 asserts
  roundToNearest(103.7, step: 2.5) == 105, but nearest is 102.5
  (1.2 away vs 1.3). Controller ruling: the IMPLEMENTATION IS CORRECT and
  the test expectation is arithmetically wrong. Evidence: the test is named
  "Rounds to the nearest 2.5" and its sibling assertion (101.2 -> 100) only
  holds under nearest-rounding. ProgressionEngine.swift must not change.
  Also noted both existing assertions round downward, so there was no
  round-up coverage; instructed to add 104 -> 105.
Task 1: resumed with that ruling. Escalate again only if a THIRD
  pre-existing failure appears that is not a test-expectation arithmetic
  error.
Task 1: implementer DONE — commits 3e77cad (throws fix), 3bdf039 (rounding
  expectation fix), a16e6ba (Swift 6 + strict concurrency + warnings as
  errors in all four buildSettings blocks). Zero source changes were needed
  for strict concurrency.
Task 1: task review clean — spec PASS, quality APPROVED, no findings.
  Reviewer confirmed all four blocks changed, alphabetical order kept, no
  @unchecked Sendable / nonisolated(unsafe) / @preconcurrency anywhere, both
  baseline fixes minimal, ProgressionEngine.swift untouched, and the nine
  `try? context.save()` calls left alone.
Task 1: controller resolved the reviewer's one "cannot verify from diff"
  item by running the suite independently: "✔ Test run with 23 tests in 4
  suites passed". NOTE the trap — xcodebuild also prints "Executed 0 tests"
  from the legacy XCTest reporter, and TEST SUCCEEDED prints even when
  nothing runs. Documented in CLAUDE.md (63b29da).
Task 1: complete (commits 67175a5..a16e6ba, review clean)

Task 2: dispatched (implementer aad0188b98940f485, base 63b29da)
Task 2: implementer DONE — commit b68000a. Created
  Domain/ExtensibleTaxonomy.swift and Domain/Taxonomies.swift.
Task 2: note — implementer observed `xcodebuild test` auto-rewriting
  project.pbxproj (objectVersion 77->71, sync-group reformat) and reverted
  it before committing. Controller confirmed tree clean and objectVersion
  back to 77. Watch for recurrence on later tasks.
Task 2: task review clean — spec PASS, quality APPROVED, no findings.
  Reviewer confirmed canonicalization present on all six types, the
  backticked `extension` constant in both declaration and known array, the
  lenient decode/encode round-trip, and that a non-failable init(rawValue:)
  legitimately satisfies RawRepresentable's failable requirement.
Task 2: controller verified independently: "✔ Test run with 28 tests in 5
  suites passed".
Task 2: complete (commits 63b29da..b68000a, review clean)

Task 3: dispatched (implementer a2569d9df6acdeff5, base b68000a)
Task 3: implementer DONE — commit 70cd04f, Domain/Mass.swift.
Task 3: task review clean — spec PASS, quality APPROVED, no findings.
  Reviewer did the arithmetic independently: kilogramsPerPound is the exact
  legal 0.45359237, conversions consistent in both directions, converted(to:)
  returns self on a no-op so no drift, rounded(toNearest:) guards a
  non-positive increment. Critically, confirmed the representational-equality
  decision was PRESERVED — no custom == comparing kilograms, so 100 lb still
  does not equal its own kg conversion. A logbook must not rewrite what was
  entered.
Task 3: controller verified independently: "✔ Test run with 35 tests in 6
  suites passed".
Task 3: complete (commits b68000a..70cd04f, review clean)

Task 4: dispatched (implementer a72dbb07572b6520d, base 70cd04f)
Task 4: implementer DONE — commit 35886ea, Domain/Exercise.swift.
Task 4: task review clean — spec PASS, quality APPROVED, no findings.
  Reviewer verified the asymmetric decoding contract field by field: the six
  required fields use throwing `decode`, the lenient ones use
  `decodeIfPresent`. Checked for transposition errors (secondaryMuscles not
  landing in primaryMuscles) and found none. Confirmed no CodingKeys enum is
  needed since only init(from:) is hand-written, so Swift synthesizes keys
  from property names.
Task 4: controller verified independently: "✔ Test run with 40 tests in 7
  suites passed".
Task 4: complete (commits 70cd04f..35886ea, review clean)

Task 5: dispatched (implementer a1b03665c53235138, base 35886ea)
Task 5: implementer DONE_WITH_CONCERNS — commit e05bdf5. 412 entries, 95
  enriched from free-exercise-db, 54 overrides (grew from the brief's 12
  under the audit mandate, which was authorized).
Task 5: task review — spec PASS, but quality FINDINGS. Reviewer confirmed
  the 6 defects the controller found by querying output, then found 8 MORE
  slugs in 3 groups. 14 bad slugs total. All one root cause: rule-table keys
  matching slug substrings, where short keys hide inside unrelated words.
    Critical: equipment key "ring" hides in "hamstring" — the only 3
      suspension entries in the catalog are all false positives.
    Critical: pattern key "rope" hides in cable rope-attachment names —
      cable face pulls landed in category "cardio".
    Important: muscleHints "lat" hides in plate/lateral/bilateral/
      unilateral/iso-lateral; "chest" matches chest-supported rows where the
      chest is what you lean on; "trap-bar" broke trap-bar-shrug.
  Controller independently verified both Criticals before dispatching.
Task 5: deferred minor — 9 Olympic-lift overrides (hang-clean, power-clean,
  push-jerk, split-jerk, snatch-pull etc.) encode a fact that generalizes
  (Olympic pattern implies barbell) and arguably belong as a rule rather
  than 9 separate overrides. Not blocking. Flag to the final review.
Task 5: deferred minor — 5 override entries carry explicit "force": null.
  Verified harmless: decodeIfPresent checks decodeNil first, so JSON null
  and an absent key both decode to nil. Cosmetic only.
Task 5: fix round 1/5 dispatched to the original implementer with all 14
  slugs, the root-cause analysis, the exact key deletions, and a mandated
  re-audit plus a sweep for other short-key collisions.
Task 5: fix round 1/5 result — commit 97d2876. Implementer fixed the 14 and
  found 10 MORE collisions plus 2 order-dependent same-length ties. Scoped
  re-review: all 3 findings ADDRESSED, no new breakage, consistency audit
  down to only neck-curl (correct). Controller verified by direct query:
  412 unique, 0 missing fields, 0 suspension false positives, 0 cable or
  barbell entries in the cardio category.

ENVIRONMENT INCIDENT (resolved): the machine hit a genuinely full disk —
  APFS container 99.8% used, 225MB free — and xcodebuild failed with ENOSPC.
  Investigated: no Time Machine snapshots; ~/Library/Developer/XCTestDevices
  showed 64GB but was APFS copy-on-write clones, so deleting the 17
  abandoned test-runner clones (all 5+ weeks old, from June/July) reclaimed
  almost nothing. Freed ~8GB by clearing regenerable Xcode caches:
  iOS DeviceSupport (5.7GB, rebuilds on next device connect), all
  DerivedData, ModuleCache, SymbolCache. Builds work again — verified
  "✔ Test run with 40 tests in 7 suites passed". NOT fixed and still the
  user's call: ~/Library/Application Support/com.apple.wallpaper is 30GB,
  which is a known macOS cache bug, and the data volume remains 97% full.

Task 5: fix round 2/5 dispatched. Re-review found
  machine-cable-v-bar-push-downs misclassified; controller checked whether
  it was isolated and found a CLASS — 34 entries fell through to
  defaultPattern "carry", and since patternMuscles["carry"] is
  ["abdominals"], every unmatched exercise silently became an ab exercise.
  ~25 are genuinely wrong (kettlebell-swing, dumbbell-push-press,
  barbell-rack-pull, wall-sit, the thrusters, the landmine presses).
  Structurally valid, so Task 8's integrity tests would NOT catch it.
  Root cause: the pattern table has no bare "press" or "pull" key, only
  compound ones. Fix also mandates a generator guard that counts and prints
  default-pattern and default-equipment fallthroughs, so this can never
  hide silently again.
Task 5: fix round 2/5 INTERRUPTED — the machine powered off mid-run.
  Verified nothing landed: HEAD still 97d2876, working tree clean,
  derivation-rules.json still lacks bare "press"/"pull", exercises.json
  still shows 34 pattern=="carry" entries. No partial state to clean up.
  Re-dispatched round 2 with the full task restated.
Task 5: fix round 2/5 result — commit 4a79238. Pattern fallthrough cut from
  34 to 9. Guard added to build-catalog.py printing fallthrough counts and
  slugs every run. Also hardened 2 new same-length ties (clean-and-press,
  swim-pull-drill) created by adding the bare press/pull keys.
  Controller verified by query: kettlebell-swing now hinge, wall-sit squat,
  push-downs extension/triceps, thrusters and push-presses vertical press.
Task 5: controller rulings this round —
  (a) The implementer's consistency audit returned 3 not 1 and it REFUSED to
      force a clean pass, investigating instead. Correct call: rotator-cuff
      external rotation genuinely is pattern rotation targeting shoulders.
      MY audit script's expected-set was stale, not the data. Corrected the
      expected set to {'abdominals','shoulders'} for the re-review.
  (b) sled-push as carry (loaded locomotion) and sled-pull as horizontal
      pull: both accepted as defensible judgment calls.
Task 5: scoped re-review of round 2 — finding ADDRESSED, no new breakage.
  Re-reviewer regenerated the catalog live and got byte-identical output
  (confirms determinism). All 24 slug->pattern checks pass. Verified the bare
  "press"/"pull" keys did not capture the 63-slug bench/overhead/leg-press/
  pulldown/pull-up/pullover/face-pull family — longer keys still win.
  Consistency audit returns only neck-curl. 412 unique, no missing fields.
  9 remaining pattern=="carry" entries, each justified (planks, dead-hang,
  farmers-carry, plate-pinch, sled-push, bird-dog, turkish-get-up).
  Guard confirmed mechanism-only, no training knowledge in the script.
Task 5: complete (commits 35886ea..4a79238, review clean after 2 fix rounds)

Task 6: dispatched (implementer a613f2e4bc8cf5bb2, base d784769)
Task 6: implementer DONE — commit ce9afcc, Catalog/ExerciseCatalog.swift.
Task 6: NOTE — the controller's dispatch said to expect 11 new tests; the
  brief contains 10. The implementer transcribed the 10 and flagged the
  discrepancy rather than inventing an 11th to hit the stated number.
  Controller confirmed by counting @Test in the file: 10. The dispatch was
  wrong, the implementer was right.
Task 6: task review clean — spec PASS, quality APPROVED, no findings.
  Reviewer confirmed all three protected decisions held: bundled() throws
  with no [] fallback, ExerciseFilter guards every axis with !isEmpty so an
  empty filter matches everything, substitutes() returns [] for unknown IDs
  rather than trapping. Also verified prefix-first search ranking is real
  (not plain alphabetical), byID uses uniquingKeysWith so duplicates can't
  trap, and only-let stored properties keep Sendable honest under strict
  concurrency.
Task 6: controller verified independently: "✔ Test run with 50 tests in 8
  suites passed".
Task 6: complete (commits d784769..ce9afcc, review clean)

Task 7: dispatched (implementer ad30c88b6cdf123dd, base ce9afcc)
Task 7: implementer DONE — commit c1e67a9, Catalog/ExerciseResolver.swift.
  No fuzzyThreshold change needed; 0.82 passed on first run.
Task 7: task review clean — spec PASS, quality APPROVED. Reviewer HAND-
  COMPUTED the Dice coefficient on "Barbel Bench Pres" vs "barbell bench
  press" (shared 14, totals 14+16, 28/30 = 0.933) to confirm the algorithm,
  and verified the division uses total bigram counts rather than dictionary
  .count — the transcription error that would have produced plausible-looking
  numbers while silently mismatching exercises. Confirmed the core invariant:
  no "closest match anyway" path, nil returned when nothing clears threshold,
  and nil when even the fallback filter matches nothing.
Task 7: deferred minor — ResolvedExercise's doc comment states what it is but
  not how it is used or what it depends on, so it does not fully satisfy the
  doc-comment constraint. Inherited verbatim from the brief, so this is a
  PLAN defect, not an implementer defect. Flag to the final review.
Task 7: controller verified independently: "✔ Test run with 60 tests in 9
  suites passed".
Task 7: complete (commits ce9afcc..c1e67a9, review clean)

Task 8: dispatched (implementer ab1ce1f1520292deb, base c1e67a9)
Task 8: implementer DONE_WITH_CONCERNS — commits cbdce9f (data fix) and
  7690ae7 (tests). Found a THIRD data defect the plan did not anticipate:
  musclesDoNotOverlap failed on floor-press, which had "chest" in BOTH
  primaryMuscles and secondaryMuscles. Fixed correctly via overrides.json +
  regeneration, never by hand-editing generated output.
Task 8: NOTE — controller's dispatch again stated the wrong test count (said
  10 new; brief has 9). Implementer transcribed the 9 and flagged it rather
  than padding. Second time this happened; the implementers were right both
  times. Controller confirmed by counting @Test: 9.
Task 8: task review — spec PASS, quality APPROVED with one Minor finding.
  Reviewer verified the assertion was not weakened, the fix went into
  overrides.json rather than exercises.json, and the regenerated output
  matches the override. Full scan confirms 0 primary/secondary overlaps
  across all 412 entries.
Task 8: DEFERRED MINOR (latent generator bug, controller-confirmed by reading
  the source) — Tools/build-catalog.py line ~122 dedups secondaryMuscles
  against primary, but line ~135 applies overrides AFTERWARD. An override
  that replaces primaryMuscles therefore dedups against the OLD list and can
  silently reintroduce overlap. That is exactly what caused floor-press. The
  per-slug patch is a correct data fix and the new integrity test now catches
  any recurrence at build time, so this is not blocking — but the root cause
  is a generator ordering bug every future override author would hit.
  Recommended one-line fix: re-run the dedup immediately after
  entry.update(overrides[slug]). FLAG TO FINAL REVIEW for triage.
Task 8: controller verified independently: "✔ Test run with 69 tests in 10
  suites passed".
Task 8: complete (commits c1e67a9..7690ae7, review clean, 1 deferred minor)

ALL 8 TASKS COMPLETE. Proceeding to final whole-branch review.

FINAL REVIEW (opus, whole branch 06b6ec0..7690ae7): "ready with follow-ups".
Swift judged clean; the defects are in DATA and in resolver edge cases the
per-task reviews could not see because each saw only its own slice.
  F1 Important — muscleHints keys are "abductor"/"adductor" but the slugs read
     "-abduction"/"-adduction", so no hint fires and patternMuscles["raise"]
     wins: machine-hip-abduction, machine-hip-adduction, bodyweight-hip-
     abduction, standing-cable-hip-abduction, tibialis-raise, hanging-knee-
     raises, captains-chair-knee-raise all have primaryMuscles ["shoulders"].
     band-hip-abduction has ["adductors"] (the ANTAGONIST). Zero of the six
     hip ab/adduction entries is correct.
  F2 Important — fedb enrichment at difflib cutoff 0.87 pulled data from the
     WRONG exercise for ~11 of 95 enriched entries. barbell-incline-bench-
     press carries DECLINE instructions and the alias "decline barbell bench
     press"; cable-external-rotation took Cable INTERNAL Rotation.
  F3 Important — resolver token-sorting collapses cable-high-to-low-fly and
     cable-low-to-high-fly to one key; one silently overwrites the other and
     resolve() returns the wrong direction at .normalized confidence.
  F4 Important — duplicate alias keys silently overwrite: "upright barbell
     row" is an alias on both the barbell and dumbbell entries; the dumbbell
     one wins, so resolving a barbell name returns a dumbbell exercise.
  F5 Important — fuzzy tie-breaking is NONDETERMINISTIC. The loop iterates a
     Dictionary (seed-randomized per process) and keeps the first maximum.
     "dcline push up" ties at 0.87 against decline-push-up and incline-push-
     up, so the same input resolves differently per app launch — precisely
     the history fragmentation this branch exists to prevent.
  F6 Minor — threshold 0.82 loose (32 distinct pairs score >=0.82); recall
     low (30 of 56 common gym names resolve to nothing).
  F7 Minor — rowing-machine-steady-state classified as strength.
  F8 Minor — two vacuous tests (substitutes and resolutionsAreReal).
Deferred item 1 upgraded to MUST-FIX: the generator ordering bug has a live
  second instance — behind-the-neck-press kept fedb's ["calves","quadriceps",
  "triceps"] as secondary muscles. Calves on an overhead press. The
  musclesDoNotOverlap test cannot see this one.
Deferred items 3 and 4 CLOSED by the final review: the Olympic overrides are
  the right shape (equipment is derived independently of pattern, and
  dumbbell-single-arm-clean-and-press is a real counterexample), and
  "force": null is verified harmless.
Final review fix wave dispatched (ONE agent, all findings).
Fix wave result — commits d90f2a6 (generator/data), e478ba5 (resolver),
  854e3ed (tests). All 9 findings fixed plus a bonus data bug the new
  slug-muscle-agreement test caught (horizontal-leg-press-calf-press was
  tagged quadriceps). 71 tests in 10 suites.
Scoped re-review of the fix wave — findings 1-9 all ADDRESSED. Reviewer
  verified the resolver collision handling drops BOTH colliding entries via
  Set-then-compactMapValues (never keeps a winner) and that the fuzzy
  tie-break is a provably order-independent argmax fold. BUT it found NEW
  BREAKAGE introduced by our own fix: raising the enrichment cutoff to 0.93
  discarded three CORRECT matches alongside the bad ones, regressing
  band-external-rotation and cable-external-rotation from shoulders to
  abdominals, and dumbbell-upright-row from shoulders to middle back.
  Controller confirmed by diffing the catalog against 7690ae7. Verdict was
  NOT READY.
Targeted regression fix — commit a42b2a6. Restored the three via overrides
  (keeping the 0.93 cutoff, which is correct). The agent audited all 19
  lost-enrichment entries and found a FOURTH: parralel-bar-dips, where a
  typo in the slug dropped its match to 0.909, just under the new cutoff —
  restored to triceps, consistent with its bench-dips and machine-dips
  siblings. It judged the other 15 correct as-is with per-entry reasoning.

FINAL STATE VERIFIED BY CONTROLLER:
  412 entries, all IDs unique, 0 muscle overlaps, 0 duplicate aliases,
  0 missing required fields. Generator output byte-identical across runs.
  "✔ Test run with 71 tests in 10 suites passed". Working tree clean.
  28 commits on the branch.

Also committed d784769 — workout programming design doc. MoveKit sells
clips only (no splits, sets, reps, or ordering), so organization is ours.
Decided: organize by movement pattern rather than muscle group; enforce
pull>=push balance; order sessions by neurological demand; every pattern
trained twice weekly. Most important rule recorded there — exercise
selection is STICKY across regeneration, because progressive overload is
measured per exercise and a silent swap destroys the progression history.

NOTE (recurring, benign): every `xcodebuild test` run rewrites
project.pbxproj objectVersion 77->71. Each implementer has reverted it
before committing and the controller re-checks. Not a code defect.
SourceKit also reports phantom "cannot find type" / "No such module
'Testing'" errors for new files; the real compiler builds clean.
