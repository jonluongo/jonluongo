# Supersets — Design

**Date:** 2026-08-17
**Status:** Awaiting owner greenlight
**Extends:** `2026-08-16-interface-design.md`

## What a superset actually is

Two or more exercises performed back to back, **resting only after the group**.
That last clause is the whole definition — remove it and a superset is just two
exercises in a row, which the format already expresses.

It generalises: two is a superset, three a tri-set, more a giant set or a
circuit. They are the same structure with different counts, so the design should
carry a **group of any size** rather than a special case for pairs.

The unit of work becomes the **round**, not the set: round one is A1 then A2,
round two is A1 then A2 again.

## The requirement

> "They shouldnt be hardcoded in but the ai should be able to incorporate them
> if it wants and the ui should be intuitive"

So: the app never decides that anything is a superset. Claude does, or does not,
and the app renders whatever arrives. No app-side grouping heuristic, no
"exercises sharing a muscle are probably a superset" — that would be the app
deciding how someone trains.

## The format

A day's `exercises` is a flat list today. An entry becomes **either an exercise
or a group**:

```json
"exercises": [
  { "exerciseID": "barbell-bench-press", "sets": 4, "repRange": "6-8" },
  { "group": [
      { "exerciseID": "dumbbell-fly",    "sets": 3, "repRange": "12-15" },
      { "exerciseID": "cable-rope-pushdown", "sets": 3, "repRange": "12-15" }
    ],
    "restSeconds": 90
  }
]
```

**Why this shape and not the alternatives.**

A `groupID` field on each exercise — the obvious minimal change — makes an
invalid state representable: two exercises claiming the same group from opposite
ends of a day, or a group of one. Nesting makes both unsayable, and order is
inherent rather than asserted.

A parallel `supersets: [[Int]]` referencing positions is worse again: two
sources of truth, and indices that rot the moment an exercise moves.

**It also matches a decision already made here.** `sets` is either a count or a
list, distinguished by JSON type, chosen because "the count *is* the list's
length, so a contradiction cannot be written at all." Same reasoning, same
shape: one key, two forms, no way to disagree with itself.

**Rest belongs to the group**, because that is what a superset means. An
exercise inside a group carrying its own rest is a contradiction, and should be
refused by name the way every other unknown or impossible key already is.

## The store

`PlannedExercise` gains a group identity and a position within it. A separate
`SupersetGroup` model would be more literal but adds a relationship and a
CloudKit record type to express something two optional columns already say, and
the owner has asked for minimal six times.

Rest moves to the group: a grouped exercise's own rest is absent, and the
group's rest runs after the round.

## The interface

**One card per group**, not one per exercise. The card is the group because the
group is the unit of work.

**Use the notation lifters already know: A1 / A2.** It is the standard way a
superset is written on paper and in every program a lifter has followed. The
first group in a day is A, the second B; the exercise's position within it is
the number. This is borrowed vocabulary, not invented — the same argument that
took the `SET · PREVIOUS · LBS · REPS · ✓` table from Strong and Hevy.

**Rows interleave by round.** Round one shows A1 and A2 together, then round
two. A lifter mid-superset needs to see what is next in the round, not the whole
of A1 followed by the whole of A2.

**Rest runs when the round completes**, not when a set does — which is the one
behavioural difference the logging screen has to get right, and the thing that
makes the grouping worth expressing at all.

**A group of one cannot happen** because the format forbids it, so no screen
needs to handle it.

## What must not regress

- An ungrouped exercise renders exactly as it does now. The common case must not
  pay for the rare one.
- A plan written before this change still imports — the format is additive, and
  a newer document version is already refused whole rather than half-read.
- The prescription-fidelity chain holds: per-set loads, ramps, drop sets,
  intensity and timed or carried work all still reach the screen unaveraged.
- Editing a group's rest timer changes what runs, never what Claude prescribed.

## The snapshot

Claude must read back what was actually done, including the grouping — a
superset logged as six unrelated sets loses the fact that they were performed in
rounds, and the coach cannot judge a session he cannot see the shape of.

## Out of scope

- Circuits with a prescribed time cap, EMOM, and other work measured by the
  clock rather than by rounds. The structure here would carry them; the words
  for them are a separate question and nobody has asked.
- Any app-side suggestion that something *should* be a superset.
