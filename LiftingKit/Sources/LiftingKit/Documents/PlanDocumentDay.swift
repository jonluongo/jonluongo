import Foundation

/// One training day of a `PlanDocumentWeek`.
///
/// Read `entries` in the order given — that is the order the work is meant to be
/// done in, and nothing downstream re-sorts it. An empty day is a rest day the
/// plan named on purpose, not a day that failed to be filled in.
///
/// **An entry is either an exercise or a group.** A group is two or more
/// exercises performed as rounds, resting after the round — see
/// `PlanDocumentEntry`. Read `exercises` when only the movements matter, such as
/// checking every `ExerciseID` against the catalog; it is the same list flattened
/// and in the same order, so a caller that never cared about grouping keeps the
/// answer it always had.
///
/// Depends on: `Weekday`, `PlanDocumentEntry`, `DocumentRefusal`.
public struct PlanDocumentDay: Codable, Hashable, Sendable {
    public let weekday: Weekday
    /// Short label such as "Push". May be empty.
    public let focus: String
    /// How long this session runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    /// The day's work in order: each entry one exercise, or one group of them.
    public let entries: [PlanDocumentEntry]

    /// Every movement the day prescribes, in order, whatever it was grouped
    /// into. Derived rather than stored, so a day cannot hold a list of
    /// exercises that disagrees with its entries.
    public var exercises: [PlanDocumentExercise] { entries.flatMap(\.exercises) }

    public init(
        weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
        entries: [PlanDocumentEntry] = []
    ) {
        self.weekday = weekday
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.entries = entries
    }

    /// A day of ungrouped exercises, which is nearly every day.
    public init(
        weekday: Weekday, focus: String = "", durationMinutes: Int? = nil,
        exercises: [PlanDocumentExercise]
    ) {
        self.init(
            weekday: weekday, focus: focus, durationMinutes: durationMinutes,
            entries: exercises.map(PlanDocumentEntry.exercise)
        )
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
        entries = try container.decodeIfPresent([PlanDocumentEntry].self, forKey: .exercises) ?? []
    }

    /// Spelled out because the entries are written under `exercises`, which is
    /// the key this format has always used and the key a group sits in.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(focus, forKey: .focus)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encode(entries, forKey: .exercises)
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
/// **`sets` answers either of two questions with one key: how many, or which.**
/// `"sets": 3` prescribes the same work three times, which is the ordinary case
/// and must stay the short one — three sets of eight is not three near-identical
/// objects. `"sets": [ … ]` lists the sets one at a time, which is how a drop
/// set, a ramp, a back-off set or a per-set note is said. A listed set that
/// states nothing of its own is prescribed what the exercise prescribes; read
/// `prescribedSets` for every set stated in full.
///
/// `intensity` is how hard the work is meant to be, on whatever scale the plan
/// stated. `nil` means the plan named no target — nothing infers one from a
/// load.
///
/// Depends on: `ExerciseID`, `Mass`, `SetPrescription`, `IntensityTarget`,
/// `DocumentRefusal`.
public struct PlanDocumentExercise: Codable, Hashable, Sendable {
    public let exerciseID: ExerciseID
    /// For display only. Never an identity or a join key.
    public let displayName: String
    /// Prescribed working sets, exactly as written. When the plan listed its
    /// sets one at a time, this is how many it listed — a separately stated
    /// count could disagree with the sets beside it, so there is nowhere to
    /// state one.
    public let sets: Int
    /// The rep target as written, e.g. "8-12" or "5". Empty when none was
    /// prescribed. Applies to every set that did not state its own.
    public let repRange: String
    /// Prescribed rest between sets, in seconds. `nil` when none was prescribed
    /// — not zero, which would read as "rest none".
    public let restSeconds: Int?
    /// The load to work with, in the unit it was written in. `nil` when the
    /// plan left it to the lifter. Applies to every set that did not state its
    /// own.
    public let suggestedLoad: Mass?
    /// How hard the work is meant to be — an RPE, a reps-in-reserve target, a
    /// percentage of a one-rep max, or a scale this build has never heard of.
    /// `nil` when the plan named none, which is not the same as easy.
    public let intensity: IntensityTarget?
    /// Rep tempo such as "3-0-1-0". `nil` when none was given.
    public let tempo: String?
    public let notes: String?
    /// The sets the plan listed one at a time, exactly as it listed them.
    /// Empty when the plan prescribed the same work throughout.
    public let statedSets: [SetPrescription]

    /// Every set this exercise prescribes, in order, each stated in full.
    ///
    /// This is what to render and what to report: a uniform prescription reads
    /// as `sets` copies of what the exercise states, and a listed one reads as
    /// what each set states with anything it left out taken from the exercise.
    /// Nothing here is invented — see `SetPrescription.everySet(...)`.
    public var prescribedSets: [SetPrescription] {
        SetPrescription.everySet(
            stated: statedSets, count: sets, repRange: repRange,
            suggestedLoad: suggestedLoad, intensity: intensity
        )
    }

    /// The ordinary case: the same work, so many times.
    public init(
        exerciseID: ExerciseID, displayName: String, sets: Int,
        repRange: String = "", restSeconds: Int? = nil, suggestedLoad: Mass? = nil,
        intensity: IntensityTarget? = nil, tempo: String? = nil, notes: String? = nil
    ) {
        self.init(
            exerciseID: exerciseID, displayName: displayName, sets: sets,
            repRange: repRange, restSeconds: restSeconds, suggestedLoad: suggestedLoad,
            intensity: intensity, tempo: tempo, notes: notes, statedSets: []
        )
    }

    /// Sets that differ, one at a time. The set count is how many are listed.
    public init(
        exerciseID: ExerciseID, displayName: String, sets: [SetPrescription],
        repRange: String = "", restSeconds: Int? = nil, suggestedLoad: Mass? = nil,
        intensity: IntensityTarget? = nil, tempo: String? = nil, notes: String? = nil
    ) {
        self.init(
            exerciseID: exerciseID, displayName: displayName, sets: sets.count,
            repRange: repRange, restSeconds: restSeconds, suggestedLoad: suggestedLoad,
            intensity: intensity, tempo: tempo, notes: notes, statedSets: sets
        )
    }

    private init(
        exerciseID: ExerciseID, displayName: String, sets: Int, repRange: String,
        restSeconds: Int?, suggestedLoad: Mass?, intensity: IntensityTarget?,
        tempo: String?, notes: String?, statedSets: [SetPrescription]
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.sets = sets
        self.repRange = repRange
        self.restSeconds = restSeconds
        self.suggestedLoad = suggestedLoad
        self.intensity = intensity
        self.tempo = tempo
        self.notes = notes
        self.statedSets = statedSets
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exerciseID, displayName, sets, repRange, restSeconds, suggestedLoad
        case intensity, tempo, notes
    }

    /// The identity, the name, and the sets are required; a prescription that
    /// cannot say which movement or how much work is not a prescription. The
    /// rest is optional so that an absence stays an absence, and a key this
    /// format does not have is refused rather than silently discarded.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(ExerciseID.self, forKey: .exerciseID)
        displayName = try container.decode(String.self, forKey: .displayName)
        switch try container.decode(StatedSets.self, forKey: .sets) {
        case .count(let count):
            sets = count
            statedSets = []
        case .listed(let listed):
            sets = listed.count
            statedSets = listed
        }
        repRange = try container.decodeIfPresent(String.self, forKey: .repRange) ?? ""
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        suggestedLoad = try container.decodeIfPresent(Mass.self, forKey: .suggestedLoad)
        intensity = try container.decodeIfPresent(IntensityTarget.self, forKey: .intensity)
        tempo = try container.decodeIfPresent(String.self, forKey: .tempo)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Written back the way it was said: a count when the sets are the same,
    /// the sets themselves when they are not. Spelled out rather than
    /// synthesized because `sets` is one key with two shapes, and a plan that
    /// came in as a list must not go back out as a bare number.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(displayName, forKey: .displayName)
        if statedSets.isEmpty {
            try container.encode(sets, forKey: .sets)
        } else {
            try container.encode(statedSets, forKey: .sets)
        }
        try container.encode(repRange, forKey: .repRange)
        try container.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try container.encodeIfPresent(suggestedLoad, forKey: .suggestedLoad)
        try container.encodeIfPresent(intensity, forKey: .intensity)
        try container.encodeIfPresent(tempo, forKey: .tempo)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

/// What the `sets` key said: how many sets, or which ones.
///
/// A private decoding shape rather than something a client holds — callers read
/// `PlanDocumentExercise.sets` and `statedSets`, which are the same two facts
/// with the ambiguity already resolved. Depends on: `SetPrescription`.
private enum StatedSets: Decodable {
    case count(Int)
    case listed([SetPrescription])

    /// A number is a count and anything else is read as a list. The `try?`
    /// discards nothing: its failure means only "not a number, then", and the
    /// `try` that follows throws the real error — including a `DocumentRefusal`
    /// from inside a listed set, which is the whole point of listing them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let count = try? container.decode(Int.self) {
            self = .count(count)
            return
        }
        self = .listed(try container.decode([SetPrescription].self))
    }
}
