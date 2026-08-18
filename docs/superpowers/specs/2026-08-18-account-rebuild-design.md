# Account — Rebuild

**Date:** 2026-08-18
**Status:** Approved, building
**Supersedes:** the Account screen as built in `AccountView.swift` (226 lines)

## What the page is for

One sentence, because it has been drifting: **it shows what Claude knows about
the lifter, and holds the two preferences that are the lifter's rather than the
plan's.**

The app asks nothing. Every training fact on this page arrived because he told
Claude and Claude wrote it down. That is the page's whole premise and the reason
it is read-only, and the layout has been leaving it to a sentence to say.

## What is wrong

**It mixes three contracts and draws them identically.**

| Content | Contract |
|---|---|
| Goal, experience, constraints, bodyweight, equipment, session length, strength baselines | Claude's record. Read-only. |
| Units, rest timers | The lifter's preferences. His to change. |
| Delete All Blocks | Destructive. |

All three get the same panel, the same row height, the same weight. Nothing on
the page says which is which, so a toggle he owns sits at the same rank as a
fact he cannot edit and a button that destroys his history.

**The prose is load-bearing because the structure is not.** Four explanatory
paragraphs are threaded between the panels, and each exists to say something the
grouping should have said for free. *"Claude records these as you tell him; the
app only shows them"* is explaining that a section is read-only. That is why
they read as scattered: they are compensating for an absent hierarchy, not
adding to one.

**The rows are inverted.** `LifterFactRow` leads with the value and puts its name
underneath — *"Build strength / Goal"*, *"182 lb / Bodyweight"*. Six rows of
different-length values share no left edge, so there is no column to scan. The
exercise detail page already does the opposite and reads better for it: label
left, value right.

**Six identical accent discs.** They fail the test the exercise headers were held
to: the label already names the fact, so the glyph distinguishes nothing. A mark
identical everywhere it appears is decoration.

## The rebuild

### Three groups, visibly different

1. **What Claude knows** — the record, read-only. The facts, and the strength
   baselines folded in rather than kept as a section of their own: a baseline is
   another thing Claude knows about the lifter, not a different kind of thing.
   *Not yet said* belongs here too — it is the same subject from the other side,
   and it tells him what to go and tell Claude.
2. **Preferences** — units and rest timers. His, and editable.
3. **Data** — Delete All Blocks, alone at the bottom.

### Row shape

`LabeledContent`: label left in `barbellSupport` muted, value right in
`barbellSupport` ink, wrapping rather than truncating when a constraint runs
long. No icons. Identical to `ExerciseAboutSections`, which is the point — a
fact about a movement and a fact about the lifter are the same kind of statement
and should not be two designs.

`LifterFactRow` keeps `value` and `label` and loses `systemImage`. Nothing else
reads that field.

### Prose: four notes to one

| Note | Fate |
|---|---|
| "Claude records these as you tell him…" | **Kept, moved.** It states the app's premise, so it belongs under the group's heading where it frames what follows, not under the panel as a footnote. |
| Units — "sets you already logged keep their unit" | **Kept, compressed.** Genuinely non-obvious, and prevents a lifter thinking his history was rewritten. |
| Rest Timer — "when off, checking a set off starts no countdown…" | **Deleted.** It restates what a toggle labelled *Rest timers* already says. |
| Delete All Blocks — "deletes every block and every set logged against it…" | **Deleted from the page.** The confirmation dialog says it, and that is the moment it matters. Saying it twice makes neither saying count. |

### Not yet said

Stays, as a line under the record rather than a panel of its own. It is not a
record — it is the absence of one — and wrapping absence in the same panel that
holds facts claims it is one of them.

## What must not change

- **Nothing on this page becomes editable.** Every training fact stays read-only;
  the app asks nothing, and a form here would be the app asking.
- Units and rest timers stay editable, because neither is a training decision:
  one is how a number is drawn, the other is whether the lifter's own phone
  beeps.
- A profile that has been told nothing still reads as *not known*. `nil` and `[]`
  stay distinct all the way to the screen.
- `AccountRecord`'s exclusions hold: it converts no weight, decides nothing about
  training, and substitutes no value for one that is absent.

## Out of scope

- Weigh-in history as a chart or a list. The record shows the latest and says
  when it was taken; a history is a different screen and nobody has asked.
- Editing anything from here.
