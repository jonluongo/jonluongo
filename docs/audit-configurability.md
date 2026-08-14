# Configurability Audit — LiftingPlan

Date: 2026-08-14
Scope: `Tools/derivation-rules.json`, `Tools/overrides.json`, `Tools/build-catalog.py`, all Swift under `LiftingPlan/`.
Audience split assumed throughout: **developer configuration** (owner edits data, rebuilds) vs. **user configuration** (end user customizes at runtime, no rebuild).

**Framing correction applied mid-audit:** the 412-exercise catalog being hardcoded, bundled, and read-only is intentional and correct — "the lego bricks that we build with," in the owner's words. It is not a finding and no recommendation below asks for user-authored exercises, runtime catalog mutation, or a writable `exercises.json`. The interesting question is one layer up: **how the bricks get assembled into training** — split templates, equipment tiers, prescriptions, balance rules, progression, session structure. That composition layer is where this audit's findings concentrate.

---

## 1. Where training knowledge actually lives

| Knowledge | Currently lives in | Should live in | Severity if misplaced |
|---|---|---|---|
| Exercise → equipment/pattern/muscle/difficulty derivation (the bricks) | `Tools/derivation-rules.json` | Data ✓ (correct) | — |
| Per-exercise hand corrections (the bricks) | `Tools/overrides.json` | Data ✓ (correct) | — |
| Difficulty tie-break vs. free-exercise-db (`DIFFICULTY_RANK`) | `Tools/build-catalog.py` (Python) | Code ✓ — the script's own comment correctly argues this is "mechanism, not data" (a reconciliation rule between two difficulty scales, not a training fact) | — |
| Catalog taxonomies (`MuscleGroup`, `EquipmentType`, `MovementPattern`, `ForceType`, `Mechanic`, `Difficulty`, `ExerciseCategory`) | `Taxonomies.swift`, as `ExtensibleTaxonomy` structs | Code, but correctly extensible (unknown values decode intact) ✓ | — |
| **Equipment-access tiers → permitted equipment types** | `EquipmentAccess.swift` — four hardcoded `Set<EquipmentType>` literals, monotonic unions | Data | **High** (owner-named violation #1) |
| **Weekly split by day count** | `TemplatePlanBuilder.splitTemplate(forDayCount:)` — a `switch` returning `["Push","Pull","Legs"]` etc. | Data — the project's own design doc already specifies this exact table as JSON | **High** (owner-named violation #2) — see §2 for the additional finding that this code path is also dead |
| **Set/rep/rest/tempo prescriptions by goal and experience** | **Does not exist as a rule set anywhere.** The only numbers in the whole app resembling a prescription are prose embedded in `PlanGenerator`'s prompt/`@Guide` strings ("2 to 5 sets," "45 to 180 rest seconds," a rep-range format example) and the safety clamps in `PlanBlueprint.makeWorkoutPlan` (sets 1...8, rest 15...600, default rep range `"8-12"`) | Data. This is the prescription table the design doc assumes exists once `TemplatePlanBuilder` is rewritten "against these rules and the catalog" — it doesn't yet. Nothing today maps `(goal, experience, slot role)` → `(sets, rep range, rest, tempo)`. | **High** (absence, not misplacement — see §3) |
| **Balance rules** (pull ≥ press volume, every week hits squat/hinge/pull, no pattern >half a session) | **Not implemented anywhere in code.** They exist only as prose in `docs/superpowers/specs/2026-08-14-workout-programming-design.md`. `grep` for `balance`/`pullVolume`/`pressVolume` across `LiftingPlan/` returns nothing but a doc-comment mentioning "balanced sessions" in passing (`Taxonomies.swift:66`) | Data-driven rules, per the design doc's own explicit instruction ("Enforced when a week is assembled, as data-driven rules rather than hardcoded conditionals") | **High** (absence — the foundation cannot express these yet at all; see §3) |
| **Progression scheme** (RPE ceiling, heavy/light load threshold, load increments, rounding increment) | `ProgressionEngine.swift:59-69` — five `static let Double` constants baked into the enum, read directly by two view-layer call sites | Data. This is a specific, opinionated progression philosophy (linear double progression with a hard weight cutoff at 50) — exactly the kind of "fact about training" the project principle targets. Every number in `suggestion(for:)` traces back to one of these five literals or the `2.5`/`50` figures embedded directly in the constants | **High** |
| **Session structure** (slot count from time budget, ordering by neurological demand: primary compound → secondary compound → accessory → finisher) | **Not implemented anywhere.** `TemplatePlanBuilder.build` unconditionally returns `PlanBlueprint(days: [])` — see its own doc comment: "Currently returns an empty plan... selecting from that catalog against the programming rules... is the next plan's work." The AI-model path (`PlanGenerator`) asks the model for "3–6 exercises, compounds first" in prose, with no time-budget → slot-count function anywhere | Data/algorithm split per the design doc: slot count as a function of time budget, ordering by role, both meant to be governed by the same "balance constraints" JSON as above | **High** (absence — the template-generation path is a stub with none of this logic written yet) |
| Rep-range text parsing rules (digit-run scanning, "5-3-1" convention) | `RepRange.swift` | Code ✓ — this is a parser for free-text, not a training opinion | — |
| Estimated 1RM formula (Epley: `load * (1 + reps/30)`) | `LoggedSet.swift:48`, duplicated verbatim in `StrengthBaseline.swift:38` | Borderline. A fixed, named formula is reasonable as code, but it's a specific choice among several (Brzycki, Lombardi) with no seam to swap it, and it's copy-pasted rather than shared | **Low** (duplication; would become Medium if formula choice mattered) |
| UI-offered rest-timer presets | `[30, 45, 60, 75, 90, 120, 150, 180]`, duplicated verbatim in `ActiveWorkoutView.swift:20` and `ExerciseLogSection.swift:20` | Data, or at minimum one shared constant | **Medium** (duplication/drift risk, low training stakes) |
| UI-offered session-duration presets | `[30, 45, 60, 75, 90]` in `SetupView.swift:28` | Data | **Low** |
| Default training block shape (weekCount=8, weekdays=[Mon,Wed,Fri], durationMinutes=45) | Swift property/init defaults on `TrainingPlan.swift`, re-typed in `SetupView` and `PlanOverviewView` fallback literals | Fine as CloudKit-required code defaults; the specific *values* are a mild opinion re-typed in 3 places | **Low-Medium** (duplication more than misplacement) |

**Count of data-over-code violations beyond the two named:** treating "misplaced" (exists, wrong location) separately from "absent" (doesn't exist at all, so nothing to relocate) —

- **Misplaced (code today, should be data):** progression-scheme constants (`ProgressionEngine`), duplicated rest-timer presets, duplicated session-duration presets, duplicated default block shape. **4.**
- **Absent (the design doc calls for data-driven rules that were never written):** set/rep/rest/tempo prescription table, balance rules, session-structure (slot count + ordering). These aren't misplaced — they're missing, in both code and data. Their only trace is prose in `PlanGenerator`'s prompt and a stub in `TemplatePlanBuilder.build`.

So: **4 additional misplacement violations**, plus **3 load-bearing absences** that are arguably more urgent than any misplacement, because right now the app has no working non-AI path to assemble a plan at all.

---

## 2. The seam between "bricks" and "assembly rules"

This is the most important structural finding. The catalog boundary itself is clean: `ExerciseCatalogProviding` (`Catalog/ExerciseCatalog.swift:56-62`) is a narrow, sane protocol; `Exercise` decoding is deliberately lenient/forward-compatible; nothing outside `Catalog/` constructs exercises by hand. The bricks are well-isolated.

**What's tangled is that the assembly layer barely exists, and the one piece of it that does exist is disconnected from the rest of the app:**

- `TemplatePlanBuilder.splitTemplate(forDayCount:)` — the owner-named violation — is not only a hardcoded `switch`, it is **dead code in the running app**. `TemplatePlanBuilder.build(weekdays:durationMinutes:equipment:experience:)` is the only method actually called (from `PlanGenerator.generatePlan`), and it ignores `splitTemplate` entirely, returning `PlanBlueprint(days: [])` unconditionally. `splitTemplate` is exercised only by `TemplatePlanBuilderTests.swift`. So today there is no code path — template or AI — that uses a split table, a prescription table, or a balance rule to assemble a session from the catalog. The switch statement isn't wrongly-placed assembly logic so much as a fragment of assembly logic that was never wired to anything.
- The **only thing currently assembling a real plan is the on-device model**, via free-text prompt engineering (`PlanGenerator.instructions`/`prompt`) plus a `@Generable` schema with hardcoded numeric ranges in `@Guide` descriptions. Even there, the design doc is explicit that this is wrong for structural guarantees: *"it is good at interpreting a lifter's stated goal... and bad at guaranteeing balance or structural correctness. So the app owns the skeleton... and the model fills slots from the catalog."* Today the app does not own the skeleton — the model does, unconstrained by any data-driven balance rule, because none exists to constrain it with. `PlanGenerator.blueprint(from:...)` (`PlanGenerator.swift:194-217`) doesn't even map the model's exercises through yet (deliberately, per its own comment) — it keeps only the day/focus skeleton and drops all exercises.
- **`ExerciseResolver`** is the one piece of machinery already built and ready to sit exactly on this seam ("anything [the model] returns still passes through `ExerciseResolver`," per the design doc) — but nothing calls it from `PlanGenerator` yet. It's a finished bridge with no traffic on it.

**Conclusion for this section:** the seam isn't tangled by bad coupling — it's tangled by absence. There's no single Swift type today that takes `(equipment tier, experience, day count, time budget)` and produces `(split, slot count per day, pattern per slot, sets/reps/rest per slot)` from data. Once that type exists and is data-driven, `EquipmentAccess` and `TemplatePlanBuilder.splitTemplate` stop being isolated violations and become two inputs into it — which is probably why fixing them in isolation feels premature right now: they're two known corners of a table that doesn't fully exist yet.

---

## 3. Extension points

**What exists and works:**
- `ExtensibleTaxonomy` (`Domain/ExtensibleTaxonomy.swift`) is the strongest seam in the codebase: unrecognized catalog values decode intact rather than failing, `known` gives UI/validation an enumerable list without closing the type. This is real forward-configurability for catalog *vocabulary* (muscle groups, patterns, equipment types) — correctly so, since the vocabulary can grow even though the exercise list itself is fixed.
- `ExerciseCatalogProviding` is a protocol seam; `ExerciseCatalog` (bundled JSON) is one conformer, tests already supply fixtures. This is the right shape for "bricks are fixed but the read interface is abstract" — no change needed here given the catalog-is-fixed framing.

**What's missing, specific to the assembly layer:**

- **No `ProgressionScheming` protocol.** `ProgressionEngine` is a bare `enum` called directly from two view-layer sites (`ActiveWorkoutView.seedLoad`, `ExerciseLogSection.previousText`). A second progression scheme (RPE-autoregulated, percentage-of-1RM) means editing this file in place — there's no seam to add a second conformer beside it. Building one requires: extract a protocol (`suggestion(for: ExerciseHistory) -> ProgressionSuggestion`), move the five constants (§1) into the conforming type's own data, and inject the chosen scheme at the two call sites instead of calling the enum by name.
- **No `PlanGenerating`/assembly protocol.** `PlanGenerator` hardcodes exactly two paths (Foundation Model or `TemplatePlanBuilder`) as a concrete `@Observable final class`. A second generator (rule-based expert system, a different AI backend, a coach-authored program importer) means forking or branching inside this file — there's no strategy seam.
- **No `SplitTemplating`/assembly-rules abstraction**, which is really the same gap as §2: nothing owns "given inputs, produce a skeleton" as a swappable, data-fed unit. `EquipmentAccess` and `TemplatePlanBuilder` are both `enum`-with-`static func` namespaces, not types — nothing prevents a second lookup table from being loaded (e.g., a different split philosophy) because there's no protocol boundary to plug it into, just static functions.
- **`Equipment` and `ExperienceLevel` are closed Swift `enum`s** (`TrainingEnums.swift`), unlike the catalog's `ExtensibleTaxonomy` structs. This is a real inconsistency: `EquipmentType` (what an exercise *requires* — a brick property) is extensible; `Equipment` (what a lifter *has* — an assembly-layer input) is not. `EquipmentAccess.permitted(for:)` pattern-matches all four cases exhaustively, so even after moving the tier *contents* to JSON, adding a fifth tier is still a compile-time change in at least two files (the enum, the switch/lookup). If the eventual data-driven equipment-tier table is meant to be user-tunable (see §4), the tier identifier itself needs to stop being a closed enum.

---

## 4. Readiness for user-level runtime configuration

Given exercises themselves are out of scope for user editing, the realistic shape of "user configures the app" is: *pick among / lightly tune the assembly rules the owner has authored as data* — not author new rules from scratch, and never touch the catalog.

**Small changes** (no new architecture, just work within the existing layering):
- **Per-plan rep range / rest / tempo editing is already live data.** `PlannedExercise.repRange`, `.restSeconds`, `.tempo`, `.targetSets` are plain `@Model` `var`s already edited at runtime (`ExerciseLogSection`'s rest-timer `Menu` already does `exercise.restSeconds = seconds`). Exposing broader in-workout editing of these is UI-layer work only.
- **Avoided exercises / avoided patterns already exist as user-editable exclusion data.** `UserProfile.avoidedExercises` / `avoidedPatterns` (`UserProfile.swift:81-92`) and `permits(pattern:)`/`permits(exercise:)` are built and ready; there's just no settings UI yet. This is exactly the kind of "configure the assembly, not the bricks" feature the owner wants, and the data model already supports it.
- **Progression-scheme *tuning*, short of a second scheme** — once the five `ProgressionEngine` constants move to a bundled-JSON default (§1), storing a user override (e.g., "more/less aggressive") on `UserProfile` is additive: one struct, one stored property, read from it instead of the global constant. No architectural obstacle, contingent on the constants first becoming data.
- **UI presets** (rest-timer choices, duration choices) — trivial to move to a small bundled list; not user-data-layer work at all.

**Structural changes** (would require new architecture):
- **The assembly-rules table (§2) has to be built before it can be made user-configurable, because it does not exist yet.** This is the dominant fact for this section: user-level configuration of split templates, prescriptions, and balance rules is not "blocked" by a specific obstacle so much as premature — there is no owner-tunable data-driven version yet to expose a user-facing subset of. Sequencing matters: (1) write the assembly rules as bundled JSON per the design doc, wired into a real `TemplatePlanBuilder.build` that no longer returns empty, (2) only then consider which of those rules a user should be allowed to override, and how.
- **No user-override layer exists for *any* bundled rule set**, catalog or otherwise. `StoreContainer.schema` (`StoreContainer.swift:15-25`) lists nine `@Model`s — all user *records* (workouts, sets, baselines, profile) or *derived* data (plans, weeks, days) — none is a *rule override*. The pattern this needs (bundled default + optional per-user override, checked at read time) doesn't exist anywhere in the codebase yet, not even for the smaller things listed under "small changes" above — those are additive precisely because they'd be the first instance of the pattern, not because the pattern is already proven elsewhere.
- **CloudKit sync has no story for rule-like data.** Every existing `@Model` is either append-only (sets, baselines) or a singleton (`UserProfile`), which sidesteps concurrent-edit conflicts. A user-tunable rule set (e.g., "my preferred split philosophy") edited on two devices is a different sync shape (a small, denormalized, potentially-conflicting record) that nothing in the current schema resembles yet.
- **`PlanGenerator`/`TemplatePlanBuilder` have no "check user override, else bundled default" read path anywhere.** Once assembly rules are data, user-level override still requires this second read path, which is a small but real addition on top of §1's fix, not present today.

---

## 5. Over-configuration risk

- **Progression math must not become an unbounded user-facing toggle.** `ProgressionEngine`'s heavy/light threshold and load increments are plausible candidates for a user knob ("progress me faster/slower") — but if load increments become free-text with no bounds, nothing stops a user from configuring dangerous week-over-week jumps. `PlanBlueprint.makeWorkoutPlan`'s existing clamps (sets 1...8, rest 15...600s) are the right precedent: any future user-facing progression tuning needs the same clamp-at-the-boundary treatment, not a raw numeric field.
- **`ExerciseResolver.fuzzyThreshold = 0.82` should stay fixed.** It's a matching-algorithm parameter, not a training preference. The design doc is explicit that an unresolved name must never silently persist as the wrong exercise; letting a user lower this "to get more matches" directly risks merging two different exercises' progression history under one id, corrupting the exact integrity `ExerciseID` exists to protect.
- **Difficulty/mechanic/pattern reconciliation precedence in `build-catalog.py`** (rules < free-exercise-db < overrides; "fedb may only raise difficulty, never lower it") encodes a specific, documented, debugged judgment call about data quality. This should stay pipeline logic, not become user-configurable — it's about reconciling two data sources, not a training preference.
- **Balance rules, once implemented, should be enforced invariants, not optional toggles.** "Pull volume ≥ press volume" exists to prevent a specific, real shoulder-health failure mode of self-programmed training. A user who could disable it would recreate exactly the problem it exists to prevent. If any part of balance rules becomes user-tunable, it should be tunable within bounds (e.g., *how much* more pull than press) rather than a rule the user can switch off entirely.
- **`EquipmentAccess` tier monotonicity is a correctness property, not a convenience.** Each tier being a strict superset of the one below it ("fullGym can do anything homeMinimal can") is likely relied on implicitly elsewhere. If tiers become user-configurable (per §3's gap), monotonicity needs to be enforced structurally at load/validation time — a hand-edited or user-edited tier table that silently breaks the ordering would produce plans that quietly assume equipment the lifter doesn't have.
- **UI presets (rest-timer choices, session-duration choices) are safely, freely configurable** with no guardrails needed — genuinely low-stakes.

---

## Summary of file references

- `LiftingPlan/Domain/EquipmentAccess.swift:16-42` — named violation #1 (hardcoded `Set` tiers)
- `LiftingPlan/Services/TemplatePlanBuilder.swift:17-36` — named violation #2 (`switch`-based split table); note `build()` (lines 17-24) never calls `splitTemplate` and returns an empty plan unconditionally — the whole method is currently dead outside tests
- `LiftingPlan/Services/ProgressionEngine.swift:59-69` — progression-scheme constants
- `LiftingPlan/Services/PlanGenerator.swift:146-176,229-253` — session-shape numbers in prompt/schema; `194-217` — model output's exercises deliberately dropped, only day/focus skeleton kept
- `LiftingPlan/Services/PlanBlueprint.swift:53-84` — clamp magic numbers, default rep range
- `LiftingPlan/Catalog/ExerciseCatalog.swift:56-62` — `ExerciseCatalogProviding`, the clean brick-layer seam
- `LiftingPlan/Catalog/ExerciseResolver.swift` — built, ready, but not yet called from `PlanGenerator`
- `LiftingPlan/Views/ActiveWorkoutView.swift:20`, `LiftingPlan/Views/Components/ExerciseLogSection.swift:20` — duplicated rest presets
- `LiftingPlan/Views/SetupView.swift:28` — duration presets
- `LiftingPlan/Store/TrainingPlan.swift:19-27,35-39` — default block shape
- `LiftingPlan/Store/UserProfile.swift:81-92` — existing user-exclusion hook (assembly-layer, not catalog), no UI yet
- `LiftingPlan/Store/StoreContainer.swift:15-25` — schema with no rule/override model
- `docs/superpowers/specs/2026-08-14-workout-programming-design.md` — the design doc specifying the assembly-rules layer that mostly doesn't exist in code yet; independently confirms §1/§2
