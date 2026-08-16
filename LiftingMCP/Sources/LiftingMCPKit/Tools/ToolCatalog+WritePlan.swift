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
            Everything else is recorded exactly as you write it — no set count, \
            rest, rep range, or load is adjusted.
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
            "exercises": array(of: exerciseSchema, "The movements, in the order to do them."),
        ],
        required: ["weekday"]
    )

    private static let exerciseSchema = object(
        [
            "exerciseID": string("A real ID from list_exercises."),
            "displayName": string("The catalog's name for it, for display."),
            "sets": integer("Prescribed working sets."),
            "repRange": string(
                "The rep target as written, e.g. '8-12' or '5'. Omit if you are "
                    + "not prescribing one."),
            "restSeconds": integer("Rest between sets. Omit if not prescribing rest."),
            "suggestedLoad": [
                "type": "object",
                "description": .string(
                    "The load to work with. Omit to leave it to the lifter."),
                "properties": [
                    "value": ["type": "number"],
                    "unit": ["type": "string", "enum": ["kg", "lb"]],
                ],
                "required": ["value", "unit"],
            ],
            "tempo": string("Rep tempo such as '3-0-1-0'."),
            "notes": string("Anything specific to this movement."),
        ],
        required: ["exerciseID", "displayName", "sets"]
    )
}
