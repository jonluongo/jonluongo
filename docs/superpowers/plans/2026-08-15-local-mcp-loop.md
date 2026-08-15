# The Local MCP Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop. Claude writes a plan, it appears on the phone as workout tables, the lifter fills them in, and Claude reads back what happened.

**Architecture:** A shared Swift package holds the vocabulary — taxonomies, catalog, `Mass`, `RepRange`, and two versioned document formats. The iOS app writes `snapshot.json` and imports `plan.json`. A macOS MCP executable reads the snapshot and writes plans. Apple's iCloud Documents does the syncing. No backend, no auth.

**Tech Stack:** Swift 6 (strict concurrency, warnings-as-errors), Swift Package Manager, SwiftData/CloudKit, MCP over stdio, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-15-local-mcp-loop-design.md`

## Global Constraints

- **The app makes no training decisions.** No choosing exercises, sets, reps, rest, or load; no clamping, capping, flooring, or substituting a prescribed value. See `CLAUDE.md`.
- **Record what you are given.** A prescribed value is stored exactly as prescribed. Missing values are modeled honestly (optional or documented empty), never invented.
- **Layers import only downward:** Domain → Catalog → Store → Services → Views. The package must not invert this.
- **Errors are handled or propagated, never discarded.** No `try?` dropping an error.
- **No force unwrapping, force try, or force casting** outside tests.
- **Extensible taxonomies.** Unknown values round-trip intact rather than crashing or being dropped.
- **Every public type's doc comment answers three questions:** what it does, how it is used, what it depends on.
- **Warnings are errors.** Swift 6, strict concurrency. Files past ~300 lines are a signal.
- **Swift Testing** (`@Test`, `#expect`, `#require`), never XCTest. Only `✔ Test run with N tests in M suites passed` proves tests ran.
- **Never hand-edit** `project.pbxproj` or the generated `exercises.json`.

**Baseline:** 126 tests in 16 suites passing, catalog version 5, 412 exercises.

**Standing note:** `PlanBlueprint` has no producer. Task 3 gives it one. Until then, do not write anything that generates a plan.

---

### Task 1: Extract the shared package

**Files:**
- Create: `LiftingKit/Package.swift`, `LiftingKit/Sources/LiftingKit/**`
- Move: everything in `LiftingPlan/Domain/` and `LiftingPlan/Catalog/` (including `Resources/`)
- Modify: `LiftingPlan.xcodeproj` (add local package dependency — via Xcode's project file, not by hand-editing if avoidable)
- Test: move the corresponding suites into `LiftingKit/Tests/LiftingKitTests/`

**Interfaces:**
- Produces: module `LiftingKit` exporting the taxonomies, `Exercise`, `ExerciseID`, `Mass`, `RepRange`, `EquipmentAccess`, `ExerciseCatalog`, `ExerciseCatalogProviding`, `ExerciseResolver`.

**Do not move `Store/`.** The MCP server reads a snapshot file and must never link SwiftData. Moving the models would drag SwiftData into a command-line tool for nothing.

Types crossing the module boundary need explicit `public`. Adding `public` is mechanical; **adding it thoughtlessly is not** — anything not needed by the app or the server stays internal, so the package's surface stays small and honest.

Bundled resources move with the package and load via `Bundle.module`. `ExerciseCatalog.bundled()` and `assembly-rules.json` must still resolve — a resource that silently fails to load is the likely failure here, so assert it loads rather than assuming.

- [ ] **Step 1: Create the package and move Domain + Catalog with `git mv`** so history follows.
- [ ] **Step 2: Add `public` where the app needs it**, and nowhere else.
- [ ] **Step 3: Wire the package into the app target; fix imports.**
- [ ] **Step 4: Move the tests**, then run both the package suite and the app suite.
- [ ] **Step 5: Commit.** Expect the app suite to shrink and the package suite to appear; the total must not fall. Report both numbers.

---

### Task 2: The snapshot document, and exporting it

**Files:**
- Create: `LiftingKit/Sources/LiftingKit/Documents/TrainingSnapshot.swift`
- Create: `LiftingPlan/Services/SnapshotExporter.swift`
- Test: `LiftingKit/Tests/LiftingKitTests/TrainingSnapshotTests.swift`, `LiftingPlanTests/SnapshotExporterTests.swift`

**Interfaces:**
- Produces: `TrainingSnapshot` (`Codable`, `version: Int`, `catalogVersion: Int`, profile, body metrics, baselines, plans, logged sets) and `SnapshotExporter.export(from:) throws -> TrainingSnapshot`.

`TrainingSnapshot` lives in the package (the server decodes it) and is **pure value types** — no SwiftData. `SnapshotExporter` lives in the app and does the mapping.

- [ ] **Step 1: Write failing tests.** Round-trip encode/decode; unknown taxonomy values survive; a logged set keeps its `Mass` unit exactly as entered rather than being canonicalized; an empty store produces a valid snapshot rather than throwing.
- [ ] **Step 2: Implement the type and the exporter.**
- [ ] **Step 3: Export automatically when the app backgrounds** — a scene-phase change, not a button. A stale snapshot makes the coach confidently wrong.
- [ ] **Step 4: Run tests and commit.**

---

### Task 3: The plan document, and importing it

**Files:**
- Create: `LiftingKit/Sources/LiftingKit/Documents/PlanDocument.swift`
- Create: `LiftingPlan/Services/PlanImporter.swift`
- Modify: `LiftingPlan/Services/PlanBlueprint.swift` (give it a producer at last)
- Test: `LiftingKit/Tests/LiftingKitTests/PlanDocumentTests.swift`, `LiftingPlanTests/PlanImporterTests.swift`

**Interfaces:**
- Produces: `PlanDocument` (`Codable`, versioned) and `PlanImporter.import(_:into:catalog:) throws -> TrainingPlan`.

The import does exactly one thing beyond decoding: **confirm every `ExerciseID` exists in the catalog.** Not distrust — history is keyed by exercise identity, so an unknown key fragments a lift's history irreparably.

It must NOT cap sets, fill an empty rep range, clamp rest, or reject a plan for being unbalanced. That is the whole architecture in one function.

- [ ] **Step 1: Write failing tests.** A valid plan imports with every value preserved exactly — including a deliberately extreme one (12 sets, 900s rest) that must survive untouched. An unknown `ExerciseID` throws an error **naming the offending ID**, and imports nothing. Importing twice does not duplicate. **An import supersedes rather than overwrites: the previous plan and everything logged against it still exist afterward.**
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run tests and commit.**

---

### Task 4: Transport

**Files:**
- Create: `LiftingPlan/Services/DocumentTransport.swift`
- Modify: `LiftingPlan/LiftingPlan.entitlements` (add the iCloud Documents scope and ubiquity container)
- Test: `LiftingPlanTests/DocumentTransportTests.swift`

**Interfaces:**
- Produces: `protocol DocumentTransport { func writeSnapshot(_:) throws; func readPlan() throws -> PlanDocument? }` with an iCloud Documents implementation and an in-memory fake.

**One protocol, one implementation today.** This seam is justified because its future is known — the remote version replaces exactly this and nothing else.

The entitlement currently enables CloudKit only. Adding the documents scope may require a provisioning refresh; device builds use `-allowProvisioningUpdates`. **If the entitlement change cannot be made from the CLI, STOP and report rather than falling back to a local-only folder** — silently losing Mac↔phone sync would make the loop untestable while appearing to work.

- [ ] **Step 1: Write failing tests against the fake** — write-then-read round-trips; absent plan file returns nil rather than throwing; a malformed file throws rather than returning nil.
- [ ] **Step 2: Implement both.**
- [ ] **Step 3: Watch the folder** so an arriving plan appears without the user hunting for a refresh button.
- [ ] **Step 4: Run tests and commit.**

---

### Task 5: The MCP server

**Files:**
- Create: `LiftingMCP/Package.swift`, `LiftingMCP/Sources/LiftingMCP/**`
- Test: `LiftingMCP/Tests/LiftingMCPTests/**`

A macOS executable speaking stdio MCP, depending on `LiftingKit`. **Check the current Swift MCP SDK before writing** — if none is usable, implement the JSON-RPC surface directly; it is small.

Tools, every one of which reports rather than concludes:

| Tool | Returns |
|---|---|
| `list_exercises(pattern:muscle:equipment:)` | Catalog entries with real IDs, filtered to what the lifter can perform |
| `exercise_history(id:)` | Every logged set for one movement, in order |
| `recent_sessions(limit:)` | What was done lately |
| `volume_by_muscle(weeks:)` | Set and rep totals per muscle |
| `write_plan(plan)` | Writes `plan.json`; returns the resolved plan or a named error |

Plus a compact always-present context resource: identity, equipment, constraints, current block, recent sessions, working weights.

**No `suggest_progression` and no `check_balance` returning a verdict.** Reporting that a lift has not moved in four weeks is data; deciding what to do is Claude's.

- [ ] **Step 1: Write failing tests** for each tool against a fixture snapshot.
- [ ] **Step 2: Implement the tools.**
- [ ] **Step 3: Implement the MCP transport and register it with Claude Desktop.**
- [ ] **Step 4: Run tests and commit.**

---

### Task 6: Close the loop end to end

- [ ] **Step 1:** Write a plan through the server; confirm `plan.json` appears.
- [ ] **Step 2:** Confirm the app imports it and renders the tables.
- [ ] **Step 3:** Log a session; background the app.
- [ ] **Step 4:** Confirm the new sets appear in the snapshot the server reads back.
- [ ] **Step 5:** Document the setup in `README.md` — how to build the server and point Claude Desktop at it.

**This is the first end-to-end exercise of the in-gym logger.** It has never been tapped through; UI automation is unavailable in this environment, so the owner must do steps 2–3 on a device. Report exactly what was verified programmatically and what needs a human.

## Out of scope

- Hosted MCP, OAuth, connectors.
- In-app chat.
- Any app-side training decision.
