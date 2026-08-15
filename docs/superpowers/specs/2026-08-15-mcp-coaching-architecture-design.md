# MCP Coaching Architecture — Design

**Date:** 2026-08-15
**Status:** Approved by owner
**Extends:** `2026-08-14-foundation-architecture-design.md`,
`2026-08-14-workout-programming-design.md`
**Supersedes (in part):** the in-app chat interface described in
`2026-08-14-app-structure-revision.md` — see "Recorded departure" below.

## The decision

The coaching intelligence moves out of the app and into Claude, reached over
MCP. The app becomes a native training tool with a deterministic engine; Claude
reads the app's data and proposes changes to it.

Apple's on-device model stays available for what it is genuinely good at
(structured extraction from free text) but is no longer the thing that makes
this app a coach.

## Why

The product goal is a coach that manages training over time: adjusts for
injury, reads progress, judges when a load is too heavy, advises on diet.

Apple's on-device Foundation Model is roughly 3B parameters and Apple's own
guidance scopes it to focused app tasks — extraction, classification,
summarization, short generation — and steers away from open-ended expert
conversation. It is a good extractor and a poor coach. Nothing in the app's
design can compensate for that, because the gap is knowledge and reasoning
depth.

Three routes were considered:

| Route | Verdict |
|---|---|
| Fine-tune a model to be a coach | **Rejected.** No training corpus, no eval set, no quality baseline. Frontier models already carry the exercise science a fine-tune would try to install. The differentiator here is structured data and in-gym UX, not weights. |
| Hosted frontier model called from the app | **Deferred.** Requires a key-holding backend, per-user inference cost, and a privacy posture — all before it is known whether the coaching is even good. |
| **Claude over MCP** | **Chosen.** Inference is the user's own subscription, cost to us is zero, coaching quality is frontier-grade on day one, and the build is days rather than months because the layered architecture already exposes the right operations. |

MCP is chosen **as the way to find out whether this product is real**, at the
lowest cost of being wrong. If coaching over structured training data turns out
to be as useful as it looks, the in-app path is then designed against evidence:
real conversations, real failures, real knowledge of which operations matter.

## Recorded departure from the original interface vision

`2026-08-14-app-structure-revision.md` states the app's UI is "just the AI
chat," with each plan behaving like a Claude project.

**That is not what gets built now, and the owner has accepted this
deliberately.** The app has no chat. It is a plan view and a logger. The
conversation happens in Claude.

Recorded because it is the largest single departure from the original product
description and must not be re-litigated by accident. Note the departure is
partly literal fulfilment: the chat *is* Claude, and a plan genuinely does
become a Claude project.

Revisit when the proof of concept has an answer.

## One decision-maker, not two

**The app is the blocks and the record. Claude builds with them.**

Claude makes every training decision: the split, which exercises, sets, reps,
loads, what changes after an injury, when to deload. There is not a second
planner in the app arguing with it.

The app owns:

| The app owns | What that means |
|---|---|
| The blocks | 412 exercises with muscles, equipment, pattern, mechanic |
| The rulebook | Splits, slot counts, prescriptions, balance rules — versioned JSON |
| The record | Every logged set, baseline, and body metric |
| The interface | The plan view, the logger, the timer |

### Rejected: propose-and-validate

An earlier draft had Claude propose a plan and the app check it — real
exercise? owned equipment? sane load? That is guess-and-verify, and it is
unnecessary.

**Instead the app hands Claude legal options and Claude selects from them.**
Asked what is available for horizontal press, the app returns catalog entries
with their real `ExerciseID`s, already filtered to the lifter's equipment.
Claude picks one. There is no name to get wrong because Claude never types a
name.

What remains is not supervision, it is an ordinary typed interface: an
unrecognized ID returns an error the way any API does, and a write against a
stale snapshot fails with a reason. Framing that as the app "checking Claude's
work" overstated it.

### What is genuinely reserved

Only the irreversible thing: **the app is the sole writer of training history.**
History is keyed by exercise identity, so a fabricated key silently fragments a
lift's history into two unrelated series, and that cannot be repaired later.
Typed IDs make it unrepresentable rather than merely forbidden.

Note what is *not* reserved: load prescription. An earlier draft clamped load
jumps for safety. Dropped — a coach with the lifter's actual history should be
able to push hard when warranted, and a governor on that gets in the way of the
product. Good data is the better answer than a limiter.

## Architecture

### Shared Swift package

`Domain/` imports only Foundation and `Catalog/` imports only Domain. That
discipline is what makes them liftable. Both, plus the pure parts of
`Services/`, move into a Swift package consumed by two clients:

- the iOS app
- a macOS MCP server executable

One definition of exercise science, one catalog, one set of progression rules,
two faces. The rejected alternative — reimplementing the rules in a Python MCP
server — creates two sources of truth that drift, which is the exact bug class
the catalog work spent two days eliminating.

### Data flow: snapshot out, proposal in

SwiftData remains the single source of truth.

```
app ──(complete versioned snapshot)──▶ Claude, read-only
app ◀──(proposal, user confirms)───── Claude
```

**Why not one shared store both sides write:** two writers to the same records
with no conflict resolution, layered on top of CloudKit already syncing the
app's copy across devices. The failure mode is silently losing logged sets —
the one category of data that cannot be reconstructed.

**Why proposals rather than mutations:** Claude will occasionally be wrong about
how someone should train. A confirmation step is the difference between a coach
and something that silently rewrites a training program. The user sees what
changed and why, and accepts or rejects.

Nothing writes to training history except the app.

### MCP surface: a resource plus tools

A compact **context resource**, always present: identity, equipment access,
constraints, current block, recent sessions, current working weights, PRs.
Small enough to carry on every turn.

**Tools** for drill-down, so depth is paid for only when needed:
`history(for:)`, `volumeByMuscle(weeks:)`, `progressionStalls()`,
`sessionsSince(_:)`.

These are the existing `Services` operations — `PerformanceHistory`,
`ExerciseTrend`, `ProgressionEngine` — which is why the package extraction pays
for itself immediately rather than being scaffolding.

### Freshness

The snapshot exports automatically when the app backgrounds, never behind a
button. Stale data makes a coach confidently wrong, which is worse than absent
data because it is not visible as absence.

## Known crudeness, deliberately accepted

File-based transport (snapshot and proposal documents) is proof-of-concept
grade. The *pattern* — single writer, no shared mutable state, user-confirmed
change — is principled and survives. The *transport* is not, and is expected to
be replaced once the sync requirements are known from use rather than guessed.

Recorded so it is understood as temporary rather than mistaken for the design.

## Explicitly out of scope

- **A model gateway** (OpenRouter, LiteLLM). Abstracts over multiple providers;
  there is one, with no traffic. Adopt when there is a second model genuinely
  being routed between.
- **Fine-tuning.** See the decision table.
- **In-app chat and a hosted-model backend.** Deferred until the proof of
  concept reports.
- **Bidirectional sync.** Deferred until the tools reveal what actually needs
  writing.
- **Speculative capability APIs.** Define coaching operations when a caller
  needs them, not in advance.

## Consequences for the app

### The app's own plan builder is a fallback, not the main path

Because Claude is the single decision-maker, `TemplatePlanBuilder` is demoted:
it exists for **cold start** (before Claude has ever been connected) and as a
**safety net** (Claude unavailable). It does not need to be brilliant. It needs
to be sane.

This re-scopes work that was sized for a primary engine:

- **Sticky exercise selection** matters much less. It existed so regeneration
  would not silently swap movements and destroy progression history. Claude,
  adjusting week to week with the full record in view, handles continuity
  directly and with more context than a rule approximating it. Keep it as a
  property of the fallback; do not build elaborate machinery for it.
- **Balance validation** stops being a repair loop policing a generator and
  becomes a **tool Claude reads** — "does this week pull as much as it
  presses" — plus a sanity check on the fallback's own output.
- **`ExerciseResolver` is not a guard on Claude.** Claude selects IDs, so there
  is nothing to resolve. Its real job returns: understanding *the lifter's*
  free text ("some kind of row"). Smaller and more honest scope.

Still true: the app must produce a sensible block and log a session cleanly
with Claude detached, or the MCP layer is decorating something unfinished. But
"sensible" is the bar, not "expert."

Deterministic generation — currently returning `PlanBlueprint(days: [])`, so
the app generates nothing at all — remains the first work in every possible
future, because the blocks must assemble before anyone can build with them.

## Privacy

For a single owner using their own Claude subscription against their own data,
this is a personal choice with no disclosure burden.

If it ships to other people, training logs plus bodyweight plus injury notes is
sensitive data leaving the device. The export must be per-user and explicit from
the start; consent is far cheaper to design in than to retrofit.
