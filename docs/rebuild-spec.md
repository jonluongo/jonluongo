# The rebuild: formats and order

What `docs/decided.md` settles as a design, written out as the actual types,
keys and templates everything else compiles against. Read `decided.md` for the
reasoning and `rebuild-inventory.md` for the file-by-file verdicts; this
document is the contract between them.

Nothing here restates a decision. Where a choice is made *here* that was not
made there, it is marked **new**.

---

## 1. `Target` — the typed prescription

The defect this closes: a 40-metre sled push is stored today as the text `"40m"`
in a column named `repRange`, rescanned by `TargetUnits` at every read. The
record side has three typed fields and cannot confuse them; the prescription
side has one string that means whichever.

```swift
/// What one prescribed set asks for: a count, a hold, or a carry.
public enum Target: Codable, Equatable, Sendable {
    case repetitions(low: Int, high: Int?)
    case repetitionsToFailure                    // AMRAP
    case time(low: Int, high: Int?)              // seconds
    case distance(low: Double, high: Double?, unit: DistanceUnit)
}
```

**new, found while building** — `repetitionsToFailure`. Today `"AMRAP"` falls
through `WorkMeasure` to `.repetitions` with an empty range and is drawn
verbatim. A strictly typed target that refused it would take a prescription
coaches actually write out of the vocabulary, silently, in the name of type
safety. It is **not a fourth measure** — it reports `.repetitions` and is logged
in `reps`; it says what was asked for, not what it is measured in, so
`WorkMeasure` keeps its three cases and CLAUDE.md's rule about a fourth measure
is untouched.

Four cases, three measures, so a target cannot claim to be two things.
`high == nil` is a single value rather than a range — `40 metres`, not
`40–40 metres`. `measure` is derived, never stored beside it.

**It decodes from either form and encodes only the first.**

```json
{ "measure": "reps",     "low": 8,  "high": 12 }
{ "measure": "seconds",  "low": 45 }
{ "measure": "distance", "low": 40, "unit": "m" }
```

```json
"8-12"    "45s"    "40m"
```

**new** — the shorthand is accepted at *decode*, not at read. A hand-written
plan and a plan the server wrote both work, `TargetUnits` runs exactly once per
document, and the store only ever holds the typed form. Shorthand that cannot be
read is refused with the string quoted and the three forms named — it is never
stored as text and re-guessed later.

`RepRange`, `WorkDuration` and `WorkDistance` fold into this. `TargetUnits`
survives as its parser and moves under it.

---

## 2. `plan.json` — version 6

```json
{
  "version": 6,
  "id": "5C2B…",
  "catalogVersion": 3,
  "generatedAt": "2026-08-21T10:00:00Z",
  "sessions": [
    {
      "blockOrdinal": 1,
      "ordinal": 1,
      "focus": "Push",
      "icon": "push",
      "entries": [
        {
          "exerciseID": "barbell-bench-press",
          "displayName": "Barbell Bench Press",
          "restSeconds": 180,
          "coachNote": "Three down, explode up. Last set to a hard 8.",
          "sets": [
            { "isWarmup": true,
              "load": { "value": 135, "unit": "lb" },
              "target": { "measure": "reps", "low": 5 } },
            { "load": { "value": 185, "unit": "lb" },
              "target": { "measure": "reps", "low": 5, "high": 6 },
              "intensity": { "scale": "rpe", "value": 8 } }
          ]
        },
        {
          "group": {
            "restSeconds": 180,
            "exercises": [ { "exerciseID": "…", "sets": [ … ] } ]
          }
        }
      ]
    }
  ]
}
```

**Gone from version 5:** `routineID`, `title`, `goal`, `notes`,
`durationMinutes`, the `blocks` wrapper, `weekday`, `isDeload`, `tempo`,
`targetSets`, exercise-level `repRange`, and per-set `notes`.

**Added:** `sessions` at the top level, each carrying its own `blockOrdinal`;
`isWarmup` and a typed `target` on every set; every prescribed set stated
explicitly, so there are no exercise-level defaults to override.

**Merge keys on `blockOrdinal`.** A document restating a block nothing has been
logged against rewrites it whole. One with any performed set in it is refused by
ordinal, nothing taken in. `id` is kept for dedupe and names the archived copy.

**A group states its rest once.** The importer distributes it — members get `0`
except the last, which takes the group's — and reconstruction reads it back off
the last member. The one asymmetry, named rather than hidden: the store can
express a rest between members that the document cannot.

---

## 3. `snapshot.json` — version 6

```json
{
  "version": 6,
  "exportedAt": "2026-08-21T18:04:00Z",
  "catalogVersion": 3,
  "sessions": [ … exactly as plan.json states them, plus "finishedAt" … ],
  "performances": [
    {
      "exerciseID": "barbell-bench-press",
      "occurredAt": "2026-08-19T17:22:00Z",
      "source": "logged",
      "blockOrdinal": 1,
      "sessionOrdinal": 1,
      "lifterNote": "Shoulder fine today.",
      "sets": [
        { "setIndex": 1, "isWarmup": false,
          "load": { "value": 185, "unit": "lb" }, "reps": 5,
          "completedAt": "2026-08-19T17:24:00Z" }
      ]
    }
  ]
}
```

**Gone:** the whole `profile` object, and with it `statedAt`, `bodyweight`,
`baselines`, `equipment`, both avoid lists, `goal`, `experience`,
`constraints`, `preferredDurationMinutes`, `displayUnit`.

**`performances` is flat**, each carrying its coordinates. A stated baseline is
a performance with `source: "stated"` and one set. `exportedAt` is what every
tool reports so a stale read is visible.

The prescription is stated once, in the same shape the plan document uses.
`PlanDocument(reconstructing:)` is what produces it, so the round-trip suite is
what proves the store holds everything the document said.

---

## 4. The markdown files

**new** — templates, because an empty file gives an anchored edit nothing to
anchor to. Every `##` heading is a stable anchor; the coach edits beneath one.

`user.md`

```markdown
# The lifter

## Objective
_Not yet stated._

## Background
_Not yet stated._

## Injuries and limits
_None on record._

## What he avoids, and why
_Nothing on record._

## Equipment
_Not yet stated._

## Bodyweight
_No readings on record._
```

`program.md`

```markdown
# This programme

## The approach
_Not yet stated._

## What is being progressed
_Not yet stated._

## What to watch
_Not yet stated._
```

**The last two sections of `user.md` are append-only.** A weigh-in or an injury
is added as a dated line — `2026-08-14 · 218 lb` — never by replacing what is
there. Everything else is edited in place.

**The app renders these and never parses them.** No inbox, no document type, no
refusal, because nothing is read out. The moment a number must come out of
prose, that number belongs in a table.

---

## 5. Tools

| Tool | Change |
|---|---|
| `write_plan` | Writes the v6 document. Accepts shorthand targets and normalises. Loses every profile-shaped argument. |
| `list_exercises` | **Returns the catalog, full stop.** The avoid lists are prose now, so there is nothing left to subtract *or* flag. |
| `exercise_history` | Reports **per performance** — a series of sessions each holding its sets, with the prescription beside them — instead of a flat array with the context restated on every row. |
| `recent_sessions` | Follows the new shape. |
| `volume_by_muscle` | Unchanged in kind. |
| `update_notes` | **new.** `{ file, old_text, new_text }`. Refuses whole if the anchor is missing or matches more than once. Copies the file to `notes/<file>.<timestamp>.md` first. Appends rather than replaces under the two append-only headings. |
| `update_profile` | Deleted. |
| `unstated_facts` | Deleted. |

**Resources:** `user.md`, `program.md`, and the context report — which loses its
profile section and gains a pointer to the two files.

---

## 6. The shared container

| File | Written by | Read by |
|---|---|---|
| `snapshot.json` | phone | server |
| `plan.json` | server | phone |
| `plans/<id>.json` | phone, on import | the archive |
| `user.md`, `program.md` | server | phone, rendered |
| `notes/<file>.<timestamp>.md` | server, before each edit | the versions |

**new — the two markdown files are mirrored, not read live.** The app keeps a
local copy and treats the container as the sync channel, exactly as it does for
the store. Reading them straight from the container would make the account
screen blank whenever iCloud is unreachable — which it currently is, with 101 KB
free and no Mac bundle claiming the container. The screen must work on a phone
with no iCloud at all.

**Export fires on Finish, debounced after any logged set, and on backgrounding
under a background-task assertion.** Today it fires only on backgrounding and
after an inbound document, with seconds to resolve a container its own doc
comment says can block for seconds.

---

## 7. Order of work

Each phase ends green: all three suites and both `-warnings-as-errors` builds.
The app does not compile between phases 1 and 3; that is expected and is why
this is a branch.

**Phase 1 — Domain.** `Target` and its parser. Delete `EquipmentAccess`,
`RoutineCalendar`, `RoutineSchedule`; strip `Weekday` and `ExperienceLevel` from
`TrainingEnums`. Tests lead: the parse-and-refuse suite is the highest-value one
in the rebuild.

**Phase 2 — Documents.** `PlanDocument` v6, `TrainingSnapshot` v6,
`SetPrescription`, `SnapshotRoutine`, the new refusal cases, transport paths.
Delete the four profile-document files. The round-trip suite is the gate.

**Phase 3 — Store.** Five models, new names, `StoreContainer`. Nothing migrates;
the store resets.

**Phase 4 — Services.** Importer and blueprint, exporter, outbox with three
triggers, session log, grouping, order, history. Delete seeding, the profile
updater, stated facts, store upgrade, the watcher, `DayBlueprint`,
`ExerciseTrend`.

**Phase 5 — Server.** Tools, `update_notes`, the context report. Rebuild the
release binary.

**Phase 6 — Presentation and Views.** Seven prescription types to two, the
`Style.swift` split, `HomeView`, `BlockView`, the two markdown screens. CLAUDE.md's
line about `Style.swift` is rewritten here, when it stops being true.

**Held for Jon, not blocking:** the set-row layout call, which lands in phase 6
and would otherwise rebuild a known defect deliberately.
