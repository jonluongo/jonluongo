# LiftingPlan

iOS app that turns casual lifting into progressively harder training. SwiftUI,
SwiftData with CloudKit sync, and Apple's on-device Foundation Models for plan
generation with a deterministic fallback.

## Build and test

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Device builds sign with `DEVELOPMENT_TEAM = GKMVG76BQR` and need
`-allowProvisioningUpdates`.

## Architecture

Four layers. **A layer may import only the layers above it.** This is the most
important rule in the project.

| Layer | Contents | May import |
|---|---|---|
| `Domain/` | Pure value types and logic. No persistence, no UI. | Foundation only |
| `Catalog/` | Bundled exercise reference data, lookup, resolution. | Domain |
| `Store/` | SwiftData models. User data only. | Domain |
| `Services/` | Generation, progression, timing, coordination. | Domain, Catalog, Store |
| `Views/` | SwiftUI. | All of the above |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, simulator, or model. Do not erode it.

The exercise catalog is bundled reference data, never SwiftData. Exercise
identity is the MoveKit slug (see `docs/reference/movekit-exercise-slugs.txt`),
so purchased animations drop in without a mapping layer.

Design specs live in `docs/superpowers/specs/`. Read the foundation
architecture spec before changing the data model.

## Standards

These are binding. Code that violates them is not done.

**Errors are handled or propagated, never discarded.** No `try?` that drops an
error on the floor. A failed save must surface to the user — with CloudKit
sync, save conflicts are expected, not exceptional.

**No force unwrapping, force try, or force casting** outside tests. If a value
is guaranteed present, express that in the type.

**Data over code.** Facts about training — the catalog, split templates, rep and
rest prescriptions — live in versioned JSON, not in `switch` statements. No
numeric literal expressing a training opinion appears inside a function body.

**Extensible taxonomies, not closed enums.** Muscle groups, equipment,
movement patterns, and categories are raw-value-backed structs with static
constants. Unknown values from data must round-trip intact rather than crash or
be silently dropped.

**Protocol seams at boundaries.** Layers depend on protocols, not concrete
types, so implementations can be swapped and faked.

**Tests before implementation.** The pure layers carry real coverage. The
exercise resolver and unit conversion are the highest-value suites in the
project — they are the guard on data integrity.

**Every public type answers three questions** in its doc comment: what it does,
how it is used, what it depends on. If a type cannot be understood without
reading its internals, the boundary is wrong.

**Warnings are errors.** Swift 6 language mode, strict concurrency.

**Files stay focused.** A file growing past roughly 300 lines is a signal it is
doing too much.

## Verification

Never claim work is complete without running the command and reading the
output. State what was run and what it printed. If tests fail, say so.
