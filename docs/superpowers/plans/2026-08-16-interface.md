# Barbell Interface — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Rebuild the interface around what this app actually is — a prescription carried into a gym and a record brought back — with a coherent visual system underneath it.

**Spec:** `docs/superpowers/specs/2026-08-16-interface-design.md`. Read it first; it carries the reasoning.

**Baseline:** LiftingKit 256/20 · LiftingMCP 215/21 · app 207/24.

## Global Constraints

- **The app makes no training decisions and asks the lifter nothing about training.**
- **Record what you are given.** No clamping, defaulting, or substituting a prescribed value.
- **When in doubt, lighter.** A straightforward screen beats a complete one.
- **Spacing scale: 4 / 8 / 12 / 16 / 24.** Nothing else. **Tap targets ≥ 44pt.** **Dynamic Type** throughout — no fixed point sizes.
- **No gamification:** no points, streaks, badges, levels, XP, or celebrating an achievement the app decided on.
- Layers import only downward: LiftingKit → Store → Services → Views.
- Errors handled or propagated. No force unwrap/try/cast outside tests.
- Swift 6, strict concurrency, warnings are errors. Files past ~300 lines are a signal.
- Swift Testing, never XCTest.
- Never hand-edit `project.pbxproj`. Never revert `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_KEY_UIBackgroundModes`, `ASSETCATALOG_COMPILER_APPICON_NAME`.
- `BarbellIcon.icon/**` is the owner's work — never touch or stage it.

---

### Task 1: Two correctness bugs, before any pixels

Both are the "silently discarded" class this project has fixed repeatedly. Neither is cosmetic.

- **`PlanDocument.notes` is discarded** at `PlanBlueprint.swift:216` — the coach's own words about the block, accepted and never stored. Store it, and store `TrainingPlan.title`, which is stored but never rendered.
- **`LoggedSet.rpe` is exported to Claude but no screen can write it.** Give it a write path (UI lands in Task 5).

Tests: a note survives import and reaches the store; an RPE written in the app reaches the snapshot.

### Task 2: The design system

Create the spacing scale, type ramp, and the components the audit found duplicated — worst is an icon-circle row implemented twice and already diverged six ways (36 vs 44 circle, 0.15 vs 0.12 fill, `.caption` vs `.subheadline`).

- Spacing: 4 / 8 / 12 / 16 / 24, named. Corner radii: one small, one large.
- Type: five roles — **Metric** (`.title2.bold.monospacedDigit`), **Title**, **Body**, **Support**, **Label**.
- Extract each duplicated pattern once.
- Fix the fixed-size control (currently 11.4pt, ignores Dynamic Type).

**Do not restyle screens yet.** This task creates the vocabulary; later tasks spend it. Apply it mechanically where a value already exists, and report every site where the nearest scale value changes the layout meaningfully.

### Task 3: The app learns what day it is

Nothing in the app knows the date — the root cause behind the whole restructure.

Build the derivation: given a block and today's date, what is today? Which week, which day, is it a rest day, is the block finished, is a session already in progress?

**Pure logic, no UI.** It belongs where it can be tested without a simulator. Cover: a training day, a rest day, the first day, the last day, a finished block, a day outside the block, and a session already started.

### Task 4: Today

The five states from the spec, each rendered plainly:

| State | Screen |
|---|---|
| No plan | One line: ask Claude for a block |
| Training day | Today's session, and a way to begin |
| In progress | Resume where they left |
| Rest day | "Rest day" and what is next |
| Block finished | What was done, and to ask for the next |

Header shows block and week (*"Week 2 · Accumulation"*) and opens the block view. Replaces the Plan tab as the front door.

**Rest days are ~40% of days.** That state gets the same care as a training day.

### Task 5: The logging screen

The screen this app exists for, and the one with the worst findings.

- **Current exercise expanded; every other exercise collapsed to one line.** The session's shape stays visible; the current work is unambiguous.
- **The set row**: set number or a visible **W** for warmup; previous in grey; weight; reps *or* time *or* distance per `WorkMeasure`; completion control **≥44pt** with a VoiceOver label (it is currently 30×28 with none).
- **Per-set intensity and notes render on their own row**, not floating above the table.
- **Intensity entry appears only when the prescription names an intensity target.**
- Replace the hidden warmup toggle on the set number — a mis-tap currently deletes a set from Claude's data silently.
- Keyboard: a dismiss affordance on the number pad (there is none).
- The session's coach note at the top, in real type.

**Do not** average a ramp, collapse a rep range, or fill an absent value — that chain is correct and the audit said to leave it alone.

### Task 6: The lifter's voice

Today the lifter can only send integers. There is no way to record *"left shoulder felt wrong on set three."*

Add a note the lifter can attach to a set or an exercise, reaching the snapshot so the coach reads it next conversation. This is the honest alternative to an "ask Claude" button the app cannot honour.

Keep it light: one unobtrusive affordance, no second keyboard in the middle of a set.

### Task 7: Feedback at the moment of effort

The deliberate exception to the no-flair rule, argued in the spec.

- Haptics and a decisive transition on set completion — the lifter may not be looking closely.
- A moment at the end of a session rather than the screen stopping.
- A deload week looks different because it is different.

**Still no** points, streaks, badges, or celebrating an app-decided achievement.

### Task 8: The record

Everything Claude knows is invisible in the app: profile, equipment, baselines, bodyweight. Session history does not exist — only per-exercise trends. Superseded blocks are unreachable.

Make the record visible. Read-only: the app displays what it holds; Claude writes it.

### Task 9: Retire what the restructure replaces

`SessionDetailView` is a read-only preview of a screen that is already editable. Delete what Today and the block view subsume, and remove any copy describing capabilities the app no longer has.

---

## Sequencing

1 and 2 first (correctness, then vocabulary), then 3, then 4 and 5 — the two screens that matter. 6 and 7 refine them. 8 and 9 last.

Verify all three suites and a device build after each task. Install to the owner's iPhone when the loop's screens change; the in-gym screen cannot be judged in a simulator.

## Out of scope

In-app chat. Any app-side training decision, including exercise substitution. Apple Watch.
