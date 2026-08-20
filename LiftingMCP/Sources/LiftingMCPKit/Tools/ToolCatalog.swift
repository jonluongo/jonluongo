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
    public static let unstatedFacts = "unstated_facts"

    public static let definitions: [ToolDefinition] = [
        listExercisesDefinition, exerciseHistoryDefinition, recentSessionsDefinition,
        volumeByMuscleDefinition, unstatedFactsDefinition, writePlanDefinition,
        updateProfileDefinition,
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
            reps, and what was prescribed at the time. A set held for time \
            reports 'durationSeconds', a set carried for distance reports \
            'distance' as a value and its unit, and a counted set reports 'reps' — \
            no two of them are ever the same number. The measure a set was not \
            performed in is null, except 'reps', which is 0 there because the app \
            stores a repetition count rather than an absent one: read that 0 as \
            'not counted in reps', with the seconds or the distance beside it \
            saying what he did. Includes warmups and uncompleted rows, each flagged, plus any \
            stated starting baseline.
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
            what was logged against it, and when. Each logged set carries its \
            reps, its 'durationSeconds' for work held for time, and its \
            'distance' — a value and its unit — for work carried over a distance. \
            An exercise trained in a superset, tri-set or giant set carries \
            'group' — its notation ('A1'), its place in the round, and the rest \
            after each round; 'group' is null for an exercise performed on its \
            own. Without it a superset would read back as unrelated sets rather \
            than as the rounds it was performed in.
            """,
        inputSchema: object(
            ["limit": integer("How many sessions to return. Defaults to 10.")]
        )
    )

    static let volumeByMuscleDefinition = ToolDefinition(
        name: volumeByMuscle,
        title: "Volume by muscle",
        description: """
            Completed working sets per muscle over a recent window, with reps, \
            seconds held and distance carried counted separately as primary and \
            as secondary so no weighting is assumed. Time held is reported as \
            seconds and distance as 'primaryDistance' — one total per unit — and \
            neither is ever added into the rep total, so a block of planks never \
            reads as repetitions and neither does a block of carries. Warmups and \
            uncompleted rows do not count. The muscle totals are resistance \
            training only: cardio and stretching are real work but not lifting \
            volume, so they are reported apart under 'excluded' — by category, \
            with the sets, seconds and distance they were performed in — rather \
            than counted as muscle volume. Read 'excluded' before concluding \
            anything about how much a lifter is doing; an hour of conditioning \
            is there and in none of the totals above.
            """,
        inputSchema: object(
            ["weeks": integer("How many weeks back from now to count. Defaults to 4.")]
        )
    )

    // MARK: - Reading what nobody has said

    /// **This names empty fields. It does not name questions to ask.** The
    /// difference is the architecture: "equipment and bodyweight are unstated"
    /// is a fact about the record, and "ask about equipment before writing a
    /// split" is a training opinion. The first belongs here; the second is
    /// Claude's, and putting it in a tool description would be this app deciding
    /// how coaching goes.
    static let unstatedFactsDefinition = ToolDefinition(
        name: unstatedFacts,
        title: "Unstated facts",
        description: """
            Which facts about the lifter this record can hold, and which of them \
            nobody has stated yet: the equipment he owns, what he weighs, what he \
            can already lift, his experience, his goal, his injuries, and when and \
            how long he can train. The app has no setup screen and asks him none \
            of it, so an unstated fact is a conversation that has not happened \
            rather than an answer of 'none' — and nothing else in this server will \
            volunteer that a field is empty. Call it when you want to know what is \
            not known. A fact he has stated comes back with the date he last said \
            it, so a constraint mentioned this week and one mentioned before the \
            last two blocks can be told apart — null where the record predates \
            those dates being kept. Which of these matter for what you are about \
            to write, whether an old date is worth revisiting, and whether to ask \
            at all, is yours to judge; this reports fields and dates and passes no \
            verdict on either. \(updateProfile) is what closes one, and stating a \
            fact again records that he said it again.
            """,
        inputSchema: object([:])
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
            keeps the value it already has. Pass null for a single fact to \
            return it to not-known, which is how a fact recorded in error is \
            taken back. Lists replace rather than add, so send the whole list \
            each time — except bodyweight and baselines, which are series: each \
            record you send is filed under its day or its lift, adding a new one \
            and correcting one already there, so the history is never \
            overwritten. Those two cannot be nulled, and a null on either is \
            refused rather than ignored: it would read either as recording \
            nothing or as erasing every entry. Correct a series by stating that \
            day's reading, or that lift's baseline, again. Every fact you state \
            here is dated with this call, and stating one again records that he \
            said it again — which is how a constraint he mentioned last year and \
            one he mentioned this week are told apart later. The dates are \
            written from the call and are not yours to send.
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
                        + "a new day is added, so the trend is never overwritten. Null is "
                        + "refused here — a series cannot be taken back, only corrected."),
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
                        + "Stating a lift again replaces that lift's baseline. Null is "
                        + "refused here — a series cannot be taken back, only corrected."),
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
            "goal": string(
                "What he is training for, in his words. This is the fact the "
                    + "rest of the plan follows from — the split, the rep "
                    + "ranges, the intensity and what progress even means all "
                    + "answer to it, and nothing else in this record "
                    + "distinguishes a lineman training for explosiveness from "
                    + "someone who wants to look bigger. 'Get in shape' records "
                    + "as little as it says; it is worth asking what he is "
                    + "actually after before writing it down."),
            "constraints": string(
                "Injuries and limitations in his words, with the nuance a list "
                    + "cannot hold, e.g. 'left shoulder hurts overhead'."),
            "avoidedPatterns": stringOrList(
                "Movement patterns to keep out of his training entirely, e.g. "
                    + "'vertical press'. This is the enforceable half of an injury — "
                    + "list_exercises and the app both filter on it."),
            "avoidedExercises": stringOrList(
                "Specific exercise IDs to keep out, taken verbatim from list_exercises."),
            "preferredDurationMinutes": integer("How long he wants a session to run."),
            "displayUnit": enumerated(
                MassUnit.allCases.map(\.rawValue),
                "How the app should render weights. A display setting, not a "
                    + "training fact — he can also change it himself."),
        ])
    )

}
