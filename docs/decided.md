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
| One screen: the session he is in | Home and the logging sheet were the same session drawn twice. A set row with an empty field *is* the preview. |
| No tab bar | Two of three tabs were opened roughly never and cost ~90pt of every screen. Blocks and Account live behind the `⋯`. |
| No calendar, no start date shown | `PlanImporter` invents the start date from when the file arrived. The calendar showed intent; the log records fact, and Claude reads the log. |
| Sessions are trained in the block's order, and the record says when | Removes the question of what happens when Tuesday's session is trained on Wednesday. |
| Finish greys and asks while sets are unticked, but is never disabled | Whether he is finished is his to say. Refusing to record three good sets because the plan wrote four would be the app deciding. |
| The session clock counts from the first ticked set | A fact the record already holds, so it survives closing, backgrounding and syncing with nothing new stored. |
| Every number lives in `Style.swift` | A number written in a view is a number nobody chose. |
| `Views/` holds only SwiftUI; pure model→string logic is `Presentation/` | Mechanical test, no judgement: if it does not import SwiftUI, it is not a view. |

## Tried and killed

| Rejected | What happened |
|---|---|
| A week strip / calendar on Home | Rested on an invented start date and showed intent where the log records fact. Deleted with `BlockCalendar`, `WeekStrip`, `PlanWeekSelection`. |
| `Finish` in the top-right corner | That is where iOS puts *dismiss*. It was pressed as a way out and marked an untouched session as trained. |
| A green Finish button | Green marks what the record holds — a ticked set, a logged session. The button is the act that creates that, not the fact. It also put a second saturated colour in a one-accent palette. |
| `Done` buttons on sheets | The platform dismisses sheets already; the button was chrome for an existing behaviour. All sheets use the grabber. |
| A large navigation title on Home | It cannot collapse — the scrolling happens inside the pager, which the title does not sit on — so it stood permanently large. The title is drawn as content instead. |
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
