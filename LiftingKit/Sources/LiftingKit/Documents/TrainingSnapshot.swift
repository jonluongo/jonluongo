import Foundation

/// Everything the app knows about the training, as a tree of plain values.
///
/// **What it does.** Carries the record the other way from `PlanDocument`: the
/// app writes one, the coach reads it and decides what to prescribe next. It
/// holds what was asked for, what was done, and when it was exported — and
/// nothing about the user himself, which lives in `ACCOUNT.md` where he can be
/// described in words rather than fields.
///
/// **`exportedAt` is the honest half of a cache.** The phone is the only writer
/// of the record, so a reliable export is always current — but nothing is
/// reliable enough to go unstated, and the failure this guards against arrives
/// looking like a fact: a coach told a block holds four sessions when it holds
/// nine. Every tool that reads this reports the date, so a stale read is
/// visible rather than convincing.
///
/// **A prescription is stated once.** A session carries the plan document's own
/// `PlanDocumentSession`, not a second description of it. A prescription used to
/// live in three vocabularies and two of them disagreed about how a superset is
/// written; there are two now, and the round-trip suite is what says the store
/// holds everything the document stated. Do not add a third.
///
/// **What it depends on.** `PlanDocumentSession`, `Mass`, `Distance`,
/// `ExerciseID` and `PerformanceSource` from the layers above. Pure value types
/// by design — the macOS server links this package and must never link
/// SwiftData, so the mapping from the stored models lives in the app.
///
/// Every weight is carried as the user entered it. Nothing here converts a
/// load into a common unit: `Mass` compares exactly on representation, and a
/// snapshot that canonicalized would misreport what was actually lifted.
public struct TrainingSnapshot: Codable, Hashable, Sendable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    ///
    /// **Version 6 is the rebuild.** The whole `profile` object is gone, and
    /// with it `bodyMetrics`, `baselines`, `statedAt` and the avoid lists —
    /// every one of them display-only in the app, and all of them better said
    /// in prose the coach writes and reads. `routines` and their weekday-keyed
    /// sessions are replaced by a flat `sessions` list, each stating which block
    /// it belongs to; the weekday-keyed `log` and the separate `userNotes` are
    /// replaced by `performances`, one per exercise per day, each holding its
    /// own sets. That grain is the point: *how has bench gone* is a series of
    /// performances, and this format used to answer it with a flat array of sets
    /// that restated the plan, block, weekday and focus on every row.
    /// Version 7 renamed one key: `lifterNote` became `userNote`. **The word
    /// *user* is not one this project uses** — the person is the user and the
    /// AI is the coach — and a wire key is prose the server has to type, so it
    /// was the one place the old word could not simply be edited out of a
    /// comment. Bumped rather than renamed quietly, because a reader handed the
    /// old key would refuse it as unknown and report the wrong problem.
    public static let currentVersion = 7

    /// The format version of this document, as written.
    public let version: Int
    /// When the phone wrote this. Reported by every tool that reads it, so a
    /// coach reading yesterday's record knows that is what he is doing.
    public let exportedAt: Date
    /// Which generation of `exercises.json` the exercise IDs were selected from.
    public let catalogVersion: Int
    /// Every session the coach has prescribed, in no particular order — each
    /// states which block it belongs to and where it sits in that block.
    public let sessions: [SnapshotSession]
    /// Every exercise performed, flat, each carrying its own sets and the
    /// coordinates of the session it belongs to.
    public let performances: [SnapshotPerformedExercise]

    public init(
        version: Int = TrainingSnapshot.currentVersion,
        exportedAt: Date,
        catalogVersion: Int,
        sessions: [SnapshotSession] = [],
        performances: [SnapshotPerformedExercise] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.catalogVersion = catalogVersion
        self.sessions = sessions
        self.performances = performances
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, exportedAt, catalogVersion, sessions, performances
    }

    /// **A snapshot is refused in both directions, and a plan is not.** A plan is
    /// an archive: the coach wrote it and it is the only copy. A snapshot is a
    /// cache the phone rewrites whenever the record changes, so an old one is
    /// not history — it is a stale file that will be replaced the moment the app
    /// opens. Reading one half-way would report a user who has trained less
    /// than he has, which is the one failure that arrives looking like a fact.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DocumentRefusal.snapshotVersionMismatch(
                version, understood: Self.currentVersion)
        }
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))

        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        sessions = try container.decodeIfPresent([SnapshotSession].self, forKey: .sessions) ?? []
        performances = try container.decodeIfPresent(
            [SnapshotPerformedExercise].self, forKey: .performances) ?? []
    }

    /// Every block the record knows about, in order.
    public var blockOrdinals: [Int] {
        Array(Set(sessions.map(\.blockOrdinal))).sorted()
    }

    /// The sessions of one block, in the order they are to be trained.
    public func sessions(inBlock ordinal: Int) -> [SnapshotSession] {
        sessions.filter { $0.blockOrdinal == ordinal }.sorted { $0.ordinal < $1.ordinal }
    }

    /// Every performance of one movement, oldest first — what a coach means by
    /// *how has this lift gone*.
    public func performances(of exerciseID: ExerciseID) -> [SnapshotPerformedExercise] {
        performances.filter { $0.exerciseID == exerciseID }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so a
    /// snapshot is diffable and a Mac and a phone cannot disagree about an
    /// instant.
    public static func makeEncoder() -> JSONEncoder { DocumentCoding.makeEncoder() }

    /// The matching decoder. Use it rather than a bare `JSONDecoder`, whose
    /// default date strategy would reject everything `makeEncoder()` writes.
    public static func makeDecoder() -> JSONDecoder { DocumentCoding.makeDecoder() }
}
