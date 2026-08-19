# Decided

Things that are settled, and things that were tried and killed. Read this before
proposing anything on it.

**Why this file exists.** A long session gets compacted: what was decided
survives, why it felt right does not. The predictable failure is not forgetting
— it is confidently re-proposing something already rejected, with fresh
enthusiasm and no memory of the reason. Commit messages record what was built.
This records what was *not*, which is the half that otherwise disappears.

Add to it when something is rejected for a reason that would not be obvious to
someone arriving cold. Delete from it when a rejection genuinely stops holding —
but say so, rather than quietly re-adding the thing.

---

## Settled

| Decision | Why |
|---|---|
| The app is a datastore and the interface an AI trainer works through | Everything that is neither is bloat. This is the filter for any proposal. |
| The app makes no training decisions and asks the lifter nothing | Claude decides; the app records. No form, no default that asserts something nobody said. |
| Blocks → a block → the session, and the app opens in the middle | The top of the tree costs a tap before every session; the bottom could show what was left of the week but never what was coming. The block page is the only place that is one tap from training and still shows the block. Supersedes *one screen: the session he is in*, and the swipeable pager that replaced it. |
| The session is a sheet with an X; everything else is a stack with a back arrow | A session is entered, done and left. Leaving it puts him back where he chose it, with that day marked. |
| No tab bar | Two of three tabs were opened roughly never and cost ~90pt of every screen. Account is behind a person icon on the two list pages, and absent from the session. |
| One panel per thing being chosen | A panel holding every session of a week made a week one object with three names in it; the same was true of a panel holding every block. |
| No calendar, and no date on anything he is training | `PlanImporter` takes the start date from when the file arrived, so a date on the block he is *on* would be dressing an arrival up as a plan. A block behind him is dated — that is the honest thing to say about a block there is nothing left to do in — and the block he is training says which week he is on instead. |
| Sessions are trained in the block's order, and the record says when | Removes the question of what happens when Tuesday's session is trained on Wednesday. |
| Finish greys and asks while sets are unticked, but is never disabled | Whether he is finished is his to say. Refusing to record three good sets because the plan wrote four would be the app deciding. |
| The session clock runs from the first ticked set to the last | Both ends are facts the record already holds, so it survives closing, backgrounding and syncing with nothing new stored — and it does not run overnight on a session left open. It states hours when there are hours. |
| An icon names an action a word will not fit, or marks a state that varies — nothing else | And a varying icon varies along **one axis**. SF Symbols only; see *Standards* in `CLAUDE.md`. |
| The app is called Superset; the bundle id and iCloud container are not | `com.jonluongo.LiftingPlan` and `iCloud.com.jonluongo.LiftingPlan` stay. Renaming either makes this a different app to iOS, with an empty store and no way back to what is on the phone. `AppIdentityTests` guards all three. |
| Every number lives in `Style.swift` | A number written in a view is a number nobody chose. |
| `Views/` holds only SwiftUI; pure model→string logic is `Presentation/` | Mechanical test, no judgement: if it does not import SwiftUI, it is not a view. |

## Tried and killed

| Rejected | What happened |
|---|---|
| A week strip / calendar on Home | Rested on an invented start date and showed intent where the log records fact. `WeekStrip` and the screen that drew it are gone. **`BlockCalendar` and `PlanWeekSelection` are not** — the first dates a block for the list, the second names a week and answers which week he is on. This row said all three had gone, which would have had a later session deleting live code. |
| `Finish` in the top-right corner | That is where iOS puts *dismiss*. It was pressed as a way out and marked an untouched session as trained. |
| A green Finish button | Green marks what the record holds — a ticked set, a logged session. The button is the act that creates that, not the fact. It also put a second saturated colour in a one-accent palette. |
| `Done` buttons on sheets | The platform dismisses sheets already; the button was chrome for an existing behaviour. All sheets use the grabber. |
| A large navigation title on the root | It stood permanently large on the screen it was meant to collapse on, and a large title on the root against a small centred one a tap deeper is the app changing what a header looks like as you move through it. Both pages are inline. (The pager it could not collapse over is itself gone.) |
| Panels at 6pt radius | Cutting the radius made them *sharper*, not quieter. The problem was circular arcs, not the number. They are 12pt `.continuous`. |
| A `PREVIOUS` column | A quarter of the table's width reporting a figure he was about to type over, and a column of dashes on a first session. It is the field's placeholder now. |
| `SET · PREVIOUS · LB · REPS · ✓` column headers | Redrawn above every exercise, telling a lifter who has used this once what he already knows. The `×` carries it. |
| `lb` in the session header | He knows his own unit and it never changes silently. Account states it where it is set. |
| The "Demonstration coming soon" well | The largest element on the exercise screen, promising a feature that does not exist. It returns when there is an animation for it. |
| Explaining empty states twice | Every empty state had two headings and led with the emptier. The title states it; the body says only what the title cannot. |
| Sentences under buttons explaining the button | "Records this session as trained…" under a control labelled **Finish Workout**. Scar tissue from a bug fixed by moving the button. |
| `Superset A` / `A1` / `A2` / `ROUND n` | A code plus the glossary that decodes it. A group is drawn as its movements, each with the header and table an ungrouped exercise gets. |
| Stretching card rows to fill a fixed height | Fixed the emptiness by inflating the content, which is decoration pretending to be design. |
| RPE shown as `RPE 8` | Jargon. `80% effort` is the same figure without it. Nothing maps an RPE onto a percentage of a maximum — that is a table lookup and a training claim. |
| VoiceOver as a dedicated pass | On the plan because it is on a checklist, which is the reasoning this project rejects everywhere else. One user, sighted. |
| An exercise `role` field | Claude prescribes a warm-up by prescribing it. A field so he can label it is a field nobody reads. |
| `Current` and `Earlier` headings on the blocks list | They named a standing the order already gives. What distinguishes the blocks is what the rows *say*: the one being trained reports where he is in it, a block behind him reports when it ran. |
| A dumbbell for the open block, a calendar for a closed one | Not two values of one thing — two subjects in one slot, so the change from one to the other read as noise rather than as information. Both went, and `IconCircleRow` with them. |
| Section *headers* | A plain `List` pins them: a week's name sat frozen over the days of a different week, claiming to describe what was passing beneath it. `SectionHeading` is the first row of its section. |
| A day row of name, count, minutes and two movement names | Three lines of grey wrapping unevenly, with the mark floating against the middle of them. The count said in a figure what the names say concretely. Name and mark on one line, movements on one line under them, truncated at the edge. |
| `GroupRounds` and the interleaved round table | A group is drawn as its movements, so the notation, the per-row prescription, the round a row belongs to and the warm-ups outside the rounds had no reader. One line survived — whether a round just closed, which starts the group's rest — and it lives on `ExerciseGroup`. |
| A right-aligned value that wraps | `Add size to my chest and back without losing / the squat`, the tail stranded against the right edge. `FactRow` offers the one-line arrangement first and the wrapping one when it does not fit. |

## Settled by investigation

**Supersets are expressible and always were.** Claude reported on 2026-08-18 that
"the plan format has no superset field. No grouping, no pairing." That is not
true of this repo: `PlanDocumentEntry` is an enum of exercise-or-group,
`ToolCatalog+WritePlan` documents `{"group": [ … ], "restSeconds": 90}` to him
explicitly, `SnapshotExerciseGroup` carries a logged group back, and
`SnapshotExporter` writes it. Probing the rebuilt server over stdio for
`tools/list` shows `write_plan` mentioning both *group* and *superset*. He was
talking to a binary built on 2026-08-17 at 17:17, before that work landed.
**Rebuild the server and restart the connection after changing LiftingKit or
LiftingMCP** — the client holds the old process otherwise, and the symptom is
Claude describing a format that no longer exists.

**The snapshot exporter drops nothing.** He also reported reading four sessions
of a nine-session block. `SnapshotExporter` maps `orderedWeeks → orderedDays →
exercises` with no filter, prefix or limit, and `SnapshotCompletenessTests` now
asserts a three-week block of three days survives whole, keeps its exercises,
and does not silently omit an empty week. A truncated snapshot is a stale
`snapshot.json`: the phone writes it, and a phone that has not opened the app
since the block changed has not rewritten it.

## Settled by asking

These were put to the owner as two defensible designs and answered. They are his,
not the assistant's, and re-opening them is churn.

| Question | His answer |
|---|---|
| Where the `SUPERSET` label sits | Above the movement's name, on its own line, with the `⋯` on the title line as on every other card. |
| A long fact that wraps | Wraps left-aligned under the label; short values stay right-aligned, so the column of figures still reads down the page. |
| What replaces the blocks list's headings | Nothing — the rows say where he is instead. |
| What a session clock does overnight | Stops at the last ticked set. It advances as sets are ticked rather than by the clock on the wall. |

## Calibration

Across a long day of building this, one pattern held without exception: **the
owner's defect calls were right and the assistant's aesthetic calls mostly were
not.** Bugs he pointed at were real bugs. Designs proposed unprompted were
overruled far more often than not.

What follows from it: fix what is broken freely, and stop and ask on anything
that is merely a defensible taste call. Two designs that both work is his choice,
not a gap to fill.

The second pattern, four times over: **a change made where the assistant was
looking and not where its siblings were** — panel insets applied to two callers
of five, a completed-row background left on the group table after deletion from
the exercise table, a `Done` button left on one sheet of three. Rendering the
screen being worked on is not verification. See *Verification* in `CLAUDE.md`.
