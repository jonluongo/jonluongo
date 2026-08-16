# Barbell — Interface Design

**Date:** 2026-08-16
**Status:** Approved by owner
**Extends:** `2026-08-15-mcp-coaching-architecture-design.md`

## What this app is, for interface purposes

Barbell carries a prescription into a gym and brings back a record. The
prescription was written by a coach who knows the lifter and who will read the
result.

That sentence contains everything the interface has to get right, and it is what
makes copying Strong or Hevy the wrong move. They are logbooks for training you
chose yourself. Nobody wrote it for you, nobody is going to read it, and nothing
in them has an author.

Three consequences follow, and they drive every decision below.

**The coach has something to say.** `PlanDocument.notes` — a block-level note in
the coach's own words — is currently **discarded at import** and never stored.
It is the most distinctive content in the product and the screen has no place
for it. Fixed here.

**The lifter has something to say back, and currently cannot.** The loop is
Claude prescribes, the lifter logs numbers. There is no way to record *"left
shoulder felt wrong on set three."* The app is the record; a record that can only
hold integers is not much of one. Adding the lifter's voice to the loop is the
highest-value thing in this document.

**The app decides nothing, so it must not pretend to.** Fitbod offers "Switch
exercise" and "Find alternatives" because Fitbod is the coach. Ours is not, and
an "ask Claude" button would be a lie — the app cannot reach him. The honest
path is that the lifter writes it down and the coach reads it next conversation.

## Governing principle

**When in doubt, lighter.** A straightforward screen beats a complete one. Every
element must earn its place against the state it is in most often: a person
standing up, one-handed, mid-set, glancing.

## What we take from the leaders, and what we do not

Verified against Strong, Hevy, and Fitbod.

**Take:** the set row convention — `SET · PREVIOUS · WEIGHT · REPS · ✓`, set
number as a chip, previous in grey, checkmark on the right. It is universal and
users have muscle memory for it. Take Hevy's visible **"W"** for warmup sets
(ours is a hidden toggle on the set number where a mis-tap silently deletes a
set from Claude's data). Take Hevy's **column changing with the measure** —
`TIME` instead of `LBS · REPS` for a hold — which is what `WorkMeasure` already
models. Take Fitbod's **"My Plan ›"** header link rather than a calendar tab.

**Do not take:** one-exercise-at-a-time (Fitbod) hides what is coming, and in a
prescribed session the lifter wants to know whether they still need the rack.
Do not take Strong's everything-expanded scroll either — the audit measured the
current set as "the first row that is not green," 25 rows deep.

**Do not take, at all:** levels, ranks, streaks, XP, social feeds. One reference
app spends a third of its logging screen on *"This exercise does not support
ranks yet."*

## Flair: where the rule bends

The standing rule is that styling is a skin, not a mechanic. It stays. No
points, no streaks, no badges, no celebrating an achievement the app decided on
— the app decides nothing, including what counts as a win.

**One deliberate exception, argued rather than assumed.** Completing a set today
changes a row's background tint. The lifter just moved weight; the interface
answers with a colour. Feedback for a physical act is not a game mechanic, and
it matters *more* when the lifter is not looking closely. So: real haptics and a
decisive transition on set completion, and a moment at the end of a session
rather than the screen simply stopping.

Related, and information rather than decoration: **a deload week should look
different, because it is different.**

## Screens

### Today — the front door

The app currently has **no concept of what day it is**. Every week of a block
renders identically and the lifter must work out where they are. That is the
root of the problem, not a missing feature.

Five states, each answered plainly:

| State | What the lifter sees |
|---|---|
| No plan yet | One line: ask Claude for a block. Nothing else. |
| Training day, not started | Today's session and a way to begin. |
| Session in progress | Resume, at the set they left. |
| Rest day | "Rest day", and what is next. Rest is information, not absence. |
| Block finished | What was done, and that it is time to ask for the next one. |

Roughly 40% of days are rest days. That state is not an edge case and must not
render as an empty screen.

Header carries the block and the week — *"Week 2 · Accumulation"* — and is the
tap target for the block view. A link, not a tab.

### The block

Weeks as a list, each with its label and deload marked; a week opens to its
days. **Not a calendar grid.** Training is dense and patterned, not sparse and
irregular, so a month of mostly-empty cells costs space to show less than a week
does — and cannot express "week 4 is a deload", which is the thing worth
knowing.

### Logging — the screen this app exists for

**The current exercise is expanded; every other exercise is one line.** Neither
Strong nor Fitbod does this. It falls out of our sessions being prescribed
rather than improvised: the shape of the session stays visible, and the work in
front of the lifter is unambiguous.

The session's coach note sits at the top in real type, not a grey caption.

**The set row** is ours, because our prescriptions carry more than any reference
app supports:

- set number, or a visible **W** for a warmup
- previous performance, grey
- weight
- reps — or time, or distance, per `WorkMeasure`
- completion control, **44pt minimum** (currently 30×28, with no VoiceOver
  label)

Per-set intensity and per-set notes belong **on the row they describe**. Today
they float above the table and are off-screen by the time the lifter reaches
that set.

**Intensity entry appears only when the prescription names an intensity
target.** Claude reads `LoggedSet.rpe` today but no screen can write it — a
one-directional loop. Closing it costs a field; making that field permanent
would cost every row, on every screen, forever. Conditional, per the lighter
rule.

### The record

Everything Claude knows about the lifter — profile, equipment, baselines,
bodyweight — is currently **invisible in the app**. The lifter can tell Claude
they weigh 185 and never see it again. Session history does not exist either;
only per-exercise trends. Both are the app's own job as the record.

## Design system

The audit measured **12 distinct spacing values** across 37 sites, 18 off a 4pt
grid; **18 type treatments** across seven base styles for six screens; and nine
visual patterns implemented more than once, one pair already diverged six ways.

- **Spacing:** 4 / 8 / 12 / 16 / 24. Nothing else.
- **Type:** five roles — Metric, Title, Body, Support, Label.
- **Targets:** 44pt minimum, everywhere, no exceptions.
- **Dynamic Type** throughout. One control is currently a fixed 11.4pt.
- Extract the duplicated patterns once each.

Already good and not to be redone: zero colour literals, colour never the sole
carrier of meaning, correct safe-area handling.

## Out of scope

- In-app chat. The conversation is in Claude.
- Any app-side training decision, including exercise substitution.
- Apple Watch.
