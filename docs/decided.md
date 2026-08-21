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

The wire no longer follows the store: `plan.json` says `blocks` as of version 5
and the snapshot says `blockOrdinal` as of version 4. The store's own names are
the exception, and the reason is CloudKit rather than taste.

## The loop

**The coach writes one block at a time, and the routine grows.** Jon: *"the
coach (claude) should be using all of the info up until that point and make 1
week at a time instead of making everything at once."* A plan document carries
the routine's `id`; importing one already in the store now *merges* rather than
being ignored. Next week's block lands on the routine he is training instead of
becoming a second routine with the same name.

**What he has not done is the coach's; what he has done is the record.** Jon's
rule, in his words: *"the coach can change anything thats not checked off."* A
block with no completed set is rebuilt from the arriving document however it
now reads, a block the document no longer states is removed, and a block with
any completed set is refused by ordinal if the document changes it. The
comparison is `PlanDocument(reconstructing:)` — the same round trip the export
uses — so an unchanged document arriving twice writes nothing.

**Omitting `routineID` starts a new routine and closes the current one.** That
is the difference between next week and a change of programme, and neither has
to be guessed at. `nothingPrescribedBeyond` in the context resource is the cue
that the next block is due; the routine page says the same thing to the lifter
in words.

**`write_plan` guides one block at a time and does not enforce it.** A four-week
plan written in one go is still a plan somebody may want, and a schema that
refused it would be the server making a training decision.

## Resolved — the rename that was held open

**Done by deletion, 2026-08-21.** The two `@Model` names below were held hostage
for months: SwiftData derives the CloudKit record type from the entity name, so
renaming `TrainingPlan` or `TrainingWeek` without a tested migration opens the
store empty with the data still in the container. The backend rebuild deletes
both types outright — there are no routines and no block table — and it resets
the store, so there is nothing to migrate and no record type to strand. Every
name in the store is set correctly once, at the only moment it was free. What
follows is kept for the reasoning, not as an obligation.

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

**2. The `weeks` key. Done on 2026-08-19.** `PlanDocument` version 5 writes
`blocks` and reads `weeks` from anything earlier; `TrainingSnapshot` version 4
renamed `weekOrdinal` to `blockOrdinal` with it, since the snapshot carries the
document and half a vocabulary on one wire is worse than either. `write_plan`
advertises `blocks`, still accepts `weeks`, and the context resource reports
`blocksPrescribed`, `blocksLogged` and `currentBlockOrdinal`. What is left is
item 1 — the two `@Model` names, which are CloudKit record types and stay where
they are until there is a tested migration.

*Do the store rename in its own sitting.* It is the one with data behind it.

## Settled

| Decision | Why |
|---|---|
| The snapshot carries the plan document itself, and the log is flat | A prescription lived in three vocabularies, and two of them disagreed: a document *nests* a group, the old `Snapshot*` tree *flattened* it into a marker on each member. One description now, written by the format that prescribed it. The log is a series and was nested five deep, so every reading tool began by flattening it — the wire does it once. |
| `RoutineBlueprint` and `DayBlueprint` are deleted; `PlanImporter` maps the document straight into the store | **Overturns the rule in CLAUDE.md that called `RoutineBlueprint` the seam a plan enters by.** Checked rather than argued: `PlanImporter.swift:129` builds it and `PlanImporter` reads it, one producer and one consumer in the same file. It never crosses a boundary, so it is not a seam — it is a **third plain-value description of a prescription** sitting between the document and the store, which is exactly the shape this project already paid a rewrite to remove. `PlanDocument` is already a tree of plain values and can be the thing the importer reads. 390 lines go. The guarantee the blueprint was carrying — *records what it was handed, never clamping* — is a rule about `PlanImporter` and moves onto it, along with the rule that it is the only producer and no second one may be added. |
| `assembly-rules.json` is deleted | **Zero readers in any target** — confirmed by grep across all three. CLAUDE.md already said nothing decodes it and it was reference material for Claude, but nothing ever put it in front of him either, so it was a bundled file whose only delivery mechanism was somebody opening it by hand. `program.md` does the job properly: the same material, written by the coach for this lifter, editable, rather than frozen at build time and unwritable. Data earns its place or it goes, whole. |
| A plan format 6 refuses every earlier version — **once**, at the reset | Amends the row below, and only for this break. Versions 1–5 stated a routine of named blocks of days keyed by weekday, with an exercise's sets as a count *or* a list. Version 6 has no routine, no block label, no weekday, and states every set. Reading a version 5 document into it would mean inventing block ordinals from list positions and discarding weekdays — interpretation wearing compatibility's clothes, landing in the store as prescriptions nobody wrote. It is safe **only** because the store resets at this format, so no earlier document has anywhere to land and none is archived. From version 6 onward the archive rule holds again: a version 7 reader must read a version 6 plan. Carrying the older shape would have meant keeping `LegacyBlockKey`, `SingleWeekCodingKeys` and the three-way `blocks`/`weeks`/`days` reconciliation forever, for documents that will never arrive. |
| A snapshot is refused in **both** directions; a plan and a profile update are not | A plan is an archive: the coach wrote it, it is the only copy, and an older one must read forever. A snapshot is a cache the phone rewrites whenever the record changes, so an old one is a stale file rather than history. Reading either skew half-way reports a lifter who has trained less than he has, which is the one failure that arrives looking like a fact. |
| The app is a datastore and the interface an AI trainer works through | Everything that is neither is bloat. This is the filter for any proposal. |
| The rest clock has one switch, for the whole app | Reverses *a master switch was tried and killed*. Silencing was per exercise, on the reasoning that rest is prescribed per exercise — but Jon, reaching for it: *"when i turn off the alarm toggle for one alarm it should do it universally."* A lifter reaching for that switch is not saying *not on the bench press*, he is saying *not today*, and having to say it again on the next movement is the app making him repeat himself. The *length* stays per exercise; that is the thing that differs between movements. `LifterRest.off` is gone, and a lifter who silenced anything under the older build opens with the switch off. |
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
| The snapshot goes out when a session is finished and when a document lands, not only on background | A lifter who received a block, trained it and never left the app left Claude reading a record written before the block existed — the shape of the report that the snapshot held four sessions where the block prescribed nine. Not on every tick: a snapshot is the whole store serialized to iCloud, and doing that between sets spends battery to tell the coach something he is not reading yet. |
| A failed export is taken up when the lifter arrives, not when it happens | Rendered: an export failing mid-session put *Couldn't Share Your Log* over the workout. iCloud being signed out is not something he can act on with a barbell in his hands, and now that finishing exports, it would land after every session. The outbox still holds it and `RootView` reads it when the scene becomes active. |
| Finish greys and asks while sets are unticked, but is never disabled | Whether he is finished is his to say. Refusing to record three good sets because the plan wrote four would be the app deciding. |
| A finished session is locked until he unfinishes it | Jon: *"if a workout is finished it shouldnt be editable until i mark as unfinished right?"* It is a statement about what happened and the coach has already read it, so the figures stop being editable and the checks stop responding. Nothing is greyed and nothing is refused: the record reads exactly as it did, what goes is the rule under each field — the mark that says *write here* — and the way back is the button already at the foot. His own note stays writable, because *knee hurt at the end* is usually written after finishing and is a record of the session rather than an edit to it. |
| The session clock counts live from the first ticked set and stops at Finish | The start is a fact the record holds, so it survives closing, backgrounding and syncing with nothing new stored. It states hours in `h:mm:ss` when there are hours. **Freezing it at the last ticked set instead was tried and reversed** — see below. |
| Every panel that opens something draws `DisclosureChevron` | The app's mark, not the presentation's: a `NavigationLink` gets one from the system and a `Button` presenting a sheet does not, which is how two lists one screen apart came to speak differently. |
| A panel that acts as a button is tappable across the whole panel | The band between the content's inset and the panel's edge is painted by the row's background; without `fillsPanel` it is dead, and a panel that looks like a button and ignores a third of itself is worse than one that looks inert. |
| A logged session tints its whole panel | `Palette.recordedPanel`, with the check kept beside it. A 24pt mark alone made a list of sessions read as identical panels with a small green square somewhere on the right. Colour never carries it alone. |
| A block states how far through it is, as a rule under the line | `ProgressRule` draws the fraction the words already give — `3 of 12 logged` — and adds no target, no pace and no verdict on whether that is enough by now, because that is a training judgement. A block prescribing nothing draws no track rather than an empty one. |
| Blocks are never tinted by completion | `completedAt` on a block means a later plan superseded it, not that he finished it. Green there would claim what the record cannot know. |
| Panels are 20pt `.continuous`, and there are two radii, not four | A panel painted into the surface wants a tight corner or it reads as a bubble — twelve was right then. A panel that *sits* on the surface wants a rounder one, and once it did, the rest bar's radius and the panel's were the same number, so the bar takes the panel's. The `small` 8 went the same way for the opposite reason: nothing ever drew with it, since the entry fields are ruled rather than boxed. Two names for one number is what the design-system suite exists to catch, and so is a name for no number at all. |
| Panels cast a shadow in light and none in dark, and only when the panel is one row | A black blur on a near-black surface is invisible at any opacity worth drawing, so dark leans on the panel's lighter fill. A `List` gives every row its own background layer, so an interior row's blur lands *on* its neighbours — it banded every set table until the shadow was limited to single-row panels. |
| A panel's shadow is sharp and close: 6pt blur, 2pt drop, 10% | Jon, with the Claude Code app beside it: *"The drop shadows need to be sharper exactly like this."* Twelve points at four spread far enough that the panel had no edge — it read as haze under the card rather than as the card sitting on something. The darkest part of the blur belongs against the panel's underside. |
| A panel's shadow is a contact shadow: 3pt blur, 1pt drop, 6% | Jon, with the reference beside it a third time: *"too much, it should be crisp and small like this."* Six at two and ten per cent read as a halo once a panel was the height of a whole exercise. The blur belongs entirely against the panel's underside; the hairline is what draws the edge. |
| The neutrals carry none of the theme's hue, and the theme is a fill only | Tinting the greys two or three per cent toward `#DCFF5C` — so the palette would read as one object — made every surface khaki: Jon, *"puke green tint"*. At this hue two per cent is the difference between a grey and a dirty one, and a highlighter reads as one because the paper under it is white. Deepening the theme for light-mode marks was the same mistake twice: carried dark enough to read on white, `#DCFF5C` is army olive. So the theme is a filled shape and never a line — the button, the ticked box, the wash under a logged session — and every rule, eyebrow and progress fill is `ink`. |
| Every panel carries a hairline; only a panel of one row casts a shadow | Uniform shadows were asked for and are not possible while panels are drawn by `List` rows: an interior row's blur lands on its neighbours, and casting it from the panel's extended shape paints that shape's fill over them — rendered, the set table came out as three white slabs. The hairline is what every panel has in common; the panels being chosen from are lifted, the tables are not. |
| Every panel is one row, so every panel is lifted the same way | Supersedes the row above. A panel drawn as a run of `List` rows could not cast a shadow — an interior row's blur lands on its neighbours — so the session's tables stayed flat while the cards being chosen from were raised. An exercise is one row now, with its header and sets stacked inside it, and the fill, hairline, radius and shadow are identical everywhere. |
| A set cannot be removed; an unused row is left blank | Jon: *"we shouldnt be removing sets anyway just leave them blank."* Deleting a set was swipe-to-delete on a list row, which is also the one thing that stopped a panel being a single row. A row he did not use is a row he did not tick, which the record already says. |
| A week he has not reached recedes, and is shut | Muted heading and names, flat panel, and a lock where an open row carries a chevron. **This reverses *a later week still opens*, on Jon's call:** *"I want them completely locked to the user."* The reason it used to open — the app may never refuse to record a session he actually trained — is a real cost and it lands in one place: a session trained ahead of schedule reaches the record when its week becomes current, not on the day it happened. The lock is on where the week sits in the block, never on the calendar, so finishing the current week opens the next one immediately. The week he is on is the earliest still holding an unfinished session, read from the record rather than the calendar. |
| The app derives no dates for the block he is training, and the code that could is gone | The week he is on is read off the record — the earliest still holding an unfinished session — and a session trained on Wednesday that was written for Tuesday is still that session. `RoutineCalendar.today(in:on:)`, `TodayInRoutine`, `BlockDay`, `WeekPlacement`, `SessionProgress` and `RoutineToday` answered *where does today fall* for a front door that was deleted; ~600 lines went with it. What survives is `span(of:)`, which dates a block behind him — the one date the app still states. |
| A toolbar glyph is a bare mark, since the toolbar draws the circle | `info`, not `info.circle`, beside a bare `chevron.left`: a circular symbol inside a circular button reads as a ring in a ring, so the two buttons looked different sizes when only the glyphs differed. |
| Claude can write a free-form note on any exercise, and it already works | `PlanDocumentExercise.notes` → `PlannedExercise.notes` → drawn at the **foot** of the panel, closing it, in muted support type. Optional, unstructured, absent when he writes none. There is a per-*set* note beside it — `SetPrescription.notes`, for "last set to failure" — and a note on the block itself. Asked for on 2026-08-19 and found already built, end to end. |
| The lifter writes his own note, in a field of its own | Jon: *"claudes note is to provide extra detail on the workout my note is to say my feedback during that excersise like my knee hurt at the end."* Two different things, so two fields: the coach's is part of the prescription and is rewritten by every plan, and the lifter's is part of what happened and must survive that. One field would mean whichever wrote last erased the other. It is written from the exercise's menu, drawn at the panel's foot under the coach's in ink rather than support grey, and carried in the snapshot as `lifterNotes` — flat, beside the log, because it is a record and not a prescription. It is the only thing in the record the coach cannot infer from the numbers. |
| An optional element sits where its absence costs the panel no shape | Jon: *"the note should be at the bottom that way it doesn't change the panel format since its optional."* Between the name and the table the note was in the place it belongs — it is about the movement — but it pushed the sets down on the exercises that had one, so two panels in a session had their first row at different heights. |
| A panel's edge spacing is the panel's and the row's, never a third thing's | Three paddings were stacking at the top of an exercise panel — `closing`, the row's inset, and one `CardHeaderRow` added — putting thirty points above the name against twelve below the last row. The header adds none now, except four points for the superset eyebrow, whose smaller line box carries less clearance than a title's. |
| Ticking a set inside a group brings the next movement's set into view | A superset is trained *across* its movements and drawn *down* them, so the next thing to do sits on a panel the lifter cannot see. The order comes from the grouping the plan prescribed, never from an opinion: `ExerciseGroup.setAfter` answers "what is next" and a group with nothing waiting leaves him where he is. Taking a set back scrolls nowhere — that is correcting the record, not asking what is next. An ungrouped exercise moves nothing: its next set is the row below. |
| The rest bar opens a sheet with the clock and the next set | Jon: *"tapping this should open a clean popup with a big ring and timer in the middle… then when its checked move to the next one, a one row at a time view thats good for when im at the gym."* A sheet rather than a screen: rest is a state he is in for ninety seconds, not a place he goes, and the table stays behind it. The countdown is the largest thing on it; under it is one row, drawn by the same `SetRowView` the table uses, so a set logged in either place means the same thing. The sheet closes itself when the clock stops — the row is still there in the table behind. What is next comes from `SessionOrder`, which reads the grouping the plan prescribed: down an exercise's rows, and *across* a group's movements round by round. |
| A group's movements each get their own panel | The rule down their edge and the word above their names is what says they are one thing. Sharing a panel with no gap was tried on the reasoning that two things lacking the gap everything else has must be one — rendered, it read as three separate exercises rather than a pair. **A signal has to be present, not withheld.** |
| A session's mark is Claude's, chosen from a set the app publishes | The app owns the pile and refuses anything outside it; he picks. Deriving it from the day's name or from its exercises would both be the app deciding what a session is about. A day he marked nothing carries nothing — there is no default. |
| An icon names an action a word will not fit, marks a state that varies, or is a mark Claude chose — nothing else | And a varying icon varies along **one axis**. SF Symbols only; see *Standards* in `CLAUDE.md`. |
| The app is called Superset; the bundle id and iCloud container are not | `com.jonluongo.LiftingPlan` and `iCloud.com.jonluongo.LiftingPlan` stay. Renaming either makes this a different app to iOS, with an empty store and no way back to what is on the phone. `AppIdentityTests` guards all three. |
| The weight field states its unit wherever there is a weight | Jon: the weight box should never be empty, at least say `lb`. It says `185 lb × 8-12` now, in the same device the hold and the carry already use for `s` and `m`. Drawn under exactly the condition the `×` is, so a push-up still shows an empty field: an exercise carrying no load has one on purpose, and `lb` beside it would be the app asking for a number nobody prescribed. A dash was the other candidate and is the thing this field must never draw. |
| Every number lives in `Style.swift` | A number written in a view is a number nobody chose. |
| `Views/` holds only SwiftUI; pure model→string logic is `Presentation/` | Mechanical test, no judgement: if it does not import SwiftUI, it is not a view. |
| A stated fact is one type, `StatedFact`, wherever it is stated | The lifter's record, a movement's catalog entry and a routine's shape all draw through `FactRow`, and each had built its own two-string struct — one of the doc comments had already drifted into calling itself the opposite of another that read identically. `AccountRecord`, `ExerciseAbout` and `RoutineFacts` return the one type. |
| An empty work field hints the figure, not the prescription's wording | The row draws `s` or `m` after the field, so `45 seconds` said the unit twice and, in three figures of width, said it as `45 sec…`. `WorkPrescription.targetFigure` reads through `WorkDuration` and `WorkDistance` — never by trimming words — so `1:30` hints `90` and it cannot disagree with the readers that decided the row is a hold. A counted row is untouched: the `×` is its unit. |

## Tried and killed

| Rejected | What happened |
|---|---|
| A week strip / calendar on Home | Rested on an invented start date and showed intent where the log records fact. `WeekStrip` and the screen that drew it are gone. **`RoutineCalendar` and `BlockSelection` are not** — the first dates a routine for the list, the second names a block and answers which one he is on. This row said all three had gone, which would have had a later session deleting live code. **Superseded on 2026-08-21: all three are now genuinely gone.** The backend rebuild removed the last caller — `span(of:)` dated a block behind him, and sessions no longer carry a date at all — leaving `RoutineCalendar` and `RoutineSchedule` referencing only each other. The warning above still stands as method: a mutual-reference island reads as live to any grep, and the way to tell is to ask which caller is *outside* the island. |
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
**`ExerciseResolver` is deleted, and the lean toward wiring it in was wrong.**
It sat open as *delete 286 lines, or wire it into `list_exercises`*, with the
assistant leaning wire-in twice. Reading its API settles it against that:
`resolve(_:fallback:)` "substitutes the first exercise satisfying `fallback`"
when nothing matches, and `MatchConfidence` carries `.fuzzy(Double)` and
`.fallback` as ordinary outcomes. Its own doc comment calls it "the sole path by
which generated or user-typed exercise names are allowed to become a concrete
`ExerciseID` **for persistence**." A substituted ID exists in the catalog, so the
comment's claim that "an exercise is never invented" is true on a technicality
and false where it counts — the key points at the wrong lift, which is precisely
the fragmentation CLAUDE.md calls *the difference between a database and a pile
of text*. The repo already carries the scar: `aliasesAreUnique` records
"upright barbell row" resolving to a dumbbell exercise.

**The half worth keeping already existed.** `ExerciseCatalog.search` ranks
display names and aliases, and `list_exercises` exposes it as `query`. So the
coach already asks for "bench" and gets candidates *with their real IDs* and
picks one. That is the honest shape — the catalog offers, the coach decides, the
stored key is one he sent verbatim. The resolver was the same feature with the
choosing moved inside the app and a confidence score attached, which is the app
deciding the one thing it must not.

**The dead code left by a deleted screen is islands, not strays.** The sweep of
2026-08-21 removed about 590 lines in three rings, and every one of them reads as
*live* to a reference count. `RoutineCalendar` and `RoutineSchedule` call only
each other — the rebuild took the last outside caller when sessions stopped
carrying dates. `Equipment`, the four-tier enum, exists to be expanded by
`EquipmentAccess` and by nothing else; both were the profile-era answer to *what
do you own*, which is prose in `user.md` now. `ExperienceLevel` was the profile's
*how long have you trained*, and is **not** what draws the About page's
*Difficulty* row — that is the separate `Difficulty` taxonomy, which is why the
two are documented as deliberately distinct. `CoachNoteView` and `ProgressRule`
were plain orphans.

**The method, since a grep clears all of it.** Count references *outside the
declaring file*, then ask whether the survivors are all inside one ring. Asking
only "is this mentioned anywhere" keeps every island alive forever.

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

**Driven end to end on 2026-08-20, with figures rather than reasoning.** A plan
was written by the release server, imported by the app from the shared folder,
logged against in the simulator — three weeks of bench at 185, 195 and 205 lb
for five — exported by backgrounding the app, and then read back by driving the
same release binary against the file the phone wrote. Every number agreed:
twelve completed working sets and sixty repetitions on both sides, 205 lb the
heaviest on both, `volume_by_muscle` counting the same twelve sets and sixty
reps under chest, and eight sessions reported where eight were logged. The read
path does not lie.

**The store's schema change was proven by upgrading a real store in place, on
2026-08-21.** Adding a `@Model` and removing a property are the two changes most
likely to open a SwiftData store empty, and everything until then had been
tested on a schema that never changed under it. So the build from before both —
`31f7374` — was checked out into a worktree, run, and given a real plan and a
real profile update, until its store held a routine of eight sessions, a goal, a
constraint, seven pieces of equipment, a weigh-in, and the `preferredWeekdays`
that was later deleted. The current build was then installed *over* it, with no
erase.

Everything survived. The same goal, constraint, equipment and weigh-in came back
out, the routine still had its eight sessions, and the snapshot went from version
4 to 5. `ZPROFILESTATEMENT` had been created by lightweight migration, the
weekday column was gone from `ZUSERPROFILE`, and `statedAt` came back as `{}` —
a profile that predates the dates carrying no dates rather than invented ones,
which is what the unit test claims and this is the same claim against a store
that actually migrated.

**On the phone itself, the store opens.** Once the device was unlocked the app
was launched over its existing store — the one carrying CloudKit records written
against the old schema — and was still running twelve seconds later. That is
worth exactly what it proves and no more: `LiftingPlanApp.init` calls
`fatalError` when the container will not open, so surviving launch means the
migration did not throw. It does **not** prove the rows came across, because a
store that opens empty also survives launch, and there is no way from here to
read the phone's container or see its screen. The simulator's in-place upgrade
is what shows the data intact; the device shows the same schema change does not
refuse to open against real CloudKit metadata. Between them the risk is small,
and the remaining check is one look at the phone.

**The dated statements were driven the same way on 2026-08-20, and the
distinction holds through real files.** Two `profile-update.json` documents were
written by hand — a March one stating a constraint and an experience, an August
one stating only the goal — dropped in the folder one at a time, taken in by the
app's own inbox, and exported by backgrounding it. The snapshot came back with
`constraints` and `experience` dated March and `goal` dated August, which is
exactly what a single `updatedAt` could never say: under it, the August goal
would have restamped the March shoulder. Driving the release server against that
file, `unstated_facts` reported the same three dates and passed no verdict on
any of them.

Worth knowing for anyone probing this again: **killing the app does not export.**
`simctl terminate` — and a lifter swiping the app away — ends the process without
`scenePhase` reaching `.background`, so the export never runs and the file on
disk stays exactly as stale as it was. Backgrounding it properly (launch another
app) is what triggers the write. A probe that terminates and then reads the file
is measuring the previous export, which is the same mistake as reading a stale
snapshot in the first place — it cost an hour here before the timestamps were
checked.

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

**How to get a screen on screen is written down.** `docs/rendering-the-app.md`
holds the four scaffolding patches, how to drive the simulator, and the six
things that each cost an hour to learn — the `SIMCTL_CHILD_` prefix, that
terminating is not backgrounding, that there is no way to tap, that the
permission dialog is SpringBoard's and outlives the app, that the store outlives
the build, and that a colour is judged by measuring a pixel rather than by
looking. It was re-derived from scratch a dozen times in one week before anyone
wrote it down.

## Waiting on the owner

Open questions and blocked work, with what each needs. **Not decisions** — this
section exists because a long session gets compacted and an unanswered question
looks identical to a settled one afterwards. Anything answered moves up into
*Settled by asking* and leaves here.

| What | What it needs | Where it stands |
|---|---|---|
| The loop reaching the Mac at all | iCloud storage freed (**101 KB left**), and a Mac app bundle claiming `iCloud.com.jonluongo.LiftingPlan` | Both halves are his. `brctl status` reports `SYNC DISABLED (app not installed)`; the write half is proven by driving the release binary, and every layer reports the failure honestly — the phone's *Couldn't Share Your Log*, the server's missing-snapshot message, `write_plan`'s delivery note. None of it is fixed. |
| Dated statements, step 4 | Which of three phrasings the account page uses | Steps 1–3 shipped on 2026-08-20 — the phone keeps a date per fact, the wire carries it, both tools describe it. What is left is the screen: each fact carrying its date the way `Bodyweight · Aug 20, 2026` already does, and the baseline rows saying they are starting points rather than current bests. The spec is `docs/superpowers/specs/2026-08-20-dated-statements-design.md`. |
| `reps` optional | Part of the same decision, taken separately | A set prescribed as a range and ticked without typing logs `0 reps`, which the coach reads as a completed working set at `185 lb × 0`. `durationSeconds` and `distance` are already optional for this exact reason. |
| Time Sensitive Notifications | A capability toggle on the App ID in the developer portal | The rest timer asks for it; a build claiming the entitlement without it is **refused at signing** — checked, not assumed. The code states the intent and starts being honoured the day it is on. |
| The markdown split | A go, and three open answers | **Worked out with Jon in conversation on 2026-08-21. Nothing built.** The dividing question is not words against numbers, it is **does anything join to it or compute with it**. **SQLite keeps** the log unchanged; the plan's skeleton, because every logged set points at a `PlannedExercise` and that join is what lets the app say *185 × 5 against a prescribed 5–6*; the labels that name a row — a routine's title, a block's label, a day's focus — because the list draws them and a string key into a file is a join with none of a foreign key's guarantees; and the lifter facts anything computes with: `displayUnit`, `ownedEquipment` and the two avoid-lists, which filter the catalog, plus the bodyweight series and the baselines. **Markdown takes the prose:** `user.md` for the objective, his background, his injuries and whatever the schema never anticipated; `program.md` for why this routine — the approach, what is being progressed, what to watch. Not the sets. `program.md` supersedes `assembly-rules.json`, which is the same idea frozen at build time and unwritable by the coach. **Two columns leave the store:** `TrainingPlan.goal` and `.notes` to `program.md`, and `UserProfile.goal`, `.experience` and `.constraints` to `user.md`. **`PrescribedSet` keeps its numbers and loses its `notes`** — a ramp and a drop set are different loads and rep ranges per set, which the row has to draw, but a note about one set can name the set in words. Notes collapse to two, both on the exercise: the coach's and the lifter's. Agreed after the assistant first argued the per-set note earned its place; that argued for a capability rather than for what the lifter gains, and the only real difference was where the line draws — under set four rather than at the foot of a panel already in view. **Still open.** *One:* the dated statements built on 2026-08-20 date `goal`, `experience` and `constraints` — the three fields moving out — so they would end up dating only equipment and the avoid-lists, which least need it. Either `user.md` carries its own dated entries or that work loses most of its point. *Two:* a file an agent rewrites wholesale loses things invisibly and prose has no refusal machinery — append-only sections, a kept prior version, or a diff shown back, chosen before it is built rather than discovered. *Three:* `preferredDurationMinutes` is the last profile field that is neither prose nor computed with, and has no home in either column yet. |
| The backend, rebuilt | A go, six schema answers, and the migration question first | **Converged with Jon across 2026-08-21. Nothing built.** His framing: *"we are full redesigning the backend big picture so dont use the current flow as a constraint... Striving for maximum correctness on the final build not least invasive change."* A target, not a migration plan. **The loop, in one sentence: the coach reads `user.md`, `program.md` and the performed tables, and writes prescriptions; the app draws them and logs against them.** **Ask this before anything is built: what happens to the training history already on the phone.** Every table is renamed and restructured, and SwiftData derives CloudKit record types from entity names — the exact hazard this file has held the `TrainingPlan` rename open for since the beginning, now applied to all ten tables at once. Migrate across, export as documents and re-import, or start clean and lose what is logged. The assistant designed the whole schema as though the store were empty and only raised this at the end; it is the first question, not the last. **Five tables.** *`Session`* — blockOrdinal, ordinal, focus, icon, finishedAt, generatedAt, catalogVersion, sourceDocumentID. *`PlannedExercise`* → Session — exerciseID, order, restSeconds, tempo, coachNote, groupOrdinal (nullable). *`PlannedSet`* → PlannedExercise — setIndex, isWarmup, load, intensity, and one **typed** target: rep range, duration or distance. *`PerformedExercise`* → Session, → PlannedExercise (nullable) — exerciseID, occurredAt, lifterNote, `source` = logged \| stated. *`PerformedSet`* → PerformedExercise, → PlannedSet (nullable) — setIndex, isWarmup, load, reps, durationSeconds, distance, completedAt. **`Routine` and `Block` are gone** on Jon's call that **blocks do not need names**: a block is an ordinal on `Session`, and what makes block 3 an accumulation block is a line in `program.md`. That dissolves the `TrainingPlan`/`TrainingWeek` rename held open above — a rebuild is a new store, so the names are set correctly once. **The naming standard**, after Jon rejected `LiftRecord`: a pair mirrors its counterpart (`Planned{X}` ↔ `Performed{X}`); a name says what *one row* is; no word meaning something else in this domain — which is why `SetRecord` was passed over, since a lifter reads *record* as a PR; no abstraction nouns, which is what `ExercisePerformance` was. **Why prescriptions and records stay separate — Jon's reason first, better than the three the assistant gave:** the prescribed-versus-performed comparison *is* the coaching signal, and merged into one flagged table it becomes a self-join on a discriminator at both ends. Then: a range and a value are different types, so one column holding both is a string again; a prescription is rewritable while nothing is logged and a performed set never is; one prescribed set has zero, one or several performed sets. **A consequence: prescriptions are permanent**, so nothing in the rebuild may offer to delete a trained plan. **Three defects found by one test of Jon's — asking why the two sides do not match.** *One:* **the coach cannot prescribe a warm-up.** `isWarmup` appears nowhere in `PlanDocument`; `SetSeeding.swift:56` hardcodes `false`. Both sides now carry it and may honestly disagree — a lifter treats a prescribed working set as a warm-up all the time. *Two:* **the prescribed measure is untyped** — a 40-metre sled push is the text `"40m"` in a column named `repRange`, rescanned by `TargetUnits` at every read; the counted-held-or-carried rule honoured on the record side and broken on the prescription side. Parse once at the boundary, refuse what cannot be read. *Three:* the assistant's own case against merging led with its weakest leg, the column difference, which nearly vanishes once the two are corrected. **Supersets work without extra structure, traced end to end.** Members share a `groupOrdinal`; round *N* is the *N*th **working** set of each member ordered by `order`; warm-ups precede the group; rest falls out per exercise — 0 after A1, 180 after A2. Trisets, two groups in a session and unequal set counts all follow, the last degrading honestly (bench 3, row 4, round 4 is the row alone). The performed side reconstructs rounds through the `PlannedSet` link without storing anything about rounds. **A `PlannedGroup` table was proposed and then withdrawn in the same conversation**: the argument for it was that two members could disagree about the round's rest, but under per-exercise rest there is no round-rest field to disagree about, and per-exercise rest is *more* expressive. One caveat, named rather than hidden — the store can express a rest between members that the document cannot, so reconstruction reads group rest off the last member. **`groupPosition` is deleted**: it was a second ordering number for a fact `order` already carries, since group members are contiguous by construction. `notation` was never added — `A1` derives. **`UserProfile` goes whole, settled by checking.** Every profile field is display-only in the app; the sole computation anywhere was the avoid-list subtraction in `ListExercisesTool.swift:36–41`. **The assistant had claimed equipment filters the catalog; it filters nothing** — the second unchecked compute-with assertion after `weekday`. So `UserProfile`, `ProfileStatement`, `BodyMetric`, `StrengthBaseline`, `ProfileUpdate` and its coding, `SnapshotProfile`, the `statedAt` wire, `update_profile` as a ten-field tool, and `unstated_facts` all go, and **`update_profile` becomes *edit a file*.** The dated-statements work of 2026-08-20 is deleted by this, but **the idea survives as `Session.generatedAt`** — a prescription is a statement and a statement is an observation with a date. It must be the coach's date, proven with real files that day. **Jon's call: the account and routine info screens become the markdown files.** The app **renders** them and never parses them; the moment a number must be read out of prose, that number belongs in a table. That deletes `AccountRecord`, `RoutineFacts`, the row-per-fact layout and the baseline-phrasing question open since 2026-08-20. How much markdown gets rendered is a visual call left to Jon. **Versioning was asked for and declined, with the thing behind it granted.** Version columns are a permanent tax — every query and join gains *and this is the current one* — paid on every read to answer a question nobody has asked. But **`sourceDocumentID` points at nothing today**: the plan document is not kept. **Keep the documents** — one file per import, never mutated, named by its ID — and every version of every prescription the coach wrote is on disk in the form he wrote it, at zero schema cost. `decided.md` already calls a plan an archive that must read forever; it is currently an archive being thrown away. Edits to the lifter's own records are not covered and deliberately so: a correction thirty seconds later is a typo, not history. **The rest clock's switch moves to `UserDefaults` and does not sync** — CLAUDE.md calls it *about this phone rather than about the lifter*, and a phone in a gym and one on a desk want different answers. **Rest actually taken is computed, not stored**: the gap between consecutive `completedAt` timestamps, which is truer than the timer's own number, since a timer that ran 180 seconds says nothing about the 60 spent talking afterwards. It is **not to be reported to the coach yet** — a lifter who ticks a whole session at the end produces clustered timestamps and meaningless gaps, and nothing in the data says which kind of session it was; a rest figure silently wrong for a whole session is the same class of defect as the snapshot claiming four sessions when there are nine. **Exercise data is not in the database at all** — `exercises.json`, 412 movements, bundled, versioned, read-only; the store holds only `exerciseID`. His working max is computed, never stored. *How he does a lift* is prose in `user.md`, not a per-exercise table. **`catalogVersion` is kept but described honestly**: it is written, exported and reconstructed and **never consulted**. It earns its place as document content for the round-trip, not as the guard the assistant had claimed, and nobody should build on a promise it is not keeping. **Still open, schema.** *1:* **block numbering** — never reset, restart per programme, or drop it and order by date. *2:* **`load` on bodyweight movements** — added or total, where assistance goes (negative added load, which `Mass` cannot express), and that bodyweight-as-load is unavailable once bodyweight lives in `user.md`. *3:* whether duration and distance targets need ranges. *4:* **RPE achieved** — `intensity` is prescription-only and lifters do record what a set felt like; a candidate, not added. *5:* **conditioning** — the catalog is 412 lifting movements, so a bike or a run may have no `ExerciseID` regardless of measure. *6:* **tempo** — `ExerciseHeaderView.swift:88` draws it in the subtitle, and the assistant leans to folding it into the coach note, since nothing parses it and two free-text fields on one exercise invite a coin-flip; the cost is that a scannable subtitle fact becomes prose, which is Jon's call. **Not examined at all.** The wire — `plan.json` changes shape substantially and `snapshot.json` loses the profile, neither redesigned. The MCP tools — `write_plan` follows the document, `exercise_history` should report per performance rather than flat, and `volume_by_muscle` and `recent_sessions` have not been looked at once. The transport, still open from earlier and now carrying two markdown files in both directions. **The markdown files' safety**, unanswered since the split was first proposed: an agent that rewrites a file wholesale loses things invisibly and prose has no refusal machinery — append-only sections, a kept prior version, or a diff shown back, chosen before it is built. And the screens: `PlansView` has nothing to list without routines, so what the app opens on needs re-answering. **The wire is the next useful piece** — the tools and the transport both hang off it, and it decides whether the existing history can be exported cleanly before any of this replaces it. |
| ~~The schema, rebuilt from scratch~~ *(superseded by the row above; kept for the audit findings and the method failure)* | A go, and two holes filled | **Worked out with Jon on 2026-08-21, continuing the row above. Nothing built.** He asked what the simplest organised version looks like if it were built from nothing, and pushed the question further: *"I wonder if the only things that need to be stored are past lift records and future lift prescriptions."* **The proposal is seven tables on one principle — intent and event never share a table.** Intent: `Routine` (title, startDate, catalogVersion, sourceDocumentID, `closedAt`), `Block` (ordinal, label), `Session` (focus, icon), `PlannedExercise` (exerciseID, order, restSeconds, tempo, coachNote, group), `PlannedSet` (setIndex, repRange, load, intensity). Event: `LiftRecord` — exerciseID, occurredAt, load, reps, duration, distance, isWarmup, a `source` flag, and a **nullable** link to the set that was prescribed. Lifter: one `Lifter` row holding only what a machine reads. Plus `user.md` and `program.md`. **What the storing-it-as-a-blob idea costs, and why it was argued down:** a logged set currently has a real foreign key to a `PlannedExercise`, so the database guarantees the target exists and cascades the delete; coordinates into a JSON document have none of that, and the plan is the app's central queried object rather than an opaque one. The snapshot's flat log works only because nothing writes into it. **Three things fall out and are agreed in principle.** *Every prescribed set is a row* — today `PrescribedSet` exists only when sets differ, so there are two code paths and a reconciliation; materialise them all and a ramp, a drop set and three identical sets are one shape, and `targetSets` and the exercise-level `repRange` disappear. *A baseline is a record with a flag*, not a table — `StrengthBaseline` folds into `LiftRecord` with `source = stated`, which is also why that foreign key is nullable: a baseline and an added set have no prescription behind them. *Bodyweight leaves the store* — but **only if the account row showing the latest goes too**, otherwise prose is being parsed to draw a number, which is worse than a three-column table. **The audit that followed matters more than the proposal.** Jon caught that the schema carried `weekday` forward into a design that was supposed to derive from scratch, one day after `preferredWeekdays` was removed on the reasoning that *when* he trains does not matter — the contradiction was in the same session's own work. Interrogating every remaining column found four more. **The biggest: `LoggedSet` is not an event table.** `SetSeeding` creates a row for every prescribed set before the lifter touches anything, which is why `isCompleted` exists and why `reps` defaults to `0`. Write a row only when he ticks and three problems close at once — `isCompleted` goes because the row's existence is the fact, the 0-reps ambiguity stops applying to untouched sets, and `SetSeeding` goes with them. **`weekday` should be an ordinal**: it does two jobs, identifying a session within a block on the wire and naming an unnamed day, and *Session 2* does both without the schema thinking in calendar weeks. **`displayName` is a cache** of what `exerciseID` already resolves to, and unknown IDs are refused so the catalog always has it. **`durationMinutes` exists in three places** — routine, session and profile — and is the session-length question still open above. **Two holes in the proposal, both the same kind.** It has no table for *this exercise, in this session, as it went*, so the lifter note Jon placed at exercise level has nowhere to live on the event side; and the group notation — `groupID` plus position, the one part of a prescription that is not a simple tree — was never checked against the flattened sets. Both are things already specified that seven tables cannot express. **The method failure worth keeping:** the schema was built by editing the existing one in the assistant's head rather than deriving it from what the app does, which is exactly how `weekday` walked through. |
| Two commits from that brainstorm | Revert both, revert one, or keep | `3b184f0` removed `preferredWeekdays`; `1abdbac` rewrote the goal's descriptions. Both were built mid-conversation before anything was agreed, which Jon corrected: *"We were brainstorming and you went to build mode before we agreed on a solution dont do that again."* Local only; nothing pushed. |
| The set row at accessibility text sizes | Which way a row that cannot fit should give | **Found by rendering on 2026-08-20.** A rep target elides — `8-10` becomes `8–…` — from `accessibility-large` upward. Everything is correct through `extra-extra-extra-large`, the largest ordinary size, and through `accessibility-medium`; the break is in the accessibility range only. The cause is that `SetTableMetrics.entryColumnWidth` is a fixed 68pt while the text inside it scales, and the row is already full: set column 44 + entry 68 + unit + `×` + entry 68 + check 44. Widening the columns with `@ScaledMetric` — which `TimerRing` already does, for the same reason — pushes the row off the screen instead. So the row has to give somewhere, and where is a design call: wrap to two lines, drop the `lb` and `×` markers at those sizes, or scroll the table horizontally. **It matters** because the elided figure is the prescription: a lifter at those sizes cannot read what he was asked to do, and the standard is that the essential figure is the largest thing on the screen. **The blast radius is one component**, and the sweep is complete — every screen was rendered at that size. The blocks list is correct — rows scale, headings wrap to two lines rather than truncating — and the account page correct, with long values wrapping under their label and short ones still right-aligned. The rest sheet is correct, and so are the exercise detail sheet and its chart, whose axis and date labels stay legible while the facts panel wraps. Only the set table breaks, because it is the only place holding a fixed column width. **A narrow screen says the same thing.** Swept on an iPhone SE at 375pt and ordinary text size: the blocks list, the account page and the routine sheet are all correct, and the one thing that broke was again in the set row — the unit marker wrapped `lb` into `l` above `b`, fixed in `a72d8e8` by letting it take the width of its word. Two independent squeezes, one component both times.

**The row's width budget, since the decision turns on it.** Four fixed columns — the set badge at 44, both entry fields at 68, the check at 44 — plus five gutters come to about 254pt before a single unit marker is drawn. Inside the panel there is roughly 319pt on an SE and 337pt on a 16, so the markers, the `×` and every gap between them share about 65pt on the narrow phone and 83pt on the wide one. The two entry fields are 136 of those 254 fixed points, over half the row. That is why the marker was the thing that gave, and it is where any room has to come from: no arrangement of the current columns finds space at accessibility sizes, because the columns themselves are most of the row.

**And 68pt is already too narrow for an ordinary kilo load.** Rendered on 2026-08-21 with `displayUnit` set to kilograms and loads of `102.5` and `187.5` — five glyphs, monospaced — both draw *shrunken* by `minimumScaleFactor(0.6)`, visibly smaller than the single-digit rep count beside them. The column's own comment says it was widened so "a three-figure load needs the room rather than the shrinking"; five characters is past what that bought. This is not an edge case: 2.5kg increments are how most of the world loads a bar, so a lifter in kilos sees a permanently smaller weight column, on a screen whose rule is that the essential figure is the largest thing on it. It moves this decision from an accessibility matter to a default-size one.

**How short the column is, from the font rather than from a screenshot.**
`supersetMetric` is `.title3` monospaced, 20pt at default Dynamic Type, and a
monospaced digit advances about 0.6em — call it 12pt. The field is 68pt less
`entryInset` on each side, so 52pt of glyph space. Three glyphs need 36 and fit;
four need 48 and fit; five need 60 and do not, which is exactly what the render
shows. **A field that holds five glyphs at full size wants 76pt** — 8pt more
each, 16pt across the row, against the 65pt an SE has for both markers, the sign
and every gap. So widening alone does not close it on the narrow phone: the
markers would then be back where they were before `a72d8e8`. **The same shape appears once more, and it is now proven.** `RestSheet` clears its ring from the grabber with `.padding(.top, Spacing.major * 2 + Spacing.section)` — fixed — while the ring is a fixed 172pt inside a `.medium` detent that is a fraction of the screen. On an iPhone 16 at `accessibility-large` it looked tight and could not be measured. **On an iPhone SE at ordinary text size it collides:** the grabber sits on the ring's stroke and the ring's top is clipped by the sheet's edge — exactly what the comment above that padding exists to prevent, which says the two nearly touching *"read as one broken shape"*. A shorter screen gives the medium detent less height, and nothing in the sheet gives. Same call as the set table: what should give — a smaller ring on a short sheet, a taller detent, or the sheet's own scroll — and that is a proportion decision rather than a defect with one answer. |
| Reduce Motion | Whether to honour it, and which animations it should quiet | **Nothing in the app reads `accessibilityReduceMotion`** — checked, zero references — while five places animate: the rest sheet holding a ticked row and sliding the next one in, two scroll-to-set animations, the rest bar appearing, and the ring's progress. SwiftUI does not honour the setting on a caller's behalf, so a lifter who has turned it on gets all five anyway. The sheet's slide is the one that matters most and is also the one Jon specifically asked for — *"I still want to see the check before we move on"* — so quieting it needs his call rather than a blanket gate. |
| What needs a real device | A pass with the phone in hand | `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` allows both landscape orientations, which is Xcode's default rather than a decision anyone made, and **no screen has ever been seen in it.** `simctl` cannot rotate and this session has no way to tap, so it could not be checked here. A set table whose columns already run out of room at accessibility sizes is unlikely to survive a 393pt-tall window. Either it is worth rendering on a real device, or the app is portrait-only and the key should say so.

**VoiceOver is in the same position.** The set row's two fields are now labelled and the icon controls all carry labels or are deliberately hidden — swept, and the set row was the only gap. But what the rest bar *actually announces* could not be checked: it composes from the ring's countdown and the word "Resting" with a button trait on the container, which is plausible and unverified, because VoiceOver cannot be driven from this session any more than the simulator can be rotated. Both want ten minutes on the phone, not another firing here. |
| The exercise chart's y-axis | Which of two readings it should give | Rendered 2026-08-20 with three sessions of bench at 185, 195, 205 lb. The axis runs 0–300, so a 20 lb gain — the thing the chart exists to show — is drawn across about 7% of the plot height and reads as flat. **Nobody chose this**: there is no `chartYScale` anywhere, so the domain is SwiftUI Charts' default, which happens to include zero. Zero-based is honest about magnitude; a fitted range shows the change. Both are defensible, which is why it is here. |
| The account's baseline rows | Which of three phrasings | They read `Barbell Bench Press — 205 lb × 5` in a list whose left column otherwise names a *fact*, with nothing saying these are starting points rather than current bests. Put as three options and redirected into the architecture question above; the phrasing falls out of step 4. |

**The phone was unavailable from 2026-08-20 morning.** Commits from `68c3d60`
onward are built and tested but not installed on it. `1e697db` is the last build
it ran.
