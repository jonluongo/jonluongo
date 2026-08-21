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
    public static let updateNotes = "update_notes"

    public static let definitions: [ToolDefinition] = [
        listExercisesDefinition, exerciseHistoryDefinition, recentSessionsDefinition,
        volumeByMuscleDefinition, writePlanDefinition, updateNotesDefinition,
    ]

    // MARK: - Reading the catalog

    static let listExercisesDefinition = ToolDefinition(
        name: listExercises,
        title: "List exercises",
        description: """
            Catalog entries with their real exercise IDs, narrowed to what this \
            user can actually perform with the equipment he has. Every entry \
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
                "Include exercises the user's equipment, avoided patterns, or "
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
            anything about how much a user is doing; an hour of conditioning \
            is there and in none of the totals above.
            """,
        inputSchema: object(
            ["weeks": integer("How many weeks back from now to count. Defaults to 4.")]
        )
    )

    // MARK: - Writing what he wrote

    /// **An anchored edit, because prose has no refusal machinery of its own.**
    /// Every other inbound format is versioned and refuses a key it does not
    /// have; a markdown file has no shape to violate, so the guard is that the
    /// writer states the text he expects to replace. If it is not there, or
    /// appears twice, nothing is written and he is told which.
    ///
    /// A whole-file write would lose whatever he had not read, silently, which
    /// is the one failure mode this project does not accept.
    static let updateNotesDefinition = ToolDefinition(
        name: updateNotes,
        title: "Update notes",
        description: """
            Edits one of the two markdown notes the user's app renders.

            'ACCOUNT.md' is who he is: what he trains for, his background, his \
            injuries and limits, what he avoids and why, his equipment, and his \
            bodyweight over time. 'PROGRAM.md' is why this programme — the \
            approach, what is being progressed, what to watch, and what makes a \
            given block a deload.

            This is an anchored edit, not a rewrite. State 'oldText' exactly as \
            it appears and it is replaced by 'newText'. If 'oldText' is not \
            found, or is found more than once, nothing is written — read the \
            note first rather than guessing at it.

            Append rather than replace under 'Injuries and limits' and \
            'Bodyweight': those are dated observations, and the earlier ones are \
            the history.
            """,
        inputSchema: object([
            "file": enumerated(
                NoteFile.allCases.map(\.rawValue),
                "Which note to edit."),
            "oldText": string(
                "The text to replace, exactly as it appears in the note. Use a "
                    + "heading and the line under it when replacing a section."),
            "newText": string("What to put in its place."),
        ], required: ["file", "oldText", "newText"])
    )

}