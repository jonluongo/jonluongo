# Big Picture — Sprint Plan

**Date:** 2026-08-18
**Status:** Closed. Every numbered item is done except 2.3, which is Jon's
decision and annotated in place. Tier 3 stays parked.
**Context:** The app was rebuilt today from three tabs and a preview-plus-sheet
into one screen: the session he is in. That deleted a lot and moved more. This
plan is what the redesign left open, ordered by what can hurt.

## The shape of the debt

Three kinds of work, and they are not interchangeable:

1. **Regressions the redesign introduced.** Things that were right yesterday and
   are wrong now. These come first because they are my errors, not decisions.
2. **Never-looked-at.** Code that compiles and is tested and has never been
   rendered. Every defect the owner caught in the last stretch was in this
   category — the pattern is exact and worth stating: *what I screenshotted was
   right; what I only compiled was wrong.*
3. **Deferred product decisions.** Real questions with no answer yet. They are
   last because none of them is blocking and each needs the owner.

---

## Tier 1 — Regressions

### 1.1 A hold or a carry no longer says what it is measured in

`SetTableHeader` named the second column after the unit its rows actually
record: `REPS`, `SECS`, or the carry's own distance unit. It is deleted. The
prescription still reaches the lifter as the placeholder — a plank shows
`30 seconds` in the empty field — but the moment he types `34`, nothing on the
row says seconds.

**This is the exact failure the `WorkMeasure` work existed to prevent.** The
store is still correct: `SetRowView` writes `durationSeconds` for a hold and
`distance` for a carry, decided by the prescription, so no number lands in the
wrong column. What broke is what the *lifter* can see. A row reading `34 × ` is
ambiguous in a way `135 × 8` is not.

**Fix:** the unit belongs beside the figure, not above the column. For counted
work the `×` already says it. For a hold and a carry the row should read
`34s` / `40 m` — one suffix, on the one row that needs it, and nothing added to
the common case.

### 1.2 Supersets have never been seen under the new row

`SupersetLogSection` lost its column header and gained the stripped row, and no
group has been rendered since. The A1/A2 notation sits in the column the set
number now occupies. **Likely wrong, unverified either way.**

### 1.3 Finishing a session removes it from the pager

Correct — a logged session is no longer "remaining" — but it means the screen
changes under the thumb at the moment he taps Finish, and nothing says what
happened. Never watched end to end.

---

## Tier 2 — Never looked at

### 2.1 Dark mode

`Palette` declares seven colours in both appearances. **Not one of them has ever
been rendered dark.** Every screen, every panel, every hairline is unverified,
and the accent-on-dark contrast is a guess.

### 2.2 Blocks and Account as sheets

Both were built as tabs and are now presented as sheets from the `⋯`. A sheet
has a different top, a different dismiss, and different safe areas. Their
`PageTitle` and hidden navigation bar were designed for a tab. Unverified.

### 2.3 VoiceOver on the new structure — **recommended for deletion, awaiting Jon**

The card that was a tap target is gone; the session is the root; the `⋯` is now
the only route to two screens. None of the new labels or traits have been heard.

**But this item is on the plan because it is on the standard checklist, which is
exactly the reasoning the rest of this project rejects.** There is one user, he
is sighted, and nobody will ever hear these labels. The honest recommendation is
to drop it as a dedicated pass, keep writing labels while building, and treat a
nonsensical one as evidence of a control doing two jobs — which is how a
workout card that was both "start the session" and "open this exercise" would
have announced itself before it looked wrong. It becomes real work the day this
goes in front of anyone else. Left standing rather than struck, because the plan
is Jon's.

### 2.4 The MCP loop, end to end — **verified 2026-08-18**

Exercised for real rather than assumed: the app's `SnapshotExporter` wrote a
snapshot from a live store, and `LiftingMCPKit` decoded that exact file and
answered questions about it — both logged sets present, with the right exercise
ID, reps, load and focus, and `isCompletedWorkingSet` true. The read half of the
loop is intact after the calendar's deletion.

The scaffolding was deleted afterwards rather than kept: a test that depends on
a file in `/tmp` written by a different target is not a test, it is a procedure,
and leaving it would have been a permanently red suite waiting to happen.

`SnapshotPlan.weekdays` survives this pass. Nothing in the app displays it, but
the server still sends it to Claude, and whether he wants it is a question for
Jon rather than a deletion to make quietly — see Tier 3.

### 2.5 Empty and edge states

No block at all; a block whose sessions are all logged; a session of one
exercise; a session of ten. The one-screen structure changed all four and none
has been drawn.

---

## What is left, and what was struck

The app is two things: a datastore, and the interface an AI trainer works
through. A parked list of six decisions was neither — it was the shape of a
product with a roadmap, which this is not. Struck, with the reason:

| Struck | Why it was not one of the two things |
|---|---|
| VoiceOver as a pass | On the plan because it is on a checklist. One user, sighted. |
| An exercise `role` | Claude prescribes a warm-up by prescribing it. A field so he can label it is a field nobody reads. |
| Barbell → Superset rename | Cosmetic. |
| Revisiting the `⋯` as sole route | Settled. Re-opening it is churn. |

What survives, and only this:

**The record's honesty.** `TrainingPlan.completedAt` means both "the lifter
finished this block" and "a later block superseded it". A field carrying two
meanings is the datastore being ambiguous about itself, which is the one thing it
may not be. Real, not urgent — it bites the first time something needs to tell
the two apart.

**Claude's vocabulary.** Whether the catalog holds the movements he reaches for.
That is answered by asking him after a few blocks, not by building a coverage
grid in advance.

**The superset vocabulary**, because Jon asked. `Superset A` / `A1` / `A2` /
`ROUND n` is a code plus the glossary that decodes it, where the layout could
show the pairing instead.

## Order of work

1. **1.1** — a visible regression in the one thing the app must not get wrong.
2. **2.1 dark mode** — cheapest to check, largest blast radius, and it is the
   only tier-2 item where every screen is affected at once.
3. **1.2, 1.3** — verify by rendering, fix what is found.
4. **2.2, 2.5** — the screens the redesign re-parented.
5. **2.3, 2.4** — a pass each.
6. Tier 3 stays parked until asked.

**Nothing here is new product.** The whole sprint is closing what today opened,
and the sequencing is deliberate: the app should be proved before it is extended.

## The rule this plan was built on, and the sharper one it produced

It began as: ship nothing that has not been rendered.

That was not enough, and the sprint proved it four times. The panel padding
reached the two screens I was looking at. The Account sections kept the system's
dividers. One sheet of three kept a Done button. A group's set rows kept a
background that overrode the panel. **Every one of those screens was rendered —
the screen I was working on. The one that broke was its sibling.**

So the rule is: **render everything the change touches.** When a modifier, a
token or a shape changes, the question is not "does this screen still look
right" but "who else draws this, and have I looked at them." A component with
two callers has two screenshots owing.

Tests hold the logic. A screenshot holds one layout. Only the list of callers
holds the app.
