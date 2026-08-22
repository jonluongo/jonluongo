import Foundation
import LiftingKit

// What `write_plan` accepts, as the coach sees it before calling.
//
// In its own file because it is the largest thing this server advertises and the
// only one with real structure. **The structure got flatter.** A plan was a
// routine holding blocks holding days keyed by weekday, each day holding
// exercises whose sets were either a count or a list. It is a list of sessions:
// each says which block it belongs to and where it sits in that block, and each
// exercise states every set it prescribes.

extension ToolCatalog {

    static let writePlanDefinition = ToolDefinition(
        name: writePlan,
        title: "Write plan",
        description: """
            Writes plan.json into the shared folder, replacing any plan waiting \
            there, and returns the plan as it was written.

            Send one entry in 'sessions' for every workout. Each states its \
            'blockOrdinal' — which block it belongs to — and its 'ordinal' \
            within that block. Blocks run continuously and never restart, so \
            block 4 follows block 3 whatever happened in between; the context \
            resource reports the block and session he is on.

            **Write one block at a time.** Send the sessions of the block he has \
            not reached, and they land beside what is already there. A session \
            he has not trained is yours to rewrite freely; one holding a set he \
            ticked, or that he marked finished, is the record of what he did, \
            and a plan that changes it is refused naming that session.

            **A block has no name and no deload flag.** What makes block 3 an \
            accumulation block, or a deload, is something you write in \
            PROGRAM.md with update_notes — it is prose, and prose says it better \
            than a label.

            **Every set is stated.** There is no set count and no exercise-level \
            rep range: a ramp, a drop set and three identical sets are all just \
            lists of sets. Warm-ups are marked as they are prescribed.

            **When he trains is not something a plan says.** There is no weekday \
            here. He does session 2 of block 3 when he does it.
            """,
        inputSchema: object(
            [
                "sessions": array(
                    of: sessionSchema,
                    "Every workout this plan prescribes, in any order — each says where it "
                        + "sits. **All of them must belong to the same block.** Write one "
                        + "block, see how it went, then write the next; a plan naming more "
                        + "than one block is refused whole."),
                "catalogVersion": integer(
                    "The catalog version the exercise IDs came from, as list_exercises "
                        + "reported it. Left out, the server states its own."),
            ],
            required: ["sessions"])
    )

    /// One workout.
    private static var sessionSchema: JSONValue {
        object(
            [
                "blockOrdinal": integer(
                    "Which block this belongs to, from 1. Blocks run continuously and never "
                        + "restart, and every session in one plan states the same one — check "
                        + "recent_sessions for the last block on the phone and send the next."),
                "ordinal": integer("Where it sits in that block, from 1."),
                "focus": string(
                    "What to call the day — 'Push', 'Upper A', 'Core & carries'. Left out, "
                        + "the app says where it sits instead of inventing a name."),
                "icon": enumerated(
                    SessionIcon.all.map(\.rawValue),
                    "A mark for the day, from this list. Leave it out rather than guessing: "
                        + "a name the app cannot draw is refused, and a day you marked "
                        + "nothing carries nothing."),
                "entries": array(
                    of: entrySchema,
                    "The movements in the order they are trained. An entry is one exercise, "
                        + "or a group performed as rounds. A session with no entries is a "
                        + "rest day."),
            ],
            required: ["blockOrdinal", "ordinal"])
    }

    /// An exercise, or a group of them.
    private static var entrySchema: JSONValue {
        object([
            "exerciseID": string(
                "The catalog's ID, verbatim from list_exercises. Never invent one: history "
                    + "is keyed on exercise identity, and an ID the catalog does not have is "
                    + "refused with nothing taken in."),
            "displayName": string(
                "What to call it. Left out, the catalog's own name is filled in at both "
                    + "ends — send one only if you have a reason to differ."),
            "restSeconds": integer(
                "How long to rest after this movement. Left out, no clock runs, which is "
                    + "the honest answer when you did not say."),
            "coachNote": string(
                "Anything to say about the movement — a cue, a tempo such as '3-0-1-0', "
                    + "what to watch. One note per movement; if it is about one set, say so "
                    + "in words."),
            "sets": array(of: setSchema, "Every set, in order."),
            // **A group holds exercises, not entries.** A group of groups is not
            // a thing anyone performs, and describing one recursively would
            // invite a plan nobody can train.
            "group": array(
                of: object([
                    "exerciseID": string("The catalog's ID, verbatim from list_exercises."),
                    "displayName": string("What to call it. Left out, the catalog names it."),
                    "coachNote": string("Anything to say about this movement."),
                    "sets": array(of: setSchema, "Every set, in order."),
                ]),
                "Two or more movements performed as rounds, resting after the round. State "
                    + "the round's rest as this entry's 'restSeconds'; a movement inside a "
                    + "group may not state its own, and one that does is refused."),
        ])
    }

    /// One prescribed set.
    private static var setSchema: JSONValue {
        object([
            "target": string(
                "What the set asks for: a count ('5', '8-12'), a hold ('45s', '30-45s'), a "
                    + "carry ('40m', '20-30yd'), or 'AMRAP'. One measure per set, read once "
                    + "— a carry is never counted as reps. Text this server cannot read is "
                    + "refused rather than stored."),
            // **A load is a number and an intensity is text**, which is why
            // they are not written alike here despite both being called
            // 'value'. `Mass.value` is a `Double`; declaring it a string had
            // the schema promise a shape the decoder refused, so a coach who
            // followed the published schema was told his load had the wrong
            // type. An intensity really is text — it carries '8-9' and '80'.
            "load": object([
                "value": number("The number on the bar — 185, or 62.5."),
                "unit": enumerated(MassUnit.allCases.map(\.rawValue), "lb or kg."),
            ]),
            "intensity": object([
                "scale": enumerated(
                    IntensityScale.known.map(\.rawValue),
                    "How hard, on whatever scale you work in."),
                "value": string("The value on that scale — '8', '8-9', '80'."),
            ]),
            "isWarmup": boolean(
                "Whether this is a warm-up. Warm-ups are not counted as working volume and "
                    + "are not part of a round."),
        ])
    }
}
