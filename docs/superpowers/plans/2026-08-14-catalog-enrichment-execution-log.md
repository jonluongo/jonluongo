# SDD ledger — plan: docs/superpowers/plans/2026-08-14-catalog-enrichment.md

Branch: claude/ios-lifting-plan-app-w531jb
Start: d4856e7 (102 tests) -> End: ab34ee2 (114 tests in 15 suites)

Task 1: complete (1b3b801). Secondary muscles derived from movement pattern.
  Coverage 64 -> 313 of 412, zero primary/secondary overlaps.
  Implementer also caught a real generator bug: the enrichment step
  unconditionally reset secondary=[] when a name matched but the source had no
  secondary data, silently discarding the pattern default for matched entries.

Task 2: complete (ac10fed) + fix round (0a64983). Difficulty taxonomy.
  CONTROLLER-FOUND DEFECT in the first commit: barbell-squat rated beginner
  while push-up rated intermediate. Traced to free-exercise-db's `level` field
  being internally unreliable — it rates "Barbell Squat" beginner and "Barbell
  Deadlift" intermediate, and a power clean the same as a deadlift. That had
  dragged 7 compound barbell lifts down to beginner.
  Fix generalizes reasoning the implementer had already applied to pattern on
  its own initiative: external level may only RAISE a rating, never lower it.
  Ranked beginner/intermediate/advanced 0/1/2 and take max(derived, fedb).
  Entries taking difficulty from fedb dropped 71 -> 7.
  Added loadedCompoundBarbellLiftsAreNotBeginner — the assertion that would
  have caught the original bug.
  Final distribution: beginner 239, intermediate 153, advanced 20.

Task 3: complete (ab34ee2). BodyMetric, StrengthBaseline, enforceable
  constraints on UserProfile. Both new models registered in
  StoreContainer.schema (verified — a model missing there silently never
  persists). StrengthBaseline.estimatedOneRepMaxKilograms is byte-identical in
  formula to LoggedSet's, verified by diff, so a baseline and a logged set of
  the same weight can never disagree.

DEFERRED MINOR (implementer-flagged, controller agrees): UserProfile.bodyweight
  and BodyMetric overlap conceptually — the former is a denormalized "latest
  reading" convenience, like PlannedExercise.displayName. Nothing syncs them
  automatically. Collecting and consuming the data were both scoped out of this
  plan, so the sync rule belongs with whichever lands first. Flag to that plan.

FINAL STATE VERIFIED BY CONTROLLER:
  114 tests in 15 suites passing. Zero force unwraps/try!/as!. Zero try?
  discarding errors. Zero layer violations. Working tree clean.
  CloudKit CKAccountStatusNoAccount errors in test output are expected — the
  simulator has no iCloud account and the container degrades gracefully.
