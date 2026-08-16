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

    // MARK: - Writing down who he is

    static let updateProfileDefinition = ToolDefinition(
        name: updateProfile,
        title: "Update profile",
        description: """
            Records what you have learned about the lifter — the equipment he \
            has, what he weighs, what he can already lift, his experience, his \
            goal, his injuries, when he trains. The app asks him none of this, \
            so what he tells you is written here or it is not written at all. \
            Pass only the fields you have just learned: anything you leave out \
            keeps the value it already has. Pass null for a field to return it \
            to not-known, which is how a fact recorded in error is taken back. \
            Lists replace rather than add, so send the whole list each time — \
            except bodyweight and baselines, which are series: each record you \
            send is filed under its day or its lift, adding a new one and \
            correcting one already there, so the history is never overwritten.
            """,
        inputSchema: object([
            "equipment": [
                "description": .string(
                    "What he actually owns, as a list of equipment types — "
                        + "\(EquipmentType.known.map(\.rawValue).joined(separator: ", ")). "
                        + "A real gym is not a tier: send exactly what he has, e.g. "
                        + "['barbell', 'plate', 'band'] for a garage with no cable stack. "
                        + "The coarse tiers "
                        + "\(Equipment.allCases.map(\.rawValue).joined(separator: ", ")) "
                        + "are accepted in the same list as shorthand and expand into the "
                        + "types they stand for. Null if he has not said — that is unknown, "
                        + "not 'owns nothing', and an empty list is 'owns nothing'."),
                "anyOf": [
                    ["type": "array", "items": ["type": "string"]],
                    ["type": "string"], ["type": "null"],
                ],
            ],
            "bodyweight": [
                "description": .string(
                    "What he weighs, as {\"value\": 182, \"unit\": \"lb\"}. This is a dated "
                        + "series, not one number: pass a list to record several weigh-ins, "
                        + "and add \"date\" (ISO 8601, UTC) to file one on the day it happened "
                        + "rather than today. Stating a day again corrects that day's reading; "
                        + "a new day is added, so the trend is never overwritten."),
                "anyOf": [massSchema, ["type": "array", "items": massSchema]],
            ],
            "baselines": [
                "description": .string(
                    "What he can already do on a lift, before any of it is logged — the load "
                        + "anchor a first block has nothing else to work from. Each is "
                        + "{\"exerciseID\": …, \"load\": {\"value\": …, \"unit\": …}, "
                        + "\"reps\": …}, with an optional ISO 8601 \"recordedAt\". Leave out "
                        + "\"load\" for bodyweight work. Take exerciseID verbatim from "
                        + "\(listExercises); an ID the catalog does not have is refused. "
                        + "Stating a lift again replaces that lift's baseline."),
                "anyOf": [baselineSchema, ["type": "array", "items": baselineSchema]],
            ],
            "experience": [
                "description": .string(
                    "How much training he has behind him, in his words. "
                        + "\(ExperienceLevel.known.map(\.rawValue).joined(separator: ", ")) are "
                        + "the usual answers, but they are not the only ones accepted: "
                        + "'returning after two years off' is a truer answer than any of them "
                        + "and is recorded as written. Null if he has not said."),
                "anyOf": [["type": "string"], ["type": "null"]],
            ],
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

}
