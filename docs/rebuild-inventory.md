# The rebuild, file by file

Every source and test file in the project, with a verdict. Written 2026-08-21,
before anything was built, so that "dead code is unacceptable" is enforceable
rather than aspirational.

The design this measures against is the row **The backend, rebuilt** in
`docs/decided.md`. Read that first; this document does not restate it.

**Verdicts.** **Keep** — survives as it is, or with a mechanical rename.
**Rewrite** — the idea survives, the file does not. **Delete** — nothing reads
it once the design lands. **Read** — cannot be classified from its declared
purpose; someone must open it before the rebuild starts.

**Counts.** 143 source files, ~19,000 lines. 98 test files, ~19,000 lines.
The verdict tallies are at the foot of each section.

---

## The data loop, redesigned

Jon: *"We need to full redesign the data loop. When the mcp reads and write
etc."* This is the part that is not just a schema change, and it is the reason
the trainer was told a block had four sessions when it had nine.

### What the loop is today

The phone exports `snapshot.json`; the server reads it for every read tool and
writes `plan.json` and `profile-update.json` back; a watcher takes those in.

**The export fires in exactly two places** — `LiftingPlanApp.swift:110` after an
inbound document is applied, and `:141` when the app leaves the foreground.
Nothing exports when a set is ticked or a session is finished. So the snapshot
is written at the single worst moment available: `SnapshotOutbox`'s own doc
comment says resolving the ubiquity container "can block for seconds", and a
backgrounding app has roughly five seconds before iOS suspends it, with no
background-task assertion requested. A write that does not finish is
indistinguishable from one that never started.

**The phone is the only writer.** Nothing changes the store except the app, so
staleness is not inherent to a phone-exports design — a reliable export means
the snapshot is always current. The four-of-nine report is a bug, not a
limitation.

### What the loop becomes

**Export triggers, in priority order:**

1. **On Finish.** The natural boundary, the moment the coach most needs it, and
   the app is in the foreground with all the time it needs.
2. **Debounced after any logged set** — a few seconds idle. Covers a session
   left half-done, and means the file is written long before suspension.
3. **On backgrounding, wrapped in a background-task assertion**, as a flush
   rather than the only chance.
4. **`exportedAt` on the snapshot**, reported by every tool. It costs nothing
   and it is how this regression would ever be noticed again.

**What sits in the shared container:**

| File | Written by | Read by |
|---|---|---|
| `snapshot.json` | phone | server |
| `plan.json` | server | phone |
| `plans/<id>.json` | phone, on import | nobody yet — the archive |
| `user.md` | server | phone, rendered |
| `program.md` | server | phone, rendered |
| `notes/<file>.<timestamp>.md` | server, before each edit | nobody yet — the versions |

`profile-update.json` is gone.

**The markdown files are not imported.** They live in the container and the app
renders them straight from it. There is no inbox path, no document type, no
refusal — because nothing is read *out* of them. The moment a number must be
extracted from prose, that number belongs in a table instead.

**Writes to markdown are anchored edits.** `update_notes` takes
`{file, old_text, new_text}` and refuses whole if the anchor is missing or
matches more than once. That is the refusal machinery prose currently lacks, and
it is the same rule the rest of the system runs on. A prior copy is kept before
every edit. Dated facts — injuries, weigh-ins — append rather than replace.

### What still needs deciding

Nothing in the loop, now that export timing is answered. The earlier
recommendation to "make staleness visible rather than solve it" is **withdrawn**:
it treated a bug as a constraint.

---

## App target — `LiftingPlan/`

### `Store/` — 12 files → 5 models

| File | Lines | Verdict | Why |
|---|---|---|---|
| `BodyMetric.swift` | 26 | **Delete** | Bodyweight moves to `user.md` |
| `LoggedSet.swift` | 77 | **Rewrite** | Becomes `PerformedSet`; loses `isCompleted`, gains optional `reps` |
| `PersistenceError.swift` | 36 | **Keep** | Save failures still surface |
| `PlannedExercise.swift` | 148 | **Rewrite** | Loses `displayName`, `targetSets`, `repRange`, `tempo`, `lifterNote`, `groupPosition` |
| `PrescribedSet.swift` | 59 | **Rewrite** | Becomes `PlannedSet`; every set is a row, so no more sparse overrides |
| `ProfileStatement.swift` | 59 | **Delete** | Its three dated facts all become prose |
| `StoreContainer.swift` | 44 | **Rewrite** | New schema, new entity names |
| `StrengthBaseline.swift` | 33 | **Delete** | Folds into `PerformedExercise` with `source = stated` |
| `TrainingPlan.swift` | 112 | **Delete** | No routines |
| `TrainingWeek.swift` | 39 | **Delete** | A block is an ordinal on `Session` |
| `UserProfile.swift` | 202 | **Delete** | Every field display-only; the whole profile becomes `user.md` |
| `WorkoutDay.swift` | 113 | **Rewrite** | Becomes `Session`; `weekday` → `ordinal` |
| **new** `PerformedExercise.swift` | — | **Add** | The grain the store has never had |

Keep 1 · Rewrite 5 · Delete 6 · Add 1

### `Services/` — 21 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `DayBlueprint.swift` | 102 | **Delete** | Folds into `RoutineBlueprint`; the tree it navigated is two levels shallower |
| `DocumentInbox.swift` | 286 | **Rewrite** | Absorbs the watcher; loses the profile-update path; markdown is not imported |
| `ExerciseTrend.swift` | 101 | **Delete** | `PerformedExercise` *is* this reduction; two reducers become one |
| `ICloudDocumentTransport.swift` | 143 | **Keep** | Container access is unchanged |
| `PerformanceHistory.swift` | 103 | **Rewrite** | Absorbs `ExerciseTrend`; grain moves to `PerformedExercise` |
| `PlanDocumentMapping.swift` | 148 | **Rewrite** | Reconstruction follows the new document |
| `PlanImporter.swift` | 378 | **Rewrite** | Merge keys on block ordinal, not routine id |
| `ProfileUpdater.swift` | 249 | **Delete** | No profile to update |
| `RestPreferences.swift` | 232 | **Keep** | Already `UserDefaults`, keyed by `ExerciseID`, device-only — and structurally unable to reach `SnapshotExporter` |
| `RestTimerModel.swift` | 184 | **Keep** | Counts down what was prescribed |
| `RoutineBlueprint.swift` | 288 | **Rewrite** | The only seam a plan enters by; still one producer |
| `ScreenLockedCue.swift` | 210 | **Keep** | Notification half, untouched by the schema |
| `SessionGrouping.swift` | 266 | **Rewrite** | Rounds derive from `setIndex` and `order` |
| `SessionLog.swift` | 162 | **Rewrite** | No seeded rows to mutate |
| `SessionOrder.swift` | 146 | **Rewrite** | Working-set numbering survives; its inputs change |
| `SetSeeding.swift` | 95 | **Delete** | A performed row exists only if it happened |
| `SnapshotExporter.swift` | 226 | **Rewrite** | No profile, new tables |
| `SnapshotOutbox.swift` | 125 | **Rewrite** | Three triggers and a background assertion |
| `StatedFacts.swift` | 46 | **Delete** | Dies with `ProfileStatement` |
| `StoreUpgrade.swift` | 43 | **Delete** | The store resets; nothing to carry |
| `UbiquitousDocumentWatcher.swift` | 134 | **Keep** | **Verdict reversed on 2026-08-21, after reading it.** It is `NSMetadataQuery` plumbing — iCloud advertises an item before its contents arrive, so it requests the download and announces only once the item reports current — while `DocumentInbox` handles refusals and application. Two jobs; merging them makes one 420-line file doing both. |

Keep 3 · Rewrite 10 · Delete 8

### `Presentation/` — 21 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `AccountRecord.swift` | 229 | **Delete** | The account screen renders `user.md` |
| `BlockSelection.swift` | 57 | **Rewrite** | Blocks have no names; `isDeload` gone |
| `ExerciseAbout.swift` | 78 | **Keep** | Reads the catalog |
| `HoldPrescription.swift` | 33 | **Delete** | Inferred a hold from free text; the stored `Target` says so |
| `IntensityPrescription.swift` | 75 | **Delete** | One caller; folds into `PrescriptionSummary` |
| `LoggedWorkSummary.swift` | 49 | **Rewrite** | Light — reads a performed set |
| `NumberFormatting.swift` | 15 | **Keep** | — |
| `OpenRoutine.swift` | 57 | **Delete** | No routines to open; Home is blank |
| `PrescriptionSummary.swift` | 119 | **Rewrite** | One of the two survivors: renders a prescription, absorbing intensity and rest |
| `RepPrescription.swift` | 46 | **Delete** | Same inference, same reason |
| `RestPrescription.swift` | 33 | **Delete** | One caller; folds into `PrescriptionSummary` |
| `RestTarget.swift` | 33 | **Rewrite** | Group rest is per exercise now |
| `RoutineFacts.swift` | 49 | **Delete** | The routine screen renders `program.md` |
| `RoutineListing.swift` | 197 | **Rewrite** | Lists blocks, not routines |
| `SessionPhrasing.swift` | 30 | **Rewrite** | No weekday to fall back to |
| `SetEntry.swift` | 97 | **Keep** | What typing means is unchanged |
| `SetFieldLabel.swift` | 84 | **Keep** | — |
| `SetIdentity.swift` | 35 | **Keep** | — |
| `SetRowPrescription.swift` | 81 | **Rewrite** | The other survivor: what one row shows, reading a `PlannedSet` directly |
| `StatedFact.swift` | 35 | **Delete** | Dies with the account rows |
| `WorkPrescription.swift` | 106 | **Delete** | Exists **entirely** to answer which of three a set records — which the schema now answers |

Keep 5 · Rewrite 7 · Delete 9

### `Views/` — 9 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `AccountView.swift` | 173 | **Rewrite** | Renders `user.md` |
| `ActiveWorkoutToolbar.swift` | 40 | **Keep** | — |
| `ActiveWorkoutView.swift` | 387 | **Rewrite** | Rows come from prescriptions, not seeded records |
| `ExerciseDetailView.swift` | 193 | **Rewrite** | History is per performance |
| `RestSheet.swift` | 216 | **Keep** | — |
| `RootView.swift` | 190 | **Rewrite** | No `UserProfile` singleton to guarantee |
| `RoutineInfoSheet.swift` | 67 | **Rewrite** | Renders `program.md` |
| `RoutineView.swift` | 230 | **Rewrite** | Becomes `BlockView` |
| `RoutinesView.swift` | 132 | **Rewrite** | Becomes `HomeView` — blank, account icon only |
| **new** `MarkdownView.swift` | — | **Add** | One renderer, two callers |

Keep 2 · Rewrite 7 · Add 1

### `Views/Components/` — 25 files

| File | Lines | Verdict |
|---|---|---|
| `AccountToolbarItem.swift` | 35 | **Rewrite** — one screen now, not two |
| `CardHeaderRow.swift` | 102 | **Keep** |
| `CoachNoteView.swift` | 45 | **Keep** |
| `DisclosureChevron.swift` | 27 | **Keep** |
| `ExerciseAboutSections.swift` | 67 | **Keep** |
| `ExerciseHeaderView.swift` | 146 | **Rewrite** — tempo folds into the note |
| `ExerciseLogSection.swift` | 152 | **Rewrite** |
| `ExerciseRestSheet.swift` | 194 | **Keep** — depends on `LifterRest` and `RestPrescription`, never on the store |
| `FactRow.swift` | 63 | **Delete** — the account's fact rows go |
| `InfoSheet.swift` | 42 | **Keep** |
| `LifterNoteSheet.swift` | 75 | **Keep** |
| `NoRoutineView.swift` | 28 | **Rewrite** — the empty state is now Home's |
| `NoteRow.swift` | 30 | **Keep** |
| `PanelRow.swift` | 179 | **Keep** |
| `PrimaryActionButton.swift` | 137 | **Keep** |
| `ProgressRule.swift` | 37 | ~~Keep~~ — **deleted in `52a804e`**: the screen that drew it went in the rebuild and nothing replaced the call. |
| `RecordedMark.swift` | 54 | **Keep** |
| `RestTimerBar.swift` | 131 | **Keep** |
| `SectionHeading.swift` | 47 | **Keep** |
| `SessionClock.swift` | 87 | **Keep** |
| `SessionFinishSection.swift` | 99 | **Rewrite** — Finish now triggers an export |
| `SessionIconView.swift` | 51 | **Keep** |
| `SetRowView.swift` | 420 | **Rewrite** |
| `Style.swift` | 512 | **Rewrite** — splits; see below |
| `TimerRing.swift` | 91 | **Keep** |

Keep 17 · Rewrite 7 · Delete 1

### Root

`LiftingPlanApp.swift` (187) — **Rewrite.** The export triggers live here.

---

## `LiftingKit/`

### `Domain/` — 15 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `Distance.swift` | 70 | **Keep** | |
| `EquipmentAccess.swift` | 81 | **Delete** | Tiers were input shorthand for a profile that is gone |
| `Exercise.swift` | 137 | **Keep** | |
| `ExtensibleTaxonomy.swift` | 50 | **Keep** | |
| `Mass.swift` | 70 | **Keep** | Keeps its own unit even though only pounds are written |
| `RepRange.swift` | 95 | **Rewrite** | Becomes part of the typed `Target`, parsed at the boundary |
| `RoutineCalendar.swift` | 75 | **Delete** | A session has no date |
| `RoutineSchedule.swift` | 41 | **Delete** | Same |
| `SessionIcon.swift` | 70 | **Keep** | |
| `TargetUnits.swift` | 163 | **Rewrite** | Runs once at import, not on every read |
| `Taxonomies.swift` | 215 | **Keep** | |
| `TrainingEnums.swift` | 65 | **Rewrite** | `Weekday` and `ExperienceLevel` both go |
| `WorkDistance.swift` | 117 | **Rewrite** | Folds into `Target` |
| `WorkDuration.swift` | 143 | **Rewrite** | Folds into `Target` |
| `WorkMeasure.swift` | 52 | **Keep** | The one value with three cases |
| **new** `Target.swift` | — | **Add** | Measure + range, one type, parsed once |

Keep 7 · Rewrite 5 · Delete 3 · Add 1

### `Catalog/` — 3 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `ExerciseCatalog.swift` | 177 | **Keep** | Gains conditioning entries in the JSON, not the code |
| `ExerciseResolver.swift` | 187 | **Delete** | 187 lines, a full suite, zero callers — open since before this |
| `PlanDocumentNaming.swift` | 80 | **Keep** | Two callers — `PlanImporter.swift:121` and `WritePlanTool.swift:92`. The document keeps `displayName` even though the store drops it |

### `Documents/` — 13 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `DocumentCoding.swift` | 41 | **Keep** | |
| `DocumentRefusal.swift` | 222 | **Keep** | Gains the anchored-edit refusal |
| `IntensityTarget.swift` | 82 | **Keep** | |
| `PlanDocument.swift` | 300 | **Rewrite** | v6: no routine id, block ordinals |
| `PlanDocumentDay.swift` | 284 | **Rewrite** | Typed targets, `isWarmup` |
| `PlanDocumentGroup.swift` | 137 | **Keep** | Nesting is unchanged; the store flattens it |
| `ProfileFacts.swift` | 124 | **Delete** | |
| `ProfileUpdate.swift` | 228 | **Delete** | |
| `ProfileUpdate+Coding.swift` | 226 | **Delete** | |
| `SetPrescription.swift` | 121 | **Rewrite** | Typed target, `isWarmup`, no notes |
| `SnapshotRoutine.swift` | 213 | **Rewrite** | Follows the new tables |
| `StatedValue.swift` | 57 | **Delete** | Dies with `ProfileUpdate` |
| `TrainingSnapshot.swift` | 295 | **Rewrite** | v6: no profile, carries `exportedAt` |

Keep 4 · Rewrite 5 · Delete 4

### `Transport/` — 1 file

`DocumentTransport.swift` (165) — **Rewrite.** Carries two markdown files and an
archive directory it does not know about today.

---

## `LiftingMCP/`

### Server — 7 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `ContextReport.swift` | 288 | **Rewrite** | No profile section; points at the markdown |
| `JSONValue.swift` | 281 | **Keep** | |
| `LifterFacts.swift` | 146 | **Delete** | Exists to enumerate profile fields |
| `MCPServer.swift` | 241 | **Keep** | |
| `ServerConfiguration.swift` | 112 | **Rewrite** | Two more paths |
| `TrainingDocuments.swift` | 72 | **Rewrite** | Reads and writes markdown too |
| `TrainingLog.swift` | 249 | **Rewrite** | Per performance, not flat |

### Tools — 14 files

| File | Lines | Verdict | Why |
|---|---|---|---|
| `ListExercisesTool.swift` | 125 | **Rewrite** | Stops subtracting the avoid lists; flags instead |
| `LogReportTools.swift` | 250 | **Rewrite** | `exercise_history` reports per performance |
| `ProfileArguments.swift` | 216 | **Delete** | |
| `ProfileArguments+Facts.swift` | 194 | **Delete** | |
| `ToolCatalog.swift` | 282 | **Rewrite** | |
| `ToolCatalog+WritePlan.swift` | 248 | **Rewrite** | |
| `ToolRunner.swift` | 179 | **Keep** | |
| `ToolSchema.swift` | 95 | **Keep** | |
| `UnstatedFactsTool.swift` | 85 | **Delete** | Reports empty profile fields |
| `UpdateProfileTool.swift` | 203 | **Delete** | Replaced by editing a file |
| `VolumeTool.swift` | 148 | **Rewrite** | Light |
| `VolumeTotals.swift` | 148 | **Keep** | |
| `WritePlanTool.swift` | 337 | **Rewrite** | |
| `WritePlanTool+Report.swift` | 172 | **Rewrite** | Its unstated-facts half goes |
| **new** `UpdateNotesTool.swift` | — | **Add** | Anchored edit, versioned copy, append-only dated facts |

`LiftingMCPTool.swift` (82) — **Keep.**

---

## Tests — 98 files

A test dies with the thing it tests. These are grouped by fate rather than
listed individually; each maps to a source verdict above.

**Delete outright (20).** `AccountRecordTests`, `ProfileFactsApplyTests`,
`ProfileUpdaterTests`, `RoutineFactsTests`, `StatedFactsTests`,
`StoreUpgradeTests`, `OpenRoutineTests`, `LifterDataTests`,
`EquipmentAccessTests`, `ExerciseResolverTests`, `ProfileFactsTests`,
`ProfileUpdateTests`, `RoutineCalendarTests`, `ProfileFactsToolTests`,
`UnstatedFactsTests`, `UpdateProfileTests`, `NulledSeriesTests`,
`SessionPhrasingTests` (weekday half), `BlockSelectionTests` (deload half),
`RestPreferenceTests` is **kept**, not deleted.

**Rewrite (roughly 45).** Everything touching the store shape, the plan
document, the snapshot, prescriptions, supersets or the log — including all four
`Superset*Tests`, `PlanDocument*`, `Snapshot*`, `SetRowPrescriptionTests`,
`WorkPrescriptionHintTests`, `SessionOrderTests`, `PlanImporterTests`,
`RoutineBlueprintMappingTests`, `LogReportTests`, `WritePlanTests`,
`ContextResourceTests`, `ListExercisesTests`, `VolumeTests`.

**Keep (roughly 33).** The pure-value suites the rebuild does not touch:
`MassTests`, `TaxonomyTests`, `TargetUnitsTests`, `WorkDistanceTests`,
`WorkDurationTests`, `RepRangeTests`, `CatalogIntegrityTests`,
`ExerciseDecodingTests`, `DocumentCodingTests`, `DocumentTransportTests`,
`MCPServerTests`, `ServerConfigurationTests`, `NumberFormattingTests`,
`SetFieldLabelTests`, `SetEntryTests`, `DesignSystemTests`,
`PersistenceErrorTests`, `RefusalMessageTests`, `SessionIconTests`,
`SessionClockTests`, and the rest-timer suites.

**New suites owed.** The typed `Target` parse-and-refuse. Every prescribed set
as a row. The export firing on Finish. The anchored markdown edit refusing a
missing anchor. And the one the queue has asked for and never got: a three-block,
three-session store exported whole, asserting all nine survive.

---

## The revision pass — cleanest, not least invasive

Jon, after the first draft: *"we are optimizing for best and cleanest final
build not minimum invasive change."* He was right that several verdicts were
inertia. What changed on 2026-08-21:

**The seven prescription types in `Presentation/` become two.** 493 lines, and
**four of the seven have exactly one caller**. They exist because a prescription
arrives as an untyped string and each infers something from it — `WorkPrescription`
(106 lines, 7 callers) exists *entirely* to answer which of reps, a hold or a
carry an exercise records. The typed `Target` answers that from storage, so the
inference has nothing left to do. `PrescriptionSummary` and `SetRowPrescription`
survive; the other five go.

**Files for one job, merged.** `ExerciseTrend` folds into `PerformanceHistory` —
`PerformedExercise` *is* the reduction both were doing. `DayBlueprint` folds into
`RoutineBlueprint`, and both were then deleted outright once it turned out the
blueprint was built and read inside `PlanImporter` and crossed no boundary at all.

**One merge in this pass was wrong, and reading the file is what said so.**
`UbiquitousDocumentWatcher` was to fold into `DocumentInbox`. It is
`NSMetadataQuery` plumbing and the inbox is refusal handling; merging them makes
a 420-line file doing two jobs. **A line count is evidence that something might
be wrong, never that it is** — and this pass was argued from line counts.

**`Style.swift` splits, and CLAUDE.md changes with it.** 512 lines and nine
declarations — `Palette`, a `UIColor` extension, a `Font` extension, `Spacing`,
`Radius`, `TapTarget`, `SetTableMetrics`, `ProgressMetrics`, `PanelMetrics`. The
last three are *component* constants wearing a token file's clothes, and
`SetTableMetrics.entryColumnWidth` — the number behind two defects this week —
sits 400 lines from the row that reads it. It becomes:

| New file | Holds |
|---|---|
| `Palette.swift` | every colour, and the `UIColor` bridge |
| `Typography.swift` | the type roles |
| `Layout.swift` | `Spacing`, `Radius`, `TapTarget` |

and `SetTableMetrics`, `ProgressMetrics` and `PanelMetrics` move next to the
components that own them.

CLAUDE.md currently states *"Every colour, gap, radius and type role lives in
Style.swift."* The split keeps the intent — one place, never scattered through
views — and breaks the letter, so that line is rewritten **when the split lands,
not before**; editing it now would describe a build that does not exist. Jon's
ruling on the standard: *"the claude.md is not hard boundaries if you think its
in the best interest to change something you can just do it for a good reason."*

**Four test suites exist twice.** `CarriedWorkTests`, `TimedWorkTests` and
`PerSetPrescriptionTests` each appear in both `LiftingPlanTests` and
`LiftingMCPKitTests`; `DocumentTransportTests` in both `LiftingKitTests` and
`LiftingPlanTests`. Each pair collapses to one, in the package that owns the
behaviour.

---

## Tallies

| | Keep | Rewrite | Delete | Read | Add |
|---|---|---|---|---|---|
| App | 28 | 37 | 24 | 0 | 2 |
| LiftingKit | 13 | 12 | 7 | 0 | 1 |
| LiftingMCP | 6 | 11 | 5 | 0 | 1 |
| **Source total** | **47** | **60** | **36** | **0** | **4** |

**36 files delete outright.** Roughly 5,400 lines of source and a further 3,000
of tests, none of which anything will read.

---

## Before code is written

**The three unclassified files were read on 2026-08-21, and all three keep.**
`RestPreferences` is already exactly the design the rebuild wanted — `UserDefaults`,
keyed by `ExerciseID`, on this device only, with a doc comment noting that it
*cannot* reach `SnapshotExporter`, so the guarantee is structural rather than
remembered. The app-wide `isClockOn` lives there already, and the per-exercise
*length* override is the lifter's own choice, which CLAUDE.md keeps. Its sheet
touches `LifterRest` and `RestPrescription` and never the store.
`PlanDocumentNaming` has two real callers, `PlanImporter.swift:121` and
`WritePlanTool.swift:92` — the first grep missed them because the entry point is
`.named(using:)` rather than the type's name, which is worth remembering: a
grep for a type does not find its extension methods.

**One design consequence.** Dropping `displayName` from the *store* does not
drop it from the *document*: the coach may state a name, `PlanDocumentNaming`
fills in the rest from the catalog at both ends, and the app resolves what it
draws from the catalog. Those are three different things and only the middle one
was ever a stored column.

**Six schema questions are answered** in `decided.md`; none block the start.

**The order that makes sense.** Domain and documents first — `Target`, the plan
document, the snapshot — because the store, the app and the server all depend on
them and nothing depends on those three. Then the store, then services, then the
server, then the screens. Tests lead each step, as they do now.
