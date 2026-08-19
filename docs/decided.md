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

## The vocabulary

Renamed on 2026-08-19, on Jon's call. **A routine is the whole thing Claude
writes; a block is a phase within it; a session is a day's work.** What the list
used to call a block is a routine, and what the routine's page used to call a
week is a block — which is the vernacular a lifter already uses, since those
phases were already named *Accumulation* and *Deload*.

**The stored types keep their old names, and that is deliberate.**
`TrainingPlan` and `TrainingWeek` are SwiftData `@Model` classes mirrored into
CloudKit, and CloudKit derives its record types from the entity name. Renaming
them would leave every logged set in the container under a record type the app no
longer asks for — the store would open empty with the data still sitting there.
It is the same hazard that keeps `com.jonluongo.LiftingPlan` as the bundle
identifier, and it is refused for the same reason. The mapping, for anyone
reading `Store/`:

| Stored type | What it is called |
|---|---|
| `TrainingPlan` | a routine |
| `TrainingWeek` | a block |
| `WorkoutDay` | a session |

The wire keys follow the store rather than the vocabulary for the same reason: a
`weeks` key that Claude already writes is not worth a format version to rename.

## Held open — finish the rename

Two pieces of the routine/block rename are deliberately unfinished. They are not
forgotten and they are not settled; they are waiting on a condition.

**1. The two `@Model` class names.** `TrainingPlan` should be `Routine` and
`TrainingWeek` should be `Block`. SwiftData derives the CloudKit record type from
the entity name, so renaming either leaves every set already synced under a
record type the app no longer asks for: the store opens empty with the data
still in the container, and no error is raised.

*What it needs:* a `VersionedSchema` for the current shape, a second for the
renamed one, a `SchemaMigrationPlan` with a stage that carries the rows across,
and a test that opens a store written under the old schema and finds the logged
sets intact. **Verify against the real phone, not a fixture** — the failure mode
is CloudKit's, and an in-memory container cannot show it.

**2. The `weeks` key in `plan.json` and `snapshot.json`.** Under the vocabulary
it should be `blocks`. Both formats are versioned, so the mechanism exists:
bump `PlanDocument.currentVersion`, accept `weeks` from any earlier version and
`blocks` from the new one, and refuse a newer version whole as both readers
already do.

*What it needs:* the version bump, the reader's two-key path, wire tests for
both spellings, and the MCP schema and tool description updated in the same
commit — Claude writes that key, so the server and the phone must not disagree
about it for even one build.

*Do them in that order.* The store rename is the one with data behind it.

## Settled

| Decision | Why |
|---|---|
| The app is a datastore and the interface an AI trainer works through | Everything that is neither is bloat. This is the filter for any proposal. |
| The app makes no training decisions and asks the lifter nothing | Claude decides; the app records. No form, no default that asserts something nobody said. |
| Blocks → a block → the session, and the app opens in the middle | The top of the tree costs a tap before every session; the bottom could show what was left of the week but never what was coming. The block page is the only place that is one tap from training and still shows the block. Supersedes *one screen: the session he is in*, and the swipeable pager that replaced it. |
| The session is a sheet with an X; everything else is a stack with a back arrow | A session is entered, done and left. Leaving it puts him back where he chose it, with that day marked. |
| No tab bar | Two of three tabs were opened roughly never and cost ~90pt of every screen. Account is behind a person icon on the blocks list — the screen it belongs to, since it is about the lifter — and nowhere else. |
| The block page's trailing mark is `info.circle`, not Account | What a block is *for* is the question that screen raises. Account is about the lifter, not about the block he is reading. |
| What a block is for lives behind that mark, not above the weeks | The goal and the coach's note opened the screen, where they were read once and scrolled past on every visit after. `RoutineInfoSheet` holds them and the routine's shape — weeks, sessions, logged, training days, session length — and states no verdict on whether he is on schedule, because that is a training judgement. |
| A block's information and a movement's are one screen, `InfoSheet` | Same surface, same inline title, same grabber, same `info.circle` to reach them. They are the same question — *tell me about this* — and were two designs answering it. |
| Every sheet is inline-titled | Account carried a large title beside two inline ones, so which top a sheet had depended on which sheet you opened. The same fault the root and the block page were corrected for. |
| An exercise whose sets are all ticked takes the recorded ground | The same `Palette.recordedPanel` a logged session takes, so a movement finished reads as finished from across the screen. An exercise with no rows is not finished — there is nothing to have done. |
| One panel per thing being chosen | A panel holding every session of a week made a week one object with three names in it; the same was true of a panel holding every block. |
| No calendar, and no date on anything he is training | `PlanImporter` takes the start date from when the file arrived, so a date on the block he is *on* would be dressing an arrival up as a plan. A block behind him is dated — that is the honest thing to say about a block there is nothing left to do in — and the block he is training says which week he is on instead. |
| Sessions are trained in the block's order, and the record says when | Removes the question of what happens when Tuesday's session is trained on Wednesday. |
| Finish greys and asks while sets are unticked, but is never disabled | Whether he is finished is his to say. Refusing to record three good sets because the plan wrote four would be the app deciding. |
| The session clock counts live from the first ticked set and stops at Finish | The start is a fact the record holds, so it survives closing, backgrounding and syncing with nothing new stored. It states hours in `h:mm:ss` when there are hours. **Freezing it at the last ticked set instead was tried and reversed** — see below. |
| Every panel that opens something draws `DisclosureChevron` | The app's mark, not the presentation's: a `NavigationLink` gets one from the system and a `Button` presenting a sheet does not, which is how two lists one screen apart came to speak differently. |
| A panel that acts as a button is tappable across the whole panel | The band between the content's inset and the panel's edge is painted by the row's background; without `fillsPanel` it is dead, and a panel that looks like a button and ignores a third of itself is worse than one that looks inert. |
| A logged session tints its whole panel | `Palette.recordedPanel`, with the check kept beside it. A 24pt mark alone made a list of sessions read as identical panels with a small green square somewhere on the right. Colour never carries it alone. |
| A block states how far through it is, as a rule under the line | `ProgressRule` draws the fraction the words already give — `3 of 12 logged` — and adds no target, no pace and no verdict on whether that is enough by now, because that is a training judgement. A block prescribing nothing draws no track rather than an empty one. |
| Blocks are never tinted by completion | `completedAt` on a block means a later plan superseded it, not that he finished it. Green there would claim what the record cannot know. |
| Panels are 20pt `.continuous`, and there are two radii, not four | A panel painted into the surface wants a tight corner or it reads as a bubble — twelve was right then. A panel that *sits* on the surface wants a rounder one, and once it did, the rest bar's radius and the panel's were the same number, so the bar takes the panel's. The `small` 8 went the same way for the opposite reason: nothing ever drew with it, since the entry fields are ruled rather than boxed. Two names for one number is what the design-system suite exists to catch, and so is a name for no number at all. |
| Panels cast a shadow in light and none in dark, and only when the panel is one row | A black blur on a near-black surface is invisible at any opacity worth drawing, so dark leans on the panel's lighter fill. A `List` gives every row its own background layer, so an interior row's blur lands *on* its neighbours — it banded every set table until the shadow was limited to single-row panels. |
| A week he has not reached recedes, and still opens | Muted heading and names, flat panel. Nothing is gated: the app may never refuse to record a session he actually trained, which is the same reason Finish greys and asks but is never disabled. The week he is on is the earliest still holding an unfinished session, read from the record rather than the calendar. |
| The app derives no dates for the block he is training, and the code that could is gone | The week he is on is read off the record — the earliest still holding an unfinished session — and a session trained on Wednesday that was written for Tuesday is still that session. `RoutineCalendar.today(in:on:)`, `TodayInRoutine`, `BlockDay`, `WeekPlacement`, `SessionProgress` and `RoutineToday` answered *where does today fall* for a front door that was deleted; ~600 lines went with it. What survives is `span(of:)`, which dates a block behind him — the one date the app still states. |
| A toolbar glyph is a bare mark, since the toolbar draws the circle | `info`, not `info.circle`, beside a bare `chevron.left`: a circular symbol inside a circular button reads as a ring in a ring, so the two buttons looked different sizes when only the glyphs differed. |
| Claude can write a free-form note on any exercise, and it already works | `PlanDocumentExercise.notes` → `PlannedExercise.notes` → drawn at the **foot** of the panel, closing it, in muted support type. Optional, unstructured, absent when he writes none. There is a per-*set* note beside it — `SetPrescription.notes`, for "last set to failure" — and a note on the block itself. Asked for on 2026-08-19 and found already built, end to end. |
| An optional element sits where its absence costs the panel no shape | Jon: *"the note should be at the bottom that way it doesn't change the panel format since its optional."* Between the name and the table the note was in the place it belongs — it is about the movement — but it pushed the sets down on the exercises that had one, so two panels in a session had their first row at different heights. |
| A panel's edge spacing is the panel's and the row's, never a third thing's | Three paddings were stacking at the top of an exercise panel — `closing`, the row's inset, and one `CardHeaderRow` added — putting thirty points above the name against twelve below the last row. The header adds none now, except four points for the superset eyebrow, whose smaller line box carries less clearance than a title's. |
| Ticking a set inside a group brings the next movement's set into view | A superset is trained *across* its movements and drawn *down* them, so the next thing to do sits on a panel the lifter cannot see. The order comes from the grouping the plan prescribed, never from an opinion: `ExerciseGroup.setAfter` answers "what is next" and a group with nothing waiting leaves him where he is. Taking a set back scrolls nowhere — that is correcting the record, not asking what is next. An ungrouped exercise moves nothing: its next set is the row below. |
| A group's movements each get their own panel | The rule down their edge and the word above their names is what says they are one thing. Sharing a panel with no gap was tried on the reasoning that two things lacking the gap everything else has must be one — rendered, it read as three separate exercises rather than a pair. **A signal has to be present, not withheld.** |
| A session's mark is Claude's, chosen from a set the app publishes | The app owns the pile and refuses anything outside it; he picks. Deriving it from the day's name or from its exercises would both be the app deciding what a session is about. A day he marked nothing carries nothing — there is no default. |
| An icon names an action a word will not fit, marks a state that varies, or is a mark Claude chose — nothing else | And a varying icon varies along **one axis**. SF Symbols only; see *Standards* in `CLAUDE.md`. |
| The app is called Superset; the bundle id and iCloud container are not | `com.jonluongo.LiftingPlan` and `iCloud.com.jonluongo.LiftingPlan` stay. Renaming either makes this a different app to iOS, with an empty store and no way back to what is on the phone. `AppIdentityTests` guards all three. |
| Every number lives in `Style.swift` | A number written in a view is a number nobody chose. |
| `Views/` holds only SwiftUI; pure model→string logic is `Presentation/` | Mechanical test, no judgement: if it does not import SwiftUI, it is not a view. |
| A stated fact is one type, `StatedFact`, wherever it is stated | The lifter's record, a movement's catalog entry and a routine's shape all draw through `FactRow`, and each had built its own two-string struct — one of the doc comments had already drifted into calling itself the opposite of another that read identically. `AccountRecord`, `ExerciseAbout` and `RoutineFacts` return the one type. |
| An empty work field hints the figure, not the prescription's wording | The row draws `s` or `m` after the field, so `45 seconds` said the unit twice and, in three figures of width, said it as `45 sec…`. `WorkPrescription.targetFigure` reads through `WorkDuration` and `WorkDistance` — never by trimming words — so `1:30` hints `90` and it cannot disagree with the readers that decided the row is a hold. A counted row is untouched: the `×` is its unit. |

## Tried and killed

| Rejected | What happened |
|---|---|
| A week strip / calendar on Home | Rested on an invented start date and showed intent where the log records fact. `WeekStrip` and the screen that drew it are gone. **`RoutineCalendar` and `BlockSelection` are not** — the first dates a routine for the list, the second names a block and answers which one he is on. This row said all three had gone, which would have had a later session deleting live code. |
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
| A day row of name, count, minutes and movement names | It began as three lines of grey wrapping unevenly with the mark floating against the middle of them; the count went first, and then the movements too — they crowded the check and the chevron and truncated before finishing the second name. The row is the session's name and its two marks. What is in it is one tap away, in full. |
| Removing the chevron to make the two lists agree | The right instinct, the wrong direction — Jon: *"No i want the chevron just make it consistent."* Both rows draw one now. Consistency by addition where the mark is doing a job. |
| Freezing the session clock at the last ticked set | It fixed a session left open overnight reading `1429:59` and broke every ordinary session: the figure moved only when a set was ticked, which is a clock reporting the past rather than one you can train against. Live until Finish; the overnight case is answered by finishing. |
| The rest-timer master switch | A single toggle silencing every countdown was the coarse version of a choice that already exists per exercise, on the exercise it is about — and it was the last preference on a page whose premise is that the app asks nothing. Removed whole: the toggle, the stored flag, its defaults key, and the argument threaded through `LifterRest` and the rest sheet. |
| The movement's name on the rest bar | `Barbell Bench Press` arrived as `Barbell Benc…` beside the ring and three controls — a label naming nothing, in the one place the lifter already knows the answer. It is still carried by the screen-locked notification, where he is *not* looking at the bar and the name is the whole point. |
| Deriving a session's mark in-app | Jon: *"But thats hardcoded no? We want claude to generate the info."* Right — muscle groups computed from the catalog would have been the app claiming what a session is about. He chooses from a pile instead. |
| Giving a dead function a caller to keep it | `PrescriptionSummary.text` wrote a whole prescription as one line for a browsing screen; both such screens were deleted and it had no caller but its own thirteen tests. The tempting rescue was to list a day's exercises in the block's information sheet — which is building a feature to justify keeping code, the reasoning backwards, and what *nothing exists because apps have one* is there to stop. Deleted whole, with `TargetSpan` and five helpers that existed only to write it. If a browsing line ever returns, it returns with its caller. |
| Giving a block its own colour at all | Built whole and removed whole on 2026-08-19. `BlockTint` was a closed set of eight the app owned and Claude chose from — format key, store field, snapshot round-trip, refusals at both the server and the importer, tests. The panels wore it as a gradient with white type. Jon: *"lets just go back to white keep it simple."* With the panels white the type had no reader, so it went with them rather than lingering as a field nobody could explain. **The blocks list is white panels with ink type, and that is the decision, not a stop on the way to one.** |
| An animated panel behind a block | A `MeshGradient` of the block's colour, its interior points drifting on a fourteen-second cycle. Two things killed it, in this order: rendering caught edge control points drifting *off* their edge, which tore the fill past the panel's rounded corners; and measuring caught the cost — **10.6% of a core, sustained, for four rows on screen, against 0.0% for a static fill** at almost no visible difference. Motion for its own sake is battery spent on decoration, on a phone propped against a rack. |
| Abstract drawn marks in place of the system symbols | Prototyped and rendered side by side at row size, and they lost. The system figures *depict* something and differentiate cleanly — a barbell lifter, a dumbbell, a sit-up, a stretch, a runner. The drawn marks came out less distinct: Push and Pull were two nearly identical bars, because what separates them is equipment, not shape. **And abstraction does not answer the question that prompted it** — Push, Legs and Pull are all `strength`, so they share a mark whatever the art. The harness was deleted; nothing shipped. |
| Buying stock muscle-group art | Searched: the permissively licensed developer sets (Tabler, Phosphor, Lucide) carry the same vocabulary SF Symbols already has — barbell, run, yoga — so they buy nothing, and the sets that do have muscle regions are stock-platform art with attribution or subscription terms. Above the licensing, the art is drawn for 64pt and reads as a grey smudge at 20. |
| Custom-drawn muscle glyphs, for now | The pile that would actually tell a Push from a Pull needs artwork SF Symbols does not have — `figure.push`, `figure.chest`, `figure.lowerbody` are not symbols. Shipped against the system pile; swapping in custom symbols later is a change to `SessionIconView` and the list in `SessionIcon`, not to the format. |
| A model logo per block | Asked for and deferred by Jon: nothing records which model wrote a plan, `write_plan` carries no author, and every block so far was written by Claude — so the mark would be identical on all of them, which is the rule that removed the last two glyphs. Revisit when a second model has written one, as an `author` field rather than as bundled brand art. |
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
| What a session clock does overnight | Stops at the last ticked set. **Reversed the next day**, on seeing it in use: it must tick, and Finish is what stops it. The answer to a stale session is to finish it. |
| Whether the rest bar names the movement | No. There is no room beside the ring and three controls, and he already knows what he just ticked. |
| What replaces the check on a completed session | The panel's own ground, tinted. Jon: *"the check mark icons not enough… maybe we make them green or something."* |

**A block's `completedAt` is not renamed, because no reader sees it.** The field
records that a later plan superseded the block — nothing in the app lets a lifter
declare one finished — so the name overclaims. Renaming the snapshot key to
`closedAt` was weighed and rejected on one fact: **no MCP tool emits it.**
`currentBlock` is by definition the open block, and reports title, goal, dates
and counts; the only `completedAt` Claude is ever shown is a *session's*, which
`SessionLog.finish()` writes and which means exactly what it says. A format bump,
a decoder migration and a reconnect to correct a claim no reader receives fails
the test the standards set. `isComplete` is deleted and both doc comments now say
what the field holds, which is where the risk actually was: the next person to
need "did he finish it" would have found a plausible answer waiting. The real
answer is the sessions, week by week, and they are already in the document.

**The write half of the loop was re-proven on 2026-08-19, with marks and groups.**
Not by reading the code: the release binary was driven over stdio with a real
`write_plan` — two days, a per-exercise note, a group of two, and a mark on each
day — and the file it wrote was read back off disk. It carries `"icon":
"strength"` and `"icon": "intervals"`, the group as a group rather than as two
loose exercises, and the note. The same call with `"icon": "deadlift"` failed
with the name and the list of the ten it will take, and wrote nothing. An
`exerciseID` the catalog does not have fails the same way, which is how the first
run of this probe failed — my invented IDs, not the app's.

Worth knowing where the file lands, since it cost a wrong turn: `--documents` *is*
the Documents folder. The server writes `<that path>/plan.json`, not
`<that path>/Documents/plan.json`.

## Calibration

Across a long day of building this, one pattern held without exception: **the
owner's defect calls were right and the assistant's aesthetic calls mostly were
not.** Bugs he pointed at were real bugs. Designs proposed unprompted were
overruled far more often than not.

What follows from it: fix what is broken freely, and stop and ask on anything
that is merely a defensible taste call. Two designs that both work is his choice,
not a gap to fill.

**The pattern held again, twice in a day, and both times on a call made from the
better argument rather than from use.** The chevron was removed because a mark
identical on every row distinguishes nothing — true, and wrong, because the mark
was doing the other job the rule allows: naming an action. The clock was frozen
at the last ticked set because that is the only span the record can vouch for —
true, and wrong, because a clock that moves only when you tick is not a clock you
can train against. Both were reversed by Jon within a day. The lesson is narrower
than "ask more": **a rule about what a thing means is not evidence about what it
does.** Where the argument is about use, the render is not enough — the answer is
in using it, which he does and this session does not.

The second pattern, four times over: **a change made where the assistant was
looking and not where its siblings were** — panel insets applied to two callers
of five, a completed-row background left on the group table after deletion from
the exercise table, a `Done` button left on one sheet of three. Rendering the
screen being worked on is not verification. See *Verification* in `CLAUDE.md`.
