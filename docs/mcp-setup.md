# Connecting Claude to LiftingPlan

How to point Claude Desktop at your training data, and what to expect the first
time.

## What this gives you

Claude reads your training log and writes plans back into the app.

```
  Claude (Mac)                              LiftingPlan (iPhone)
      │                                            │
      │  reads snapshot.json  ◀────────────────────┤  written when the app backgrounds
      │                                            │
      │  writes plan.json     ────────────────────▶│  imported, shown as tables
      │                                            │
      │                                            │  you fill them in at the gym
      └───────────────── next conversation ◀───────┘
```

Both files live in the app's iCloud Documents folder, so Apple does the syncing.
No server, no account, nothing to run.

**The rhythm is plan at the desk, train at the gym.** A local MCP server is
reachable by Claude on this Mac, not by Claude on your phone in a squat rack.
The plan syncs to the phone; the conversation happens here.

## Setup

**1. Build the server.**

```sh
swift build --package-path LiftingMCP -c release
```

The binary lands at `LiftingMCP/.build/release/lifting-mcp`. **Leave it beside
its `LiftingKit_LiftingKit.bundle`** — that bundle carries the 412-exercise
catalog. Moving the binary alone makes the server exit with a loud error rather
than quietly serving an empty catalog.

**2. Tell Claude Desktop about it.**

Add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "liftingplan": {
      "command": "/Users/jonluon/jonluongo/LiftingMCP/.build/release/lifting-mcp"
    }
  }
}
```

Restart Claude Desktop. To point it somewhere else, add
`"args": ["--documents", "/some/path"]` or set `LIFTINGPLAN_DOCUMENTS_DIR`.

**3. Run the app on your iPhone once, and background it.**

This is the step that cannot be skipped, and it must be a **real device** — the
simulator has no iCloud account, so the shared folder never appears.

Until the app has backgrounded at least once on your phone,
`~/Library/Mobile Documents/iCloud~com~jonluongo~LiftingPlan/Documents` does not
exist and every tool will tell you so.

## What Claude can do

| Tool | What it gives back |
|---|---|
| `list_exercises` | Catalog entries with real IDs, filtered to equipment you own |
| `exercise_history` | Every set you have logged for one movement, in order |
| `recent_sessions` | What you have been doing lately |
| `volume_by_muscle` | Set and rep totals per muscle over a window |
| `write_plan` | Writes a plan to your phone |

Plus an always-present summary: who you are, your equipment, your constraints,
your current block, your working weights.

**Every one of these reports. None of them recommends.** There is deliberately
no "suggest progression" or "check balance" tool. Reporting that your bench has
not moved in four weeks is data; deciding what to do about it is Claude's, with
the whole picture in view. That line is the architecture — the app supplies the
blocks and the record, Claude does the thinking.

## Things worth knowing

**The plan you get is the plan Claude wrote.** The import checks one thing: that
every exercise ID exists in the catalog, because history is keyed by exercise
identity and an unknown ID would split a lift's history in two permanently. It
does not cap your sets, fill in a rep range, or object to an unbalanced week. A
12-set, 15-minute-rest prescription arrives intact.

**An unknown ID fails the whole import, naming the ID.** Nothing partial lands.

**A new plan supersedes rather than overwrites.** Your previous block and every
set logged against it survive. There is no confirmation dialog — Claude decides
— but nothing is destroyed.

**Volume reports carry `snapshotAgeDays`.** A window anchored at now against a
week-old snapshot reads as zero volume, which would otherwise look like you
stopped training rather than like stale data.

## When something is wrong

**"Snapshot not found"** — the app has not backgrounded on a device yet, or
iCloud has not finished syncing. Open the app on your phone, switch away from
it, wait a moment.

**Catalog fails to load** — the binary got separated from its resource bundle.
Rebuild, or move both together.

**A plan never arrives on the phone** — check the file actually landed in the
Documents folder above. The app watches that folder and imports on arrival.
