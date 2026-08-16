# The Local MCP Loop — Design

**Date:** 2026-08-15
**Status:** Built. **The two document formats described below are narrower than
what shipped** — see "What changed on 2026-08-16" at the end. The loop, the
layering, and the reports-not-verdicts rule are all live and accurate.
**Extends:** `2026-08-15-mcp-coaching-architecture-design.md`

## The loop

```
  Claude (desktop)                          the app (iPhone)
        │                                          │
        │  reads snapshot.json  ◀──────────────────┤  exports on background
        │                                          │
        │  writes plan.json     ──────────────────▶│  imports, shows tables
        │                                          │
        │                                          │  lifter fills them in
        └──────────────── next conversation ◀──────┘
```

You talk it through with Claude, Claude writes a plan, the plan appears on your
phone as workout tables, you fill them in at the gym, and the next conversation
reads what actually happened.

The app supplies data and an interface. It decides nothing.

## Why local first

A connector in the Claude app is a **remote** MCP server: a public HTTPS
endpoint with OAuth. That requires hosting, auth, and — the expensive part —
moving training data somewhere a server can read, because a server cannot reach
a user's *private* CloudKit database.

That is a service, not a feature. It is the right end state if this becomes a
product; it is the wrong thing to build before knowing whether the coaching is
any good.

Local costs days and answers that question with real training. **Nothing built
here is thrown away when it goes remote:** the tools, the snapshot format, and
the plan format are identical. Only the transport changes, which is why the
transport is isolated behind its own boundary (see below).

**The accepted limitation:** a local server is reachable by Claude on the Mac,
not by Claude on a phone in the gym. So the rhythm is **plan at the desk, train
at the gym**. That matches how programming actually works — nobody redesigns a
block mid-session.

## Shared Swift package

`Domain/` imports only Foundation; `Catalog/` imports only Domain. That is what
makes them liftable, and this is the payoff.

**In the package:** the taxonomies, `Exercise`, `Mass`, `RepRange`,
`EquipmentAccess`, the exercise catalog and its resolver, and the two file
formats below.

**Not in the package:** the SwiftData models. The server never touches
SwiftData — it reads a snapshot file. Putting `Store/` in the package would
drag SwiftData into a command-line tool for no reason.

So the package is the shared *vocabulary*: what an exercise is, what a weight
is, and what the two documents look like. Two clients — the iOS app and a macOS
executable — cannot disagree about any of it.

## The two documents

Both are versioned, exactly like `exercises.json`, and both carry the
`catalogVersion` they were produced against.

### `snapshot.json` — app to Claude

Profile (equipment access, experience, constraints, preferred days and session
length), body metrics, strength baselines, every plan, and every logged set with
its load, reps, RPE, and timestamp.

Written **automatically when the app backgrounds.** Never behind a button —
stale data makes a coach confidently wrong, which is worse than absent data
because it does not look like absence.

Size is a non-issue: years of lifting is a few hundred KB.

### `plan.json` — Claude to the app

A plan exactly as Claude wrote it: exercise IDs from the catalog, and sets,
reps, rest, load, and notes as given.

**The import does exactly one thing beyond decoding: it confirms each
`ExerciseID` exists.** Not because Claude is untrusted, but because history is
keyed by exercise identity and an unknown key would fragment a lift's history
irreparably. It does not cap sets, fill in a rep range, or reject a plan for
being unbalanced.

An unknown ID fails the import loudly with the offending ID named, rather than
silently dropping an exercise.

## Imports never destroy

A new plan is a new plan. An adjustment **supersedes** rather than overwrites,
so the previous plan and everything logged against it survive.

This is not the app second-guessing Claude — it is the app not losing data.
There is no approval gate and no confirmation dialog: Claude is the decision
maker, and friction there would be the app arguing with it.

## Transport, isolated on purpose

The Mac writes a file the iPhone must see. The app's iCloud container currently
enables **CloudKit only**; adding the **iCloud Documents** scope gives a folder
both machines see under the same Apple ID, with Apple doing the syncing that is
already happening for everything else. No backend, no auth, no server.

**Transport lives behind one protocol** with a single implementation today.
When this goes remote, that protocol gets a second implementation and nothing
else changes. This is the one seam whose future is known, which is what
justifies it now rather than being speculative.

## The MCP server

A macOS executable speaking stdio MCP, depending on the package.

**Resource** — a compact always-present context: who the lifter is, equipment,
constraints, current block, recent sessions, current working weights.

**Tools**, every one of which *reports* rather than concludes:

| Tool | Returns |
|---|---|
| `list_exercises(pattern:muscle:equipment:)` | Catalog entries with real IDs, filtered to what the lifter can actually perform |
| `exercise_history(id:)` | Every logged set for one movement, in order |
| `recent_sessions(limit:)` | What was done lately |
| `volume_by_muscle(weeks:)` | Set and rep totals per muscle |
| `write_plan(plan)` | Writes `plan.json`; returns the resolved plan or a named error |

There is deliberately no `suggest_progression` or `check_balance` returning a
verdict. Reporting that a lift has not moved in four weeks is data. Deciding
what to do about it is Claude's job.

`list_exercises` is what makes hallucinated IDs impossible in normal use:
Claude picks from returned entries rather than typing a name.

## Verification

The end-to-end test is a real one: write a plan through the MCP server, confirm
it lands in the app, log a session against it, background the app, and confirm
the new sets appear in the snapshot the server reads back.

Unit coverage sits on the two formats — round-trip encode/decode, unknown-ID
rejection, superseding rather than overwriting, and a snapshot containing a
plan that references a since-renamed exercise.

## Out of scope

- Hosted MCP, OAuth, connectors — the end state, deliberately deferred.
- In-app chat.
- Any app-side training decision. Still the standing rule.
- Bidirectional live sync. Two documents, each written by exactly one side.

## What changed on 2026-08-16

The loop above was built and then used, and four audits found the same fault
throughout: **nothing in it decides anything, but the vocabulary is too narrow to
coach in, and narrowness is silent.** The plan is
`docs/superpowers/plans/2026-08-16-open-the-format.md`. The sections above are
left as written; what follows is what is true instead.

**`plan.json` is a block, not a week.** "sets, reps, rest, load, and notes as
given" was the whole of it. `PlanDocument` is now version 3 and carries `weeks`,
each with its own days, optional label, and `isDeload` flag. Periodization,
wave loading and a deload were unsayable before — and `weekCount: 8` was
accepted, echoed back as success, and imported as one week, so seven weeks
vanished in silence. A week's ordinal is its position; a stated `weekCount` is
now checked against the weeks present rather than believed.

**A prescribed exercise's sets may differ from one another.** `sets` is a count
or an explicit list, which is how a drop set, a ramp, a back-off set and a
per-set note are said. `intensity` states an RPE, a reps-in-reserve target, a
percentage of a one-rep max, or a scale this build has never heard of — carried
as a scale plus a verbatim value, never converted or bounded. Prescribed effort
can now be compared with the RPE the lifter logged, which the snapshot already
reported and nothing could ever set.

**"The import does exactly one thing beyond decoding" is no longer true, and
deliberately so.** It still confirms every `ExerciseID`, for the reason given
above. It now also refuses a key the format does not have, naming it and where
it sat, and refuses a document from a later format version whole. Silently
dropping a key was worse than rejecting it: the writer is told "Written" and
believes the prescription landed. `DocumentRefusal` in LiftingKit is the single
implementation, so the server and the phone cannot disagree about what is
acceptable.

**The snapshot's profile no longer has an equipment tier.** "equipment access"
above meant one of four closed tiers, which could not express a garage gym —
`fullGym` granted 109 machine and cable exercises the lifter cannot do and
`homeMinimal` denied all 66 barbell ones — and an unrecognized tier value
rejected the entire document, violating the extensible-taxonomy rule at the
exact point Claude was recording a fact. The profile now carries an open set of
`EquipmentType`. Tiers remain as input shorthand that expands at the boundary
and is never stored, so an unrecognized one cannot reject anything.

**There is a sixth tool, and it can write what it reads.** `update_profile`
records bodyweight as a dated series and strength baselines keyed on the lift —
both were read by `ContextReport` and writable by nothing, so Claude was
permanently told the lifter had no weight and no strength anchor, and a first
plan had nothing to set a load against. `experience` is an extensible taxonomy
rather than three fixed words.

**The estimated one-rep max is gone from the app.** Choosing Epley over Brzycki
is itself a training opinion, and its only consumer drew a verdict — a green
arrow telling the lifter he was getting stronger. The history chart plots the
heaviest set actually logged instead. Claude has every logged set and can
compute whatever estimate he thinks is right.

Still out of scope, and still true: supersets and circuits as *structure*, and
logging a hold in seconds. A timed prescription now travels correctly end to
end and is no longer misread as a rep count, but `LoggedSet` counts reps, so
there is nowhere to record that a 30-second plank was held for 34.
