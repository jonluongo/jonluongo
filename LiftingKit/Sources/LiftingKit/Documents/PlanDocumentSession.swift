import Foundation

/// One session of a `PlanDocument`: a workout the coach prescribed.
///
/// **What it does.** States which block and which session within it, what the
/// coach called the day, the mark he chose for it, and the movements in order.
///
/// **It has no date and no weekday.** When the user trains is not something
/// the plan decides — the app hands him the session and he does it when he does
/// it. A session is *session 2 of block 3*, and when it actually happened is a
/// fact about the record, carried by `PerformedExercise.occurredAt`.
///
/// **What it depends on.** `SessionIcon`, `PlanDocumentEntry`, and
/// `DocumentRefusal`. It judges nothing and infers nothing: a session with no
/// entries is a rest day the coach wrote, not an omission to be filled.
public struct PlanDocumentSession: Codable, Hashable, Sendable {

    /// Which block this session belongs to. Blocks run continuously and never
    /// restart, so this is also where the session sits in the whole timeline.
    public let blockOrdinal: Int
    /// Which session of that block this is, from 1.
    public let ordinal: Int
    /// What the coach called the day — "Push", "Upper A". May be empty, in
    /// which case the app says where it sits rather than inventing a name.
    public let focus: String
    /// The mark the coach chose, from the closed set the app publishes. `nil`
    /// when he marked nothing, which the app draws as nothing: a glyph the app
    /// picked would be the app deciding what a session trains.
    public let icon: SessionIcon?
    /// The movements, in the order they are to be trained. An entry is one
    /// exercise or a group of them performed as rounds.
    public let entries: [PlanDocumentEntry]

    public init(
        blockOrdinal: Int, ordinal: Int, focus: String = "",
        icon: SessionIcon? = nil, entries: [PlanDocumentEntry] = []
    ) {
        self.blockOrdinal = blockOrdinal
        self.ordinal = ordinal
        self.focus = focus
        self.icon = icon
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case blockOrdinal, ordinal, focus, icon, entries
    }

    /// A session must say where it sits; everything else is optional, because a
    /// session that states no name and no mark is stating an absence and a
    /// decoder that filled one in would be inventing a prescription.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockOrdinal = try container.decode(Int.self, forKey: .blockOrdinal)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
        icon = try container.decodeIfPresent(SessionIcon.self, forKey: .icon)
        entries = try container.decodeIfPresent([PlanDocumentEntry].self, forKey: .entries) ?? []
    }

    /// Every movement this session prescribes, flat and in order, whatever it
    /// was grouped into. Read this when the grouping does not matter — checking
    /// each `ExerciseID` against the catalog, say — and `entries` when it does.
    public var exercises: [PlanDocumentExercise] { entries.flatMap(\.exercises) }
}

/// One movement of a session, and how it is to be performed.
///
/// **Every set is stated.** `sets` is a list and never a count: a ramp, a drop
/// set and three identical sets are one shape, so nothing has to reconcile an
/// exercise's defaults with a set's overrides, and there is no second code path
/// for the case where the sets happen to agree. That reconciliation was where a
/// prescription could quietly become something the coach did not write.
///
/// **What it depends on.** `ExerciseID`, `PlanDocumentSet`, `DocumentRefusal`.
public struct PlanDocumentExercise: Codable, Hashable, Sendable {

    /// The catalog's identity for this movement. An ID the catalog does not
    /// have is refused on the way in — history is keyed by exercise identity,
    /// and a fabricated key fragments a lift's history irreparably.
    public let exerciseID: ExerciseID
    /// What to call it. Filled in from the catalog by `PlanDocumentNaming`
    /// wherever the coach stated none, at both ends of the wire.
    public let displayName: String
    /// How long to rest after this movement. `nil` when the coach did not say.
    ///
    /// **An exercise inside a group may not state one, and is refused if it
    /// does** — see `DocumentRefusal.restInsideGroup`. A group is performed as
    /// rounds and the rest is taken after the round, so a rest on one member
    /// alone is a rest nobody takes. The group states it once. What the *store*
    /// holds is the flattened form of that — nothing after the early members,
    /// the round's rest after the last — which is the importer's business and
    /// not this format's.
    public let restSeconds: Int?
    /// What the coach wants said about the movement — a cue, a tempo, what to
    /// watch. `nil` when there is none.
    public let coachNote: String?
    /// Every set, in order, each stated in full.
    public let sets: [PlanDocumentSet]

    public init(
        exerciseID: ExerciseID, displayName: String = "", restSeconds: Int? = nil,
        coachNote: String? = nil, sets: [PlanDocumentSet] = []
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.restSeconds = restSeconds
        self.coachNote = coachNote
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exerciseID, displayName, restSeconds, coachNote, sets
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(ExerciseID.self, forKey: .exerciseID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        coachNote = try container.decodeIfPresent(String.self, forKey: .coachNote)
        sets = try container.decodeIfPresent([PlanDocumentSet].self, forKey: .sets) ?? []
    }
}

/// One prescribed set: what to do, with what, how hard, and whether it counts.
///
/// **Every field is what the coach stated, and nothing is inherited.** A set
/// that states no load has no load — the user picks the bar, which is what
/// `intensity` is for. Nothing here is filled in from the exercise, because
/// there is nothing on the exercise to fill it in from: the exercise states its
/// sets, and a set states itself.
///
/// **What it depends on.** `Target`, `Mass`, `IntensityTarget`,
/// `DocumentRefusal`. It judges nothing: a load is never turned into an
/// intensity, an intensity never into a load, and no absent value is ever
/// filled with a number the app chose.
public struct PlanDocumentSet: Codable, Hashable, Sendable {

    /// What this set asks for — a count, a hold, or a carry — read once, here,
    /// and never re-guessed downstream. `nil` when the coach stated no target,
    /// which is a set defined entirely by its load and its intensity.
    public let target: Target?
    /// The external load. `nil` for a bodyweight movement, and `nil` when the
    /// coach left the bar to the user.
    public let load: Mass?
    /// How hard this set should be. `nil` when the coach stated none — never a
    /// zero, and never inferred from the load.
    public let intensity: IntensityTarget?
    /// Whether this set is a warm-up.
    ///
    /// **The coach could not say this before.** It appeared nowhere in the plan
    /// document: everything prescribed was hardcoded as work, and only a set
    /// the user added himself was ever marked — so *"ramp three sets to your
    /// top set"* could not be written down, and the app's answer was that the
    /// user adds his own. That was the app owning part of the prescription.
    ///
    /// Stated per set, because an exercise is not a warm-up — some of its sets
    /// are, and a ramp is exactly a list of sets that disagree about it.
    public let isWarmup: Bool

    public init(
        target: Target? = nil, load: Mass? = nil,
        intensity: IntensityTarget? = nil, isWarmup: Bool = false
    ) {
        self.target = target
        self.load = load
        self.intensity = intensity
        self.isWarmup = isWarmup
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target, load, intensity, isWarmup
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decodeIfPresent(Target.self, forKey: .target)
        load = try container.decodeIfPresent(Mass.self, forKey: .load)
        intensity = try container.decodeIfPresent(IntensityTarget.self, forKey: .intensity)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
    }

    /// Written by hand so a working set carries no `"isWarmup": false`. Most
    /// sets are working sets, and a key stating the default on every one of them
    /// is noise in a document a person reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(load, forKey: .load)
        try container.encodeIfPresent(intensity, forKey: .intensity)
        if isWarmup { try container.encode(true, forKey: .isWarmup) }
    }
}
