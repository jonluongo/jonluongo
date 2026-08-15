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

## What stays deterministic — and why this is not negotiable

The model supplies **judgment**. The app owns **selection and safety**.

| Owned by code | Owned by the model |
|---|---|
| Which exercises are permitted (`EquipmentAccess`) | Which split suits this lifter |
| Resolving any name to a real `ExerciseID` (`ExerciseResolver`) | What to change after an injury report |
| Sets, reps, rest (assembly rules JSON) | Whether progress says push or back off |
| Balance rules (pull ≥ press, etc.) | Diet and recovery guidance |
| Load progression (`ProgressionEngine`) | Explaining any of the above |

Two failures justify the split. A hallucinated `ExerciseID` corrupts training
history irreversibly — history is keyed by exercise identity, and a fabricated
key silently fragments it. A wrong load is an injury. Neither is acceptable at
any model quality, so neither is delegated at any model quality.

This is the same division already designed in the programming spec. MCP changes
only *who* supplies the judgment.

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

The app must be genuinely good standing alone. If it cannot produce a sensible
training block and log a session cleanly with Claude detached, the MCP layer is
decorating something unfinished.

This makes deterministic plan generation — currently returning
`PlanBlueprint(days: [])` — the prerequisite for everything here, in every
possible future. It is the first work, and it implements
`2026-08-14-workout-programming-design.md` unchanged.

## Privacy

For a single owner using their own Claude subscription against their own data,
this is a personal choice with no disclosure burden.

If it ships to other people, training logs plus bodyweight plus injury notes is
sensitive data leaving the device. The export must be per-user and explicit from
the start; consent is far cheaper to design in than to retrofit.
