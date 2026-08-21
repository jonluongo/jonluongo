import Foundation

/// One session as the coach wrote it, and what the record has of it since.
///
/// **What it does.** Pairs a prescription with the two facts the store adds:
/// whether the user finished it, and which import it came from. The
/// prescription is the plan document's own `PlanDocumentSession` rather than a
/// restatement — one description of a session, written once, by the format that
/// prescribed it.
///
/// **`finishedAt` is the only event on it.** Everything else the user did is a
/// `SnapshotPerformedExercise`, which is a fact about the record rather than about the
/// prescription. A session can be finished with nothing performed, which is why
/// it cannot be derived.
///
/// **What it depends on.** `PlanDocumentSession`.
public struct SnapshotSession: Codable, Hashable, Sendable {

    /// The session exactly as the coach wrote it.
    public let prescription: PlanDocumentSession
    /// When the user pressed Finish, or `nil` while he has not.
    public let finishedAt: Date?
    /// When the coach wrote it — his date, not the day the phone took it in.
    public let generatedAt: Date
    /// Which import it arrived in, naming the archived copy of the document.
    public let sourceDocumentID: UUID?

    public init(
        prescription: PlanDocumentSession, finishedAt: Date? = nil,
        generatedAt: Date, sourceDocumentID: UUID? = nil
    ) {
        self.prescription = prescription
        self.finishedAt = finishedAt
        self.generatedAt = generatedAt
        self.sourceDocumentID = sourceDocumentID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case prescription, finishedAt, generatedAt, sourceDocumentID
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prescription = try container.decode(PlanDocumentSession.self, forKey: .prescription)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        sourceDocumentID = try container.decodeIfPresent(UUID.self, forKey: .sourceDocumentID)
    }

    /// Which block this belongs to.
    public var blockOrdinal: Int { prescription.blockOrdinal }
    /// Where it sits in that block.
    public var ordinal: Int { prescription.ordinal }
    /// Whether the user has been through it.
    public var isFinished: Bool { finishedAt != nil }
}

/// One exercise, on one day, as it actually went.
///
/// **This is the grain the wire never had.** The log used to be a flat series of
/// sets, each restating the plan, block, weekday, focus and prescription it
/// belonged to — because the store had no row at the grain the question is
/// asked at. *How has bench gone* is a series of these.
///
/// **It carries its own coordinates rather than a link.** A performance stays
/// readable when the session behind it is gone, which is what makes this a log
/// rather than a view of a plan. A stated baseline has no session at all: it is
/// a performance with `source: stated`, one set, and no coordinates.
///
/// **It never carries an aggregate.** Set count, top set, volume and estimated
/// 1RM are computed from `sets`. A stored copy can disagree with them.
///
/// **It is named for the row it is, not for the idea of one.** It was
/// `SnapshotPerformance` until an audit caught it: `Performance` is an
/// abstraction noun, and this project's naming rule bans them for exactly the
/// reason `ExercisePerformance` was rejected in the store. It mirrors
/// `PerformedExercise` because it *is* that row, on the wire.
///
/// **What it depends on.** `ExerciseID`, `PerformanceSource`.
public struct SnapshotPerformedExercise: Codable, Hashable, Sendable {

    /// The movement performed.
    public let exerciseID: ExerciseID
    /// When it was performed. For a stated baseline, when he says he did it.
    public let occurredAt: Date
    /// Ticked in the app, or told to the coach.
    public let source: PerformanceSource
    /// Which block this belongs to, or `nil` for a stated baseline.
    public let blockOrdinal: Int?
    /// Where the session sits in that block, or `nil` for a stated baseline.
    public let sessionOrdinal: Int?
    /// What the user said about it, in his own words.
    public let userNote: String?
    /// The sets performed, in the order they happened.
    public let sets: [SnapshotPerformedSet]

    public init(
        exerciseID: ExerciseID, occurredAt: Date, source: PerformanceSource = .logged,
        blockOrdinal: Int? = nil, sessionOrdinal: Int? = nil,
        userNote: String? = nil, sets: [SnapshotPerformedSet] = []
    ) {
        self.exerciseID = exerciseID
        self.occurredAt = occurredAt
        self.source = source
        self.blockOrdinal = blockOrdinal
        self.sessionOrdinal = sessionOrdinal
        self.userNote = userNote
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exerciseID, occurredAt, source, blockOrdinal, sessionOrdinal, userNote, sets
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(ExerciseID.self, forKey: .exerciseID)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        source = try container.decodeIfPresent(PerformanceSource.self, forKey: .source) ?? .logged
        blockOrdinal = try container.decodeIfPresent(Int.self, forKey: .blockOrdinal)
        sessionOrdinal = try container.decodeIfPresent(Int.self, forKey: .sessionOrdinal)
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
        sets = try container.decodeIfPresent([SnapshotPerformedSet].self, forKey: .sets) ?? []
    }

    /// The sets that count toward progression — work rather than warm-ups.
    public var workingSets: [SnapshotPerformedSet] { sets.filter { !$0.isWarmup } }
}

/// One set the user actually did.
///
/// **Every measure is optional, and they never mix.** `nil` is *he did not say*;
/// a number is *he did that much*. A hold is seconds and a carry is a distance
/// in the unit it was prescribed in, and neither is ever added into a rep total
/// — that would be a number nobody performed, propagating into every report
/// that follows.
///
/// **`reps` is optional for the same reason the others are.** A set prescribed
/// as a range and ticked without a number used to arrive as `0`, which a coach
/// reads as a completed working set at `185 lb × 0`.
///
/// **What it depends on.** `Mass`, `Distance`.
public struct SnapshotPerformedSet: Codable, Hashable, Sendable {

    /// Where this sat among the exercise's sets.
    public let setIndex: Int
    /// Whether it was performed as a warm-up.
    public let isWarmup: Bool
    /// What was on the bar. `nil` for bodyweight, and `nil` when he did not say.
    public let load: Mass?
    /// How many. `nil` when he did not state a count.
    public let reps: Int?
    /// How long it was held. `nil` when it was not timed.
    public let durationSeconds: Int?
    /// How far it was carried, in the unit prescribed. Never converted.
    public let distance: Distance?
    /// The moment it was recorded. Consecutive values are what rest actually
    /// taken is derived from, which is truer than what a timer counted.
    public let completedAt: Date

    public init(
        setIndex: Int, isWarmup: Bool = false, load: Mass? = nil, reps: Int? = nil,
        durationSeconds: Int? = nil, distance: Distance? = nil, completedAt: Date
    ) {
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.load = load
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case setIndex, isWarmup, load, reps, durationSeconds, distance, completedAt
    }

    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setIndex = try container.decode(Int.self, forKey: .setIndex)
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        load = try container.decodeIfPresent(Mass.self, forKey: .load)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        distance = try container.decodeIfPresent(Distance.self, forKey: .distance)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
    }

    /// Written by hand so a working set carries no `"isWarmup": false`, matching
    /// `PlanDocumentSet` on the other side of the seam. Most sets are working
    /// sets, and a key stating the default on every one of them is noise in a
    /// file a person reads.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setIndex, forKey: .setIndex)
        if isWarmup { try container.encode(true, forKey: .isWarmup) }
        try container.encodeIfPresent(load, forKey: .load)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encode(completedAt, forKey: .completedAt)
    }
}
