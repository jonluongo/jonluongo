# Connecting Claude to Barbell

How to point Claude Desktop at your training data, and what to expect the first
time.

The app is called **Barbell** on the Home Screen. The Xcode project, the bundle
identifier and the iCloud container are all still `LiftingPlan` — renaming those
would orphan the data already on the phone, so the name changed and nothing
else did.

## What this gives you

Claude reads your training log and writes plans back into the app.

```
  Claude (Mac)                                    Barbell (iPhone)
      │                                               │
      │  reads snapshot.json  ◀───────────────────────┤  written when the app backgrounds
      │                                               │
      │  writes plan.json     ───────────────────────▶│  imported, shown as tables
      │  writes profile-update.json ─────────────────▶│  applied to your profile
      │                                               │
      │                                               │  you fill them in at the gym
      └──────────────────── next conversation ◀───────┘
```

All three files live in the app's iCloud Documents folder, so Apple does the
syncing. No server, no account, nothing to run.

**The app asks you nothing.** There is no setup screen and no form. What days
you train, how long you have, what you're chasing, what gear you own, what your
shoulder does overhead — you say it in conversation, and Claude writes it down
with `update_profile`. That is the whole reason the loop has a second inbound
file.

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

It opens straight to the tabs — empty, because nothing has been planned yet.
There is nothing to fill in. Swipe up to the Home Screen; that is what writes
the snapshot.

This is the step that cannot be skipped, and it must be a **real device** — the
simulator has no iCloud account, so the shared folder never appears.

Until the app has backgrounded at least once on your phone,
`~/Library/Mobile Documents/iCloud~com~jonluongo~LiftingPlan/Documents` does not
exist and the tools that read your log will tell you so.

## What Claude can do

| Tool | What it gives back |
|---|---|
| `list_exercises` | Catalog entries with real IDs, filtered to equipment you own |
| `exercise_history` | Every set you have logged for one movement, in order |
| `recent_sessions` | What you have been doing lately |
| `volume_by_muscle` | Set, rep and seconds-held totals per muscle over a window, for lifting; cardio and stretching are reported apart |
| `unstated_facts` | Which facts the record can hold about you, and which are still empty |
| `write_plan` | Writes a block to your phone — every week of it |
| `update_profile` | Writes down what you said about yourself, what you weigh, and what you can already lift |

Plus an always-present summary: who you are, your equipment, your constraints,
your current block, your working weights — with anything you have not said
reported as `null` and named outright, so it reads as unknown rather than as a
default.

**You should not have to know which facts to volunteer.** That was the loop's
last real hole: nothing told Claude that your equipment, your bodyweight or what
you can currently lift had never been stated, so either you knew to say all of it
unprompted or he planned without it. `unstated_facts` names every fact the record
can hold and which of them are currently empty, the handshake tells him the tool
is there, and `write_plan` reports what was still empty at the moment a plan
landed. All three read one list, so they cannot disagree.

It reports empty fields and stops there. **What to ask, in what order, and
whether a gap matters for the block he is about to write is Claude's call** —
"your equipment is unstated" is a fact about the record, and "ask about equipment
before writing a split" is a training opinion, which is exactly the kind of thing
this app does not hold.

**Every one of these reports. None of them recommends.** There is deliberately
no "suggest progression" or "check balance" tool. Reporting that your bench has
not moved in four weeks is data; deciding what to do about it is Claude's, with
the whole picture in view. That line is the architecture — the app supplies the
blocks and the record, Claude does the thinking.

## What a plan can say

**A plan is a block, not a week.** Each week states its own days, its own label,
and whether it is a deload. Week 3 can prescribe more than week 1 and week 4 can
back off, which is most of what programming is.

```json
"weeks": [
  { "label": "Accumulation",    "days": [ … 275 lb … ] },
  { "label": "Accumulation",    "days": [ … 285 lb … ] },
  { "label": "Intensification", "days": [ … 300 lb … ] },
  { "label": "Deload", "isDeload": true, "days": [ … 205 lb … ] }
]
```

A week's number is where it sits in the list, so two weeks cannot both claim to
be week 3. A week Claude did not name has no name — "Week 2" on screen is the app
saying where it sits, not something the plan said. The plan screen has a week
picker and opens on the earliest week with an unfinished day, so every week is
reachable and the header stops reading "3 of 3 done" once week 1 is over.

This was the largest thing Claude could not previously say. `weekCount: 8` used
to be accepted, reported back as a success, and imported as a single week; seven
weeks vanished without a word.

**An exercise's sets can differ from one another.** `sets` answers either of two
questions — how many, or which. Three sets of eight is still `"sets": 3`.

```json
{ "exerciseID": "barbell-squat", "displayName": "Back Squat", "repRange": "5",
  "sets": [
    { "suggestedLoad": { "value": 60, "unit": "kg" } },
    { "suggestedLoad": { "value": 70, "unit": "kg" } },
    { "suggestedLoad": { "value": 80, "unit": "kg" },
      "intensity": { "scale": "rpe", "value": "8" }, "notes": "Top set" } ] }
```

That is a ramp. A drop set is the same shape with a lighter last entry and
`"repRange": "AMRAP"` on it. A listed set that says nothing of its own is
prescribed what the exercise prescribes — the ramp above is three loads, not
three loads each repeating `"repRange": "5"`. Nothing is ever filled in that the
plan did not state somewhere.

In the gym that ramp seeds row by row: 60, then 70, then 80. When the sets
differ, the logger lists them numbered above the table rather than summarizing
them into one rep range no set of it actually has.

**Intensity is a scale and a value, and neither is converted.** `rpe`, `rir` and
`percent1rm` are the scales this build knows by name; `{"scale":
"metres-per-second", "value": "0.45"}` arrives intact and is shown as written.
The value is free text, so `"8"`, `"8-9"` and `"@9+"` all survive — choosing an
end of a range would be the app deciding how hard you train. The snapshot reports
the prescribed intensity directly beside the sets logged against it, so
`4 × 8-10` asked for against `10/10/9/8` performed is the comparison a
progression decision turns on.

**The lifter is never asked to rate a set.** There is no RPE field in the app
and no rating in any report: he could not tell one rep in reserve from three,
and a number nobody can supply accurately is worse than none, because you would
trust it. Ask him in conversation if you want more than the reps say. On screen,
a prescribed intensity is shown on a set's own row only where you prescribed no
load for it — `"work up to a top single at RPE 8"` is all that set has to go on,
while a set given 100 kg has already been told how hard to work.

**Timed work is prescribed in seconds and logged in seconds.**
`"repRange": "30 seconds"` reaches your screen exactly as written, and the row
you log it in is a *hold*: the column above it reads SECS rather than REPS, and
the 34 you type is stored as thirty-four seconds. It travels that way too —
`durationSeconds` in the snapshot, in `exercise_history`, in `recent_sessions`
— and `volume_by_muscle` totals seconds in their own column beside reps, so a
month of planks never reads as repetitions you did not perform.

A hold that names one duration seeds the row (`"30 seconds"`, `"45s"`,
`"1:30"`). A range (`"30-45 seconds"`) seeds nothing and shows the range, the
same way a rep range does — picking an end of it would be the app deciding how
hard you train. So does a hold whose length cannot be read without guessing
(`"1 min 30 s"`, `"max hold"`): it is still logged in seconds, just not
pre-filled.

**A carry is prescribed in a distance and logged in that same distance.**
`"repRange": "40 metres"` reaches your screen as written, the column above the
row reads M rather than REPS, and the 38 you type is stored as thirty-eight
metres — value and unit together. It travels as `distance` in the snapshot, in
`exercise_history` and in `recent_sessions`, and `volume_by_muscle` reports
`primaryDistance` as one total per unit. Nothing converts: 50 yards stays 50
yards and is never added to a total in metres, because relating the two is a
decision and this app makes none. `m`, `km`, `yd`, `ft` and `mi` are the units
read out of a prescription; a unit outside that list is still shown to you
exactly as written, and `write_plan` says which ones can be logged so Claude
knows before he prescribes a carry.

A carry naming one distance seeds the row (`"40 m"`); a range (`"50-100 yd"`)
seeds nothing and shows the range, exactly as a rep range or a hold range does.

**A set is counted, held, or carried, and no two of them are the same number.**
Reps, seconds and distance are three separate fields in the log and three
separate columns in every report, and a set that was not held or not carried
reports nothing there rather than a zero.

## Things worth knowing

**The plan you get is the plan Claude wrote.** The import checks that the
document is one it can read whole, and that every exercise ID exists in the
catalog — history is keyed by exercise identity, and an unknown ID would split a
lift's history in two permanently. It judges nothing beyond that: it does not cap
your sets, fill in a rep range, or object to an unbalanced week. A 12-set,
15-minute-rest prescription arrives intact.

**An unknown ID fails the whole import, naming the ID.** Nothing partial lands.

**A key the format does not have is now refused by name.** It used to be
dropped: Claude wrote `dropSets`, was told "Written", and you never saw it. Now
the write fails, naming the key and where it sat — `'dropSets' … at weeks → 0 →
days → 0 → exercises → 0` — and nothing at all is taken in. The same rule holds
for profile updates. Being told a prescription landed when none of it did was
the worst failure this loop had.

**A document from a newer build is refused whole**, naming both versions, rather
than importing the parts this build understands. Plans are at format version 3
and profile updates at version 3; every older document still reads. The one
thing this breaks is a stale `plan.json` claiming `weekCount: 8` over a single
week — that document was the bug, and it is now refused with an explanation
instead of importing as one week.

**If that is the plan sitting in your folder, this is what you will see.** The
app opens with an alert saying a plan arrived that it could not read whole, that
nothing you have logged has changed, and to ask Claude to send it again — with
the sentence written for him underneath, ready to be shown to him. Asking for
the block again is the whole of the fix: the same conversation, written by this
build, produces a document that imports. Nothing is deleted in the meantime, so
there is no hurry and nothing to clean up.

**A refusal is written for two readers, and says something true to each.** The
sentence Claude gets names the key and where it sat, because he is the one who
can fix it. The sentence you get says what happened to your training and what to
do about it, because you are the one holding the phone. Neither is a summary of
the other; you get both.

**A new plan supersedes rather than overwrites.** Your previous block and every
set logged against it survive. There is no confirmation dialog — Claude decides
— but nothing is destroyed.

**A profile update merges.** Claude sends only what he just learned; every other
fact stays as it was. A single fact he sends as `null` goes back to not-known,
which is how something recorded wrongly gets taken back rather than replaced
with another guess. Lists — the movements you avoid, the days you train — are
sent whole, so they replace rather than pile up. Two updates written before your
phone has synced fold into one; nothing is lost between them.

The two series are the exception, and the tool and the phone now say so in the
same words: a `null` on `bodyweight` or `baselines` is refused rather than
quietly ignored, because it would read either as recording nothing or as erasing
every entry and there is no telling which was meant. To correct one, state that
day's reading, or that lift's baseline, again.

**Bodyweight and baselines are series, and they now have a write path at all.**
Both used to be read by Claude and writable by nobody, so he was permanently told
you had no weight and no strength anchor — the first plan for any lift had
nothing to set a load against. A weigh-in is filed under its day: a day the log
does not have is added, a day it already has is replaced. Recording and
correcting are one verb, so to fix Tuesday you state Tuesday again, and a single
weigh-in cannot flatten the trend. A baseline is keyed on the lift, so restating
your bench replaces your bench and nothing else. An `exerciseID` the catalog does
not know is refused before anything is written.

**Equipment is what you own, not a tier.** `["barbell", "plate", "band"]` is a
garage gym, and `list_exercises` narrows to what that actually allows — barbell
work in, cable work out. No tier could describe it: `fullGym` handed you 109
machine and cable exercises you cannot do, and `homeMinimal` denied all 66
barbell ones. The four tiers survive only as shorthand you may type; nothing
stores one, which is why an unrecognized one can no longer reject the whole
document. Something the catalog has never heard of (`"reverse hyper"`) is
recorded and grants nothing, which is honest. Having said nothing at all is
still `null` — unknown, not empty, and not a full gym.

**Experience is in your words.** It was one of three fixed words; "returning
after two years off" is a truer answer than any of them and is recorded as
written.

**The history chart changed meaning.** It used to plot an estimated one-rep max
and put a green arrow beside a lift when the estimate rose. Both are gone —
Epley's formula is one opinion among several that disagree materially above about
ten reps, and the arrow was the app concluding you were getting stronger. The
chart now plots the heaviest set you actually logged, titled "Heaviest set (lb)".
That is a record rather than a derivation, but it is not the same line: a session
of 105×1 after 100×5 rises on one and falls on the other. Claude has every logged
set and can compute whatever estimate he thinks is right.

**lb or kg is yours.** It is the one setting left in the app, because it is
about how numbers are drawn rather than about training. Claude can set it too;
whoever set it last wins.

**Volume reports carry `snapshotAgeDays`.** A window anchored at now against a
week-old snapshot reads as zero volume, which would otherwise look like you
stopped training rather than like stale data.

## When something is wrong

**"Snapshot not found"** — the app has not backgrounded on a device yet, or
iCloud has not finished syncing. Open the app on your phone, switch away from
it, wait a moment.

**Catalog fails to load** — the binary got separated from its resource bundle.
Rebuild, or move both together.

**A plan or a profile update never arrives on the phone** — check the file
actually landed in the Documents folder above. The app watches that folder for
`plan.json` and `profile-update.json` and takes them in on arrival. Anything it
cannot read it says so in an alert rather than ignoring.
