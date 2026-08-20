# Dated statements

**Status: proposed, waiting on the owner.** Nothing here is built. It exists so
the decision is not re-derived from scratch, and so the day it is greenlit the
work starts from a written shape rather than a conversation.

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

1. **Store.** A model for an applied profile update, holding the document and
   the date it was generated. Named right the first time — the `@Model` rename
   held open in `decided.md` is about `TrainingPlan`/`TrainingWeek`, and nothing
   new should be added needing the same migration later.
2. **Wire.** Each stated fact reports `statedAt` beside its value. Snapshot
   format bump. `SnapshotProfile.updatedAt` goes in the same bump, since what
   replaces it is per-fact and honest.
3. **Tools.** `unstated_facts` gains the answer it cannot currently give: not
   only *nobody has said*, but *said, long ago, and worth asking again*. What
   counts as long ago is the coach's judgement, not the server's — the server
   reports the date and says nothing about staleness.
4. **Screens.** The account page qualifies each fact inline, the way Bodyweight
   already carries its date. That also answers the baseline rows, which read
   `205 lb × 5` with nothing saying it was a starting point rather than a
   current best — the question that started this.

Step 4 is where two designs are defensible and the owner's call is needed. Steps
1–3 are not visible to the lifter and can land first.

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
