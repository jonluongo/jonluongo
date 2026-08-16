import Foundation
import LiftingKit

/// One tool as Claude sees it before calling it.
///
/// Read `ToolCatalog.definitions` to answer `tools/list`; `inputSchema` is the
/// JSON Schema the client validates arguments against. Depends on: `JSONValue`.
public struct ToolDefinition: Sendable, Hashable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, title: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }

    /// The wire shape of a `tools/list` entry.
    public var advertised: JSONValue {
        ["name": .string(name), "title": .string(title),
         "description": .string(description), "inputSchema": inputSchema]
    }
}

/// Every tool this server offers, and nothing else.
///
/// `ToolRunner` dispatches on these names and `MCPServer` advertises these
/// definitions, so a tool that exists in one and not the other cannot happen.
///
/// **What is missing here is the design.** There is no `suggest_progression`
/// and no `check_balance` that returns a verdict. Reporting that a lift has not
/// moved in four weeks is data; deciding what to do about it is Claude's, and a
/// tool that concluded would put a training opinion inside a Swift function,
/// which is the one thing this project does not do.
///
/// Depends on: `ToolDefinition` and `JSONValue`.
public enum ToolCatalog {

    public static let listExercises = "list_exercises"
    public static let exerciseHistory = "exercise_history"
    public static let recentSessions = "recent_sessions"
    public static let volumeByMuscle = "volume_by_muscle"
    public static let writePlan = "write_plan"
    public static let updateProfile = "update_profile"

    public static let definitions: [ToolDefinition] = [
        listExercisesDefinition, exerciseHistoryDefinition, recentSessionsDefinition,
        volumeByMuscleDefinition, writePlanDefinition, updateProfileDefinition,
    ]

    // MARK: - Reading the catalog

    static let listExercisesDefinition = ToolDefinition(
        name: listExercises,
        title: "List exercises",
        description: """
            Catalog entries with their real exercise IDs, narrowed to what this \
            lifter can actually perform with the equipment he has. Every entry \
            carries the name, movement pattern, equipment, and primary and \
            secondary muscles, so you can choose a movement without a second \
            call. Always pick exercise IDs from here — write_plan rejects an ID \
            the catalog does not have.
            """,
        inputSchema: object([
            "query": string("Free text matched against names and aliases, e.g. 'bench'."),
            "pattern": stringOrList(
                "Movement patterns to include, e.g. 'squat', 'hinge', "
                    + "'horizontal press', 'vertical pull'."),
            "muscle": stringOrList(
                "Primary muscles to include, e.g. 'chest', 'lats', 'quadriceps'."),
            "equipment": stringOrList(
                "Equipment to include, e.g. 'barbell', 'dumbbell', 'cable', 'bodyweight'."),
            "limit": integer("How many entries to return. Defaults to 50."),
            "includeUnavailable": boolean(
                "Include exercises the lifter's equipment, avoided patterns, or "
                    + "avoided exercises rule out. Defaults to false."),
        ])
    )

    // MARK: - Reading the log

    static let exerciseHistoryDefinition = ToolDefinition(
        name: exerciseHistory,
        title: "Exercise history",
        description: """
            Every set ever logged for one movement, oldest first, with the load, \
            reps, RPE, and what was prescribed at the time. Includes warmups and \
            uncompleted rows, each flagged, plus any stated starting baseline.
            """,
        inputSchema: object(
            ["id": string("The exercise ID, exactly as list_exercises reported it.")],
            required: ["id"]
        )
    )

    static let recentSessionsDefinition = ToolDefinition(
        name: recentSessions,
        title: "Recent sessions",
        description: """
            The most recently trained days, newest first: what was prescribed, \
            what was logged against it, and when.
            """,
        inputSchema: object(
            ["limit": integer("How many sessions to return. Defaults to 10.")]
        )
    )

    static let volumeByMuscleDefinition = ToolDefinition(
        name: volumeByMuscle,
        title: "Volume by muscle",
        description: """
            Completed working sets and reps per muscle over a recent window, \
            counted separately as primary and as secondary so no weighting is \
            assumed. Warmups and uncompleted rows are excluded.
            """,
        inputSchema: object(
            ["weeks": integer("How many weeks back from now to count. Defaults to 4.")]
        )
    )

    // MARK: - Writing the plan

    static let writePlanDefinition = ToolDefinition(
        name: writePlan,
        title: "Write plan",
        description: """
            Writes plan.json into the shared folder, replacing any plan waiting \
            there, and returns the plan as it was written. Every exerciseID is \
            checked against the catalog first; one bad ID fails the whole call \
            with that ID named and writes nothing. Everything else is recorded \
            exactly as you write it — no set count, rest, rep range, or load is \
            adjusted.
            """,
        inputSchema: object(
            [
                "title": string("Short name for the block, e.g. 'Autumn strength'."),
                "goal": string("What the block is for, in your words."),
                "weekCount": integer("How many weeks the block runs."),
                "durationMinutes": integer("How long a session in this block runs."),
                "notes": string("Anything the lifter should read alongside the plan."),
                "days": [
                    "type": "array",
                    "description":
                        "The block's training days. A day with no exercises is a rest day.",
                    "items": object(
                        [
                            "weekday": [
                                "description": .string(
                                    "The day, as a name ('monday') or as Calendar's "
                                        + "numbering where 1 is Sunday and 7 is Saturday."),
                                "anyOf": [["type": "string"], ["type": "integer"]],
                            ],
                            "focus": string("Short label such as 'Push'."),
                            "durationMinutes": integer("How long this session runs."),
                            "exercises": [
                                "type": "array",
                                "items": object(
                                    [
                                        "exerciseID": string(
                                            "A real ID from list_exercises."),
                                        "displayName": string(
                                            "The catalog's name for it, for display."),
                                        "sets": integer("Prescribed working sets."),
                                        "repRange": string(
                                            "The rep target as written, e.g. '8-12' or '5'. "
                                                + "Omit if you are not prescribing one."),
                                        "restSeconds": integer(
                                            "Rest between sets. Omit if not prescribing rest."),
                                        "suggestedLoad": [
                                            "type": "object",
                                            "description": .string(
                                                "The load to work with. Omit to leave it "
                                                    + "to the lifter."),
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
                                ),
                            ],
                        ],
                        required: ["weekday"]
                    ),
                ],
            ],
            required: ["days"]
        )
    )

    // MARK: - Writing down who he is

    static let updateProfileDefinition = ToolDefinition(
        name: updateProfile,
        title: "Update profile",
        description: """
            Records what you have learned about the lifter — his gym, his \
            experience, his goal, his injuries, when he trains. The app asks him \
            none of this, so what he tells you is written here or it is not \
            written at all. Pass only the fields you have just learned: anything \
            you leave out keeps the value it already has. Pass null for a field \
            to return it to not-known, which is how a fact recorded in error is \
            taken back. Lists replace rather than add, so send the whole list \
            each time.
            """,
        inputSchema: object([
            "equipmentAccess": enumerated(
                Equipment.allCases.map(\.rawValue),
                "The gym he has, as a coarse tier. Null if he has not said."),
            "experience": enumerated(
                ExperienceLevel.allCases.map(\.rawValue),
                "Roughly how long he has trained, as he describes it."),
            "goal": string("What he is training for, in his words."),
            "constraints": string(
                "Injuries and limitations in his words, with the nuance a list "
                    + "cannot hold, e.g. 'left shoulder hurts overhead'."),
            "avoidedPatterns": stringOrList(
                "Movement patterns to keep out of his training entirely, e.g. "
                    + "'vertical press'. This is the enforceable half of an injury — "
                    + "list_exercises and the app both filter on it."),
            "avoidedExercises": stringOrList(
                "Specific exercise IDs to keep out, taken verbatim from list_exercises."),
            "preferredWeekdays": [
                "description": .string(
                    "The days he says he wants to train, as names ('monday') or as "
                        + "Calendar's numbering where 1 is Sunday and 7 is Saturday."),
                "anyOf": [
                    ["type": "array", "items": ["anyOf": [["type": "string"], ["type": "integer"]]]],
                    ["type": "string"], ["type": "integer"],
                ],
            ],
            "preferredDurationMinutes": integer("How long he wants a session to run."),
            "displayUnit": enumerated(
                MassUnit.allCases.map(\.rawValue),
                "How the app should render weights. A display setting, not a "
                    + "training fact — he can also change it himself."),
        ])
    )

    // MARK: - Schema shorthand

    private static func object(
        _ properties: [String: JSONValue], required: [JSONValue] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required) }
        return .object(schema)
    }

    private static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    private static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    private static func boolean(_ description: String) -> JSONValue {
        ["type": "boolean", "description": .string(description)]
    }

    /// A closed set of exact strings, or `null` to take the fact back. The
    /// values come from the taxonomy itself rather than being retyped, so a
    /// tier added later cannot be advertised wrongly.
    private static func enumerated(_ values: [String], _ description: String) -> JSONValue {
        [
            "type": ["string", "null"],
            "description": .string(description),
            "enum": .array(values.map { .string($0) } + [.null]),
        ]
    }

    /// One value or several — Claude writes `"muscle": "chest"` as readily as
    /// `"muscle": ["chest"]`, and both plainly mean the same thing.
    private static func stringOrList(_ description: String) -> JSONValue {
        [
            "description": .string(description),
            "anyOf": [["type": "string"], ["type": "array", "items": ["type": "string"]]],
        ]
    }
}
