import Foundation

/// One training day of a `PlanDocumentWeek`.
///
/// Read `exercises` in the order given — that is the order the work is meant to
/// be done in, and nothing downstream re-sorts it. An empty `exercises` is a
/// rest day the plan named on purpose, not a day that failed to be filled in.
///
/// Depends on: `Weekday`, `PlanDocumentExercise`, `DocumentRefusal`.
public struct PlanDocumentDay: Codable, Hashable, Sendable {
    public let weekday: Weekday
    /// Short label such as "Push". May be empty.
    public let focus: String
    /// How long this session runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    public let exercises: [PlanDocumentExercise]

    public init(
        weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
        exercises: [PlanDocumentExercise] = []
    ) {
        self.weekday = weekday
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.exercises = exercises
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case weekday, focus, durationMinutes, exercises
    }

    /// Only `weekday` is required: a day that cannot say when it happens is not
    /// a day, while a day with no focus and no stated length is perfectly
    /// ordinary. An unknown key is refused rather than dropped.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decode(Weekday.self, forKey: .weekday)
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        exercises = try container.decodeIfPresent(
            [PlanDocumentExercise].self, forKey: .exercises) ?? []
    }
}

/// One prescribed movement in a `PlanDocument`.
///
/// `exerciseID` is the identity that matters and the only value the import
/// checks — history is keyed on it, so an ID the catalog does not know would
/// fragment a lift's history irreparably. `displayName` is carried for display
/// only; never resolve or match an exercise by it.
///
/// Every other field is recorded verbatim. `restSeconds` and `suggestedLoad`
/// are `nil` rather than zero when none was prescribed, and `repRange` is empty
/// rather than a default when none was stated — parse it with `RepRange`.
///
/// Depends on: `ExerciseID`, `Mass`, `DocumentRefusal`.
public struct PlanDocumentExercise: Codable, Hashable, Sendable {
    public let exerciseID: ExerciseID
    /// For display only. Never an identity or a join key.
    public let displayName: String
    /// Prescribed working sets, exactly as written.
    public let sets: Int
    /// The rep target as written, e.g. "8-12" or "5". Empty when none was
    /// prescribed.
    public let repRange: String
    /// Prescribed rest between sets, in seconds. `nil` when none was prescribed
    /// — not zero, which would read as "rest none".
    public let restSeconds: Int?
    /// The load to work with, in the unit it was written in. `nil` when the
    /// plan left it to the lifter.
    public let suggestedLoad: Mass?
    /// Rep tempo such as "3-0-1-0". `nil` when none was given.
    public let tempo: String?
    public let notes: String?

    public init(
        exerciseID: ExerciseID, displayName: String, sets: Int,
        repRange: String = "", restSeconds: Int? = nil, suggestedLoad: Mass? = nil,
        tempo: String? = nil, notes: String? = nil
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.sets = sets
        self.repRange = repRange
        self.restSeconds = restSeconds
        self.suggestedLoad = suggestedLoad
        self.tempo = tempo
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exerciseID, displayName, sets, repRange, restSeconds, suggestedLoad, tempo, notes
    }

    /// The identity, the name, and the set count are required; a prescription
    /// that cannot say which movement or how much work is not a prescription.
    /// The rest is optional so that an absence stays an absence, and a key this
    /// format does not have is refused rather than silently discarded.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(ExerciseID.self, forKey: .exerciseID)
        displayName = try container.decode(String.self, forKey: .displayName)
        sets = try container.decode(Int.self, forKey: .sets)
        repRange = try container.decodeIfPresent(String.self, forKey: .repRange) ?? ""
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        suggestedLoad = try container.decodeIfPresent(Mass.self, forKey: .suggestedLoad)
        tempo = try container.decodeIfPresent(String.self, forKey: .tempo)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}
