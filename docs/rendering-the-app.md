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
the real container never resolves and the app shows *Couldn't share your log* —
which is correct behaviour and useless for rendering anything else. In
`LiftingPlanApp.init`:

```swift
let transport = ICloudDocumentTransport(
    resolveContainer: { _ in URL.documentsDirectory })
```

Documents then live at `<app data container>/Documents/Documents/` — the
transport appends `Documents` to whatever the container resolves to.

**2. Open the screen.** Read an environment variable and set the state that
presents it. The session's cover and the rest bar live on `RootView`; the three
toolbar sheets live on `BlockView`:

```swift
.task {
    guard let render = ProcessInfo.processInfo.environment["RENDER"] else { return }
    try? await Task.sleep(for: .seconds(2))
    if render == "session" { openSession = sessions.first }
    if render == "account" { showingAccount = true }
    if render == "program" { showingProgram = true }
    if render == "history" { showingHistory = true }
}
```

**A `.task` cannot read `@Query` on its first pass.** The sleep is not padding —
it is waiting for the query to be populated *and* for `DocumentInbox` to have
imported whatever is in the folder. Without it `sessions.first` is `nil` and the
screen never opens, which looks exactly like scaffolding that did not compile.

**3. Log a set, when the screen needs one.** `SetSeeding` is gone: a performed
row exists only when something is ticked, so drive the real service.

```swift
let log = SessionLog(session: first, context: ctx,
                     restTimer: restTimer, restPreferences: RestPreferences())
try? log.record(SessionOrder.trainingOrder(of: first).first!,
                load: Mass(value: 225, unit: .pounds), reps: 5,
                durationSeconds: nil, distance: nil as Distance?)
```

`RootView` is the place, and it needs `import LiftingKit` for `Mass` and
`Distance`. Recording a set **starts a rest**, which is how to reach the bar's
resting state; `restTimer.skip()` reaches *Rest over*, and it has to happen
**after** the cover is presented or something restarts the clock.

**4. Stop the app asking for notifications** if a rest is involved, so the
permission dialog does not cover the screen. One guard, in `ScreenLockedCue`:

```swift
guard ProcessInfo.processInfo.environment["RENDER"] == nil else { return }
Task { await requestAuthorization() }
```

Stubbing the whole `RestNotificationScheduling` conformance was the old advice
and is more code for the same result.

## Driving it

```sh
xcrun simctl install booted <path>/LiftingPlan.app
DATA=$(xcrun simctl get_app_container booted com.jonluongo.LiftingPlan data)
D="$DATA/Documents/Documents"; mkdir -p "$D"
./LiftingMCP/.build/release/lifting-mcp --documents "$D" < plan-call.jsonl
xcrun simctl launch booted com.jonluongo.LiftingPlan     # once, so it imports
SIMCTL_CHILD_RENDER=session xcrun simctl launch booted com.jonluongo.LiftingPlan
xcrun simctl io booted screenshot shot.png
xcrun simctl ui booted appearance dark   # and again for the other appearance
```

Make the plan with the real thing rather than by hand: drive
`LiftingMCP/.build/release/lifting-mcp --documents <dir>` over stdio with a
`write_plan` call. A hand-written `plan.json` proves a fixture renders; a
written one proves the format does, and the refusals will tell you when you get
a key or an exercise ID wrong.

**A plan states one block, so several blocks are several calls.** Write block
one, launch so it imports, write block two, launch again. A single document
naming two blocks is refused whole — correctly — and the refusal reads like a
seeding bug if you have forgotten this.

**Terminate between launches.** `xcrun simctl launch` on a running app does
nothing and returns success, so the previous `RENDER` value stays in force and
the screenshot is of the last thing you asked for.

## Eleven things that cost an hour each

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

**`simctl privacy grant all` does not cover notifications.** It grants
calendar, contacts, photos and the rest, and the notification alert is not in
that list — so the one dialog that actually blocks these screens is the one it
cannot clear. Patch 4 stops the app *asking*; a dialog already queued from an
earlier launch survives that and needs `xcrun simctl erase`.

**A screenshot with the dialog over it is still worth reading.** Three findings
today came off shots that were half covered: the toolbar capsule split, the
session clock drawn twice, and *Finish workout* in sentence case were all legible
around the alert. Reaching for `erase` first costs the store and every seeded
plan with it — read what you have before deciding you need a clean device.

**A superset needs a plan that states one.** Nothing in the app makes a group —
the coach does — so the whole feature is invisible unless `write_plan` is given
an `entries[].group` of two or more exercises with the round's `restSeconds` on
the entry. It went unrendered for a long time for exactly this reason: every
seeded plan was a list of plain exercises, so the eyebrow, the rule down the
panel edge and the round order had tests and no screenshot.

**The store outlives the build.** Installing a new build keeps the old
container, so a session you logged three firings ago is still ticked and a
routine you imported is still current. That is useful when you want history and
misleading when you want a fresh screen — an empty state will not appear over a
store that holds a plan. `xcrun simctl erase` is the only clean slate, and it
takes the notification dialog with it.

**Capturing a screenshot is not looking at one.** Three shots — a warm-up row,
the spent state, an exercise note — were taken in one firing, reported as
rendered, and not opened until several firings later. The file appearing on disk
proves the simulator was alive, nothing more. If a screen is worth a screenshot
it is worth the read call; if it is not worth the read call, do not claim it was
rendered.

**A note at the foot of a long list is off the bottom of the screen.** The
*every session is logged* line sits under the last block, which on a three-block
routine is well past the fold, and there is no way to scroll. Seed a shorter
plan — one block, one day — when the thing being checked lives at the end.

**Measure colour from a crop; do not measure *distance* from one.** Picking the
most saturated pixel in a rough window is reliable — any pixel in the region
answers the question. Measuring how wide a figure is, or whether two shapes
touch, needs the window to be exactly right, and twice here it was not: a crop
meant for the rest ring counted the table showing through behind the sheet, and
one meant for a weight figure counted the set badge beside it. Both produced
confident numbers that meant nothing. Where the answer comes from a type size
and a font metric, take it from the style sheet instead — `.title3` monospaced
is 20pt and a mono digit advances about 0.6em, which needs no screenshot at all.

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
