import Foundation
import LiftingKit

// What `write_plan` accepts, as Claude sees it before calling.
//
// In its own file because it is the largest thing this server advertises and
// the only one with real structure: a block holds weeks, a week holds days, a
// day holds prescriptions. The nesting is the vocabulary — a plan that could
// only say one week could not say a deload, a wave, or a progression.

extension ToolCatalog {

    static let writePlanDefinition = ToolDefinition(
        name: writePlan,
        title: "Write plan",
        description: """
            Writes plan.json into the shared folder, replacing any plan waiting \
            there, and returns the plan as it was written. Send one entry in \
            'weeks' for every week of the block — weeks may differ, which is \
            how a ramp, a wave, or a deload is written; nothing here repeats or \
            fills in a week you did not send. Every exerciseID is checked \
            against the catalog first; one bad ID fails the whole call with \
            that ID named and writes nothing. A key this format does not have \
            also fails the call, with the key named, rather than being dropped. \
            An exercise's 'sets' is a number when every set is the same work and \
            a list when they differ — that is how a drop set, a ramp, a back-off \
            set or a per-set note is written. An entry in a day's 'exercises' is \
            either one exercise or one group — {"group": [ … ], "restSeconds": \
            90} — which is how a superset, a tri-set or a giant set is written: \
            the movements are performed back to back and the rest comes after \
            the round, so the group states the rest and the exercises inside it \
            state none. Group only when you mean it; nothing here groups \
            anything on its own. 'intensity' states how hard the \
            work should be, on whatever scale you work in; it is recorded as \
            written and never converted or bounded. Work that is not counted in \
            reps is prescribed in 'repRange' as the measure it actually is: held \
            for time — '30 seconds', '1:30' — or carried over a distance — \
            '40 metres', '20 yd'. The app logs each in its own unit, so neither a \
            plank nor a carry ever lands in the log or in volume_by_muscle as \
            repetitions. Everything else is recorded exactly as you write it — no \
            set count, rest, rep range, load, or effort target is adjusted.
            """,
        inputSchema: object(
            [
                "title": string("Short name for the block, e.g. 'Autumn strength'."),
                "goal": string("What the block is for, in your words."),
                "durationMinutes": integer("How long a session in this block runs."),
                "notes": string("Anything the lifter should read alongside the plan."),
                "weeks": array(
                    of: weekSchema,
                    "The block's weeks, in the order they are to be trained. A "
                        + "block of a single week is one entry. How many weeks the "
                        + "block runs is how many you send."),
            ],
            required: ["weeks"]
        )
    )

    private static let weekSchema = object([
        "label": string(
            "What you call this week, e.g. 'Accumulation'. Omit if the week has no name."),
        "isDeload": boolean("Whether this week is a deload. Omit if it is not."),
        "days": array(
            of: daySchema,
            "This week's training days. A day with no exercises is a rest day."),
    ])

    private static let daySchema = object(
        [
            "weekday": weekday(
                "The day, as a name ('monday') or as Calendar's numbering where "
                    + "1 is Sunday and 7 is Saturday."),
            "focus": string("Short label such as 'Push'."),
            "durationMinutes": integer("How long this session runs."),
            "exercises": array(
                of: entrySchema,
                "The work, in the order to do it. Each entry is one exercise, or "
                    + "one group of exercises performed back to back."),
        ],
        required: ["weekday"]
    )

    /// One entry of a day: an exercise, or a group of them.
    ///
    /// The group holds its exercises rather than labelling them, so there is no
    /// way to write half a grouping — no two exercises at opposite ends of a day
    /// claiming one group, and no group of one. It is the same choice `sets`
    /// makes: one key, two shapes, and no way to disagree with itself.
    private static let entrySchema: JSONValue = [
        "description": .string(
            "One exercise, or a group of two or more performed back to back as a "
                + "superset, tri-set or giant set."),
        "anyOf": [exerciseSchema, groupSchema],
    ]

    /// A superset, tri-set or giant set. Two or more exercises, and the rest
    /// that follows the round rather than any set inside it.
    private static let groupSchema = object(
        [
            "group": array(
                of: exerciseSchema,
                "Two or more exercises, in the order they are performed within "
                    + "each round. The lifter does one set of each, in this order, then "
                    + "rests, then goes again — so the count of sets each of them "
                    + "prescribes is the number of rounds. A group of one is refused; "
                    + "that is just an exercise."),
            "restSeconds": integer(
                "Rest after each round. Omit if you are not prescribing rest. This "
                    + "is the group's rest, and the only rest a group has: an exercise "
                    + "inside a group stating 'restSeconds' of its own is refused, "
                    + "because a rest between the movements of a round is a rest "
                    + "nobody takes."),
        ],
        required: ["group"]
    )

    private static let exerciseSchema = object(
        [
            "exerciseID": string("A real ID from list_exercises."),
            "displayName": string("The catalog's name for it, for display."),
            "sets": [
                "description": .string(
                    "How many sets, or which ones. Write a number when every set is "
                        + "the same work — '3' with repRange '8-12' is three sets of "
                        + "8-12, and you do not repeat yourself. Write a list when the "
                        + "sets differ: a drop set, a ramp, a back-off set, a set with "
                        + "its own note. A listed set that states nothing of its own is "
                        + "prescribed what this exercise prescribes, so a ramp needs "
                        + "only the loads."),
                "anyOf": [
                    ["type": "integer"],
                    ["type": "array", "items": setSchema],
                ],
            ],
            "repRange": string(
                "The target as written, e.g. '8-12' or '5'. Applies to every set "
                    + "that does not state its own. Omit if you are not prescribing "
                    + "one. Write a hold as the time it is — '30 seconds', '45s', "
                    + "'1:30' — and a carry as the distance it is — '40 m', "
                    + "'40 metres', '50-100 yd'. The lifter logs each in the unit it "
                    + "was prescribed in: a hold is logged in seconds rather than "
                    + "reps and a carry in the distance it covered, because the log "
                    + "records a rep count, a duration and a distance as three "
                    + "separate things. volume_by_muscle reports all three apart, so "
                    + "no hold and no carry is ever counted as a repetition. A "
                    + "distance keeps the "
                    + "unit you wrote it in and is never converted — "
                    + distanceUnits + " are read; a unit outside that list is shown to "
                    + "him exactly as written but cannot be logged, so prescribe a "
                    + "carry in one of them if you want the distance recorded."),
            "restSeconds": integer("Rest between sets. Omit if not prescribing rest."),
            "suggestedLoad": massSchema(
                "The load to work with. Applies to every set that does not state "
                    + "its own. Omit to leave it to the lifter."),
            "intensity": intensitySchema(
                "How hard this work should be. Applies to every set that does not "
                    + "state its own. Omit if you are not prescribing an effort."),
            "tempo": string("Rep tempo such as '3-0-1-0'."),
            "notes": string("Anything specific to this movement."),
        ],
        required: ["exerciseID", "displayName", "sets"]
    )

    /// The distance units this build can read out of a prescription and log,
    /// named in the schema so the writer can see them before he writes one.
    /// Assembled from `DistanceUnit.known` rather than typed out again, so the
    /// list Claude reads is the list the reader actually reads.
    private static let distanceUnits =
        DistanceUnit.known.map { "'\($0.rawValue)'" }.joined(separator: ", ")

    /// One set of a prescription whose sets differ. Everything is optional:
    /// `{}` is a legitimate set, meaning "the same as this exercise prescribes".
    private static let setSchema = object([
        "repRange": string(
            "This set's target, e.g. '5', 'AMRAP', a hold such as '30 seconds', or "
                + "a carry such as '40 m'. Omit to use the exercise's."),
        "suggestedLoad": massSchema("This set's load. Omit to use the exercise's."),
        "intensity": intensitySchema("How hard this set should be. Omit to use the exercise's."),
        "notes": string("Anything about this set alone, e.g. 'last set to failure'."),
    ])

    private static func massSchema(_ description: String) -> JSONValue {
        [
            "type": "object",
            "description": .string(description),
            "properties": [
                "value": ["type": "number"],
                "unit": ["type": "string", "enum": ["kg", "lb"]],
            ],
            "required": ["value", "unit"],
        ]
    }

    /// A prescribed effort. `scale` is required and is not a closed list — the
    /// three named below are the ones this build recognizes, and a scale it has
    /// never heard of is recorded intact rather than refused. Nothing converts
    /// between scales or bounds a value, so write the target as you would say
    /// it: '8', '8-9', '75'.
    private static func intensitySchema(_ description: String) -> JSONValue {
        [
            "type": "object",
            "description": .string(description),
            "properties": [
                "scale": [
                    "type": "string",
                    "description": .string(
                        "What the value is measured in. Commonly "
                            + IntensityScale.known.map(\.rawValue).joined(separator: ", ")
                            + ". Another scale is recorded as written."),
                ],
                "value": [
                    "type": "string",
                    "description": .string(
                        "The target exactly as you would write it. A range stays a range."),
                ],
            ],
            "required": ["scale", "value"],
        ]
    }
}
