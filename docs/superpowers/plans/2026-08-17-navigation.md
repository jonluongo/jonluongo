# Navigation — Implementation Plan

**Goal:** Three tabs that match what the app is for. Today for the day, Plan for the block, Settings for the record.

**Owner's instruction:** *"the first page should be home with the daily view and then instead of history there should be the plan overview specific page where you can view the whole training plan… make sure everything is being planned out and organized so that the ui is minimal and intuitive and that we are keeping the code minimal organized and intuitive as well."*

## The shape

| Tab | What it is |
|---|---|
| **Today** | The week strip, the day's session, and the one thing to do about it. Already built. |
| **Plan** | The whole block: weeks with their labels, the deload marked, the coach's note, and every session in it. `BlockView` already does this — it becomes a tab instead of a link. |
| **Settings** | What the app knows about the lifter, and the one preference that is genuinely theirs. |

## The decision this forces

`History` is the tab being replaced, and it holds **per-exercise trends** — the only place the app shows what a lift has done over time. That cannot simply be deleted; it is the record, which is half the app's job.

**It moves to the exercise.** Tapping an exercise — in a session, or in a day inside Plan — shows that exercise's history. That is where a lifter looks for it: they are reading *Barbell Bench Press* and want to know what they benched last month. A tab called History is a filing cabinet; a tap on the lift is an answer.

This also removes a screen rather than relocating one, which is the direction asked for.

## What else goes

**The block link on Today.** `BlockLinkSection` exists because the block had no other door. With Plan as a tab it is a second route to the same place, on the screen that can least afford a spare row. The week and its label still belong on Today — that is context, not navigation — so keep the words and drop the chevron and the tap.

**Anything left in `HistoryView` that the exercise view does not absorb.** Do not port a screen; port what earns its place.

## What must not regress

- The record stays reachable. Trends must be no harder to find than they are now, only found somewhere better.
- `Today` keeps opening on today, and the week strip keeps working exactly as it does.
- Absence stays absence: an exercise with one logged session draws no trend rather than a line through one point. That rule is already honoured and must survive the move.
- No screen shows the same thing as another. `SessionDetailView` was just deleted for that reason; do not reintroduce the pattern.

## Standards

The app makes no training decisions, invents no values, and asks the lifter nothing about training. Spacing scale 4/8/12/16/24, tap targets ≥44pt, Dynamic Type, no colour literals. Layers import downward only. Swift 6, strict concurrency, warnings-as-errors. Files past ~300 lines are a signal. Swift Testing, never XCTest.

**Reuse before building.** `BlockView`, `BlockWeekView`, `IconCircleRow`, `PrescribedExerciseRow`, `WeekStripView`, `CoachNoteView` and `TodayPhrasing` already exist. A new component needs a reason.

## Sequencing

One task. It is a navigation change and a move; splitting it would leave the app in a state with two Plans or no History.
