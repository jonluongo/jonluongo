# Dated statements

**Status: steps 1–3 built and shipped on 2026-08-20. Step 4 is waiting on the
owner.** What follows is the shape as designed; where it was built, the commits
are named. Read it for the reasoning — particularly *What this is not*, which is
what stopped three plausible versions of this from being built instead.

## The problem

The store holds four kinds of fact about the lifter, in three different shapes.

| Fact | Shape today | Honest? |
|---|---|---|
| Logged sets | flat dated series | yes |
| Strength baselines | dated records (`recordedAt`) | yes |
| Bodyweight | dated series (`BodyMetric`) **plus** a copy on the profile | half |
| Goal, experience, constraints, equipment, training days, session length | mutable fields on `UserProfile`, **one shared `updatedAt`** | no |

The last row is the problem. Six facts share one timestamp, so an update to the
goal today restamps a constraint stated eighteen months ago. Nothing anywhere
can answer *when did he say this?*

That matters because the coach makes every training decision and the app makes
none. "Left shoulder is touchy overhead" said last week means program around it.
Said eighteen months ago and never mentioned since means ask him. Those are
different instructions and the record cannot tell them apart.

The vestige of trying to answer this with one number is already on the wire:
`SnapshotProfile.updatedAt` is exported and **no MCP tool reads it**. A
whole-record timestamp cannot mean *when this fact was stated*, so nothing could
honestly report it.

## The shape

**A statement is an observation with a date.** That already describes a logged
set, a weigh-in and a baseline. Extend it to the six and every fact in the
system has the same shape, which is what lets the coach reason over all of them
the same way.

The document to keep is one that already exists. `ProfileUpdate` arrives with
its own `id` and `generatedAt`, the app records `appliedProfileUpdateID`, and
then the document is discarded. Keep them as a flat dated series — the shape the
training log already has — and *what he last said about X, and when* falls out
by reading back. **No new per-field columns.**

## What this is not

Three things this deliberately does not do. Each is the seductive version of
"everything the same way", and each costs something the project has already paid
for once.

**Not a generic `(key, value, date)` table.** It would take the types with it:
`Mass` stops being `Mass`, equipment stops being a list, and the refusal
machinery — the one thing this app insists on — loses its grip on what a value
is. Uniform shape, typed content.

**Not event-sourcing the plan.** Prescriptions are documents. `decided.md`
records that a prescription living in three vocabularies cost a rewrite, and
`PlanImporter.merge` already holds the right rule: a trained block cannot be
rewritten. Only *statements about the lifter* become a series.

**Not replacing the profile with a lookup.** The profile is read on every screen
render; folding a series each time is the wrong trade. Bodyweight already shows
the right pattern — the series is the record and the field is the latest value.
Make that one-way and stated, and it is a projection rather than a second source
of truth.

## What follows

1. **Store.** ✅ `ce005d7`. `ProfileStatement` records which facts an arriving
   update spoke to and when the coach wrote it, `ProfileUpdate.keysStated` names
   them from the wire's own vocabulary, and `StatedFacts` reads them back. It
   holds the keys and the dates, not the values: the profile already carries
   what is true. Named right the first time, so it needs no part of the `@Model`
   rename held open elsewhere in `decided.md`.
2. **Wire.** ✅ `8edeac2`. `SnapshotProfile.statedAt` carries a date per fact and
   the context resource reports it. `updatedAt` went in the same bump — it moved
   whenever any fact changed and no tool ever read it. Snapshot version 4 → 5,
   because the shape lost a field rather than gaining one; absence of `statedAt`
   decodes as *no dates on record*, which is what every install predating this
   has.
3. **Tools.** ✅ `0b69ab7`, `c805d2c`, `077d2c4`. Every stated fact in
   `unstated_facts` carries when he last said it, `null` where the record
   predates the dates. The server passes no verdict — a test asserts the note
   says nothing about staleness, because the temptation to add one later is
   exactly what this server is built not to do. Both tool descriptions were
   corrected to match: one had promised "empty fields and nothing more", and the
   other never mentioned that it is where the dates come from.
4. **Screens.** The account page qualifies each fact inline, the way Bodyweight
   already carries its date. That also answers the baseline rows, which read
   `205 lb × 5` with nothing saying it was a starting point rather than a
   current best — the question that started this.

Step 4 is where two designs are defensible and the owner's call is needed. Steps
1–3 were not visible to the lifter and landed first. They were also driven end
to end through the real files — two hand-written `profile-update.json`
documents, a March one and an August one, taken in by the app and read back by
the release binary — and the March constraint kept its March date while the
August goal took August. Under `updatedAt` both would have read August. See
*Settled by investigation* in `decided.md`.

## The one it does not fix

Ticking a set prescribed as a range without typing a number logs **0 reps**.
`RepPrescription` is right to seed nothing for a range — choosing an end of it
would be the app deciding how hard to train — but `LoggedSet.reps` is a
non-optional `Int`, so *he did not say* and *he did none* are the same value.
The coach reads a completed working set at 185 lb × 0.

The fix is making `reps` optional, matching `durationSeconds` and `distance`,
which are optional for exactly this reason. It is a store change and a format
bump, so it belongs in the same piece of work — but it is a separate decision
and should be taken separately.

Until it is taken, the wire is at least honest about the shape: `bff347a`
changed `exercise_history`'s description from claiming a hold or a carry reports
"no reps" to stating that `reps` is 0 there and that the 0 means *not counted in
reps*. That does not make `0` a good answer for a set he ticked without typing —
it makes the ambiguity visible instead of hidden, which is the most that can be
done without the store change.
