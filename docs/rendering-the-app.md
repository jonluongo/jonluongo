# Getting a screen on screen

`CLAUDE.md` says render everything a change touches. Doing that needs a plan in
the store, sometimes a log, and a way to reach a sheet — none of which the
simulator gives you. This is the recipe, written down because it was re-derived
from scratch a dozen times in one week and each re-derivation is another chance
to leave scaffolding in a commit.

**All of it is temporary.** Every patch here is removed before committing, and
`grep -rn "RENDER SCAFFOLDING" LiftingPlan/` is the check that it was.

## The four patches

Mark every one `// RENDER SCAFFOLDING — removed before commit.` so the grep
finds it.

**1. Point the transport at a local folder.** The simulator has no iCloud, so
the real container never resolves and the app shows *Can't reach the iCloud
folder* — which is correct behaviour and useless for rendering anything else.
In `LiftingPlanApp.init`:

```swift
let transport = ICloudDocumentTransport(
    resolveContainer: { _ in URL.documentsDirectory })
```

Documents then live at `<app data container>/Documents/Documents/` — the
transport appends `Documents` to whatever the container resolves to.

**2. Open the screen.** Read an environment variable and set the state that
presents it. `RoutineView` for a session, `ActiveWorkoutView` for its sheets,
`AccountToolbarItem` for the account:

```swift
.onAppear {
    guard ProcessInfo.processInfo.environment["RENDER"] == "session" else { return }
    openSession = plan.orderedWeeks.flatMap(Self.trainingDays(of:)).first
}
```

**3. Seed a log, when the screen needs one.** Rows exist only once a session has
been opened, so seed them first or nothing gets ticked:

```swift
SetSeeding.seedMissingSets(for: block.orderedDays.flatMap(\.orderedExercises), in: context)
try? context.save()
```

`RootView`'s `.task` is the place, after a `Task.sleep` long enough for the
inbox to have imported the plan. **Import first**: launch once without `RENDER`
so the plan lands, then launch again with it.

**4. Stub the notification centre** if a rest is involved, so the permission
dialog does not cover the screen:

```swift
private struct RenderCentre: RestNotificationScheduling {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
    func allowsAlerts() async -> Bool { true }
}
```

## Driving it

```sh
xcrun simctl install booted <path>/LiftingPlan.app
DATA=$(xcrun simctl get_app_container booted com.jonluongo.LiftingPlan data)
mkdir -p "$DATA/Documents/Documents"
cp plan.json "$DATA/Documents/Documents/"
SIMCTL_CHILD_RENDER=session xcrun simctl launch booted com.jonluongo.LiftingPlan
xcrun simctl io booted screenshot shot.png
xcrun simctl ui booted appearance dark   # and again for the other appearance
```

Make the plan with the real thing rather than by hand: drive
`LiftingMCP/.build/release/lifting-mcp --documents <dir>` over stdio with a
`write_plan` call. A hand-written `plan.json` proves a fixture renders; a
written one proves the format does, and the refusals will tell you when you get
a key or an exercise ID wrong.

## Six things that cost an hour each

**`RENDER=x xcrun simctl launch` does not reach the app.** The prefix is
`SIMCTL_CHILD_`. Without it the variable goes to `simctl` and the app sees
nothing, which looks exactly like scaffolding that did not compile.

**`simctl terminate` is not backgrounding.** It ends the process without
`scenePhase` reaching `.background`, so the snapshot export never runs and the
file on disk stays as stale as it was. To export, bring another app to the
front — `xcrun simctl launch booted com.apple.Preferences`. A probe that
terminates and then reads `snapshot.json` is measuring the *previous* export,
and the result looks precisely like the truncated-snapshot bug.

**There is no tapping.** `osascript` has no assistive access here, so nothing
can click the simulator. Anything behind a tap needs patch 2. This is why the
scaffolding exists at all.

**The notification dialog outlives the app.** An unanswered permission alert
re-presents on every launch, and it is SpringBoard's rather than the app's —
proved by stubbing the centre so the app cannot ask, and watching it appear
anyway. `xcrun simctl erase` clears it; nothing else reliably does.

**The store outlives the build.** Installing a new build keeps the old
container, so a session you logged three firings ago is still ticked and a
routine you imported is still current. That is useful when you want history and
misleading when you want a fresh screen — an empty state will not appear over a
store that holds a plan. `xcrun simctl erase` is the only clean slate, and it
takes the notification dialog with it.

**Judge colour by measurement, not by eye.** The olive `⋯` was found by cropping
the glyph and taking the most saturated pixel — 3 in light, 80 in dark. Two
appearances of the same control differing that much is a defect; deciding it by
looking at two screenshots is how it survived as long as it did.

## Before committing

```sh
grep -rn "RENDER SCAFFOLDING" LiftingPlan/ --include="*.swift"   # expect nothing
git status --short                                              # expect no app-target changes
```

Restore the patched files with `git checkout <file>` — but never as a way to
undo real work sitting in the same file. Copy the file aside first if it holds
anything uncommitted; that mistake has destroyed work in this repo three times.
