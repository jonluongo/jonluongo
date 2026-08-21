import Foundation

/// A training plan exactly as the coach wrote it, as a tree of plain values.
///
/// **What it does.** Carries prescriptions the other way from `TrainingSnapshot`:
/// the coach reads the snapshot, decides the training, and writes one of these;
/// the app imports it and the lifter sees the sessions. Encode and decode with
/// `makeEncoder()` and `makeDecoder()` so the macOS server and the phone cannot
/// disagree about how a date is written.
///
/// **A plan is a flat list of sessions.** Each says which block it belongs to
/// and where it sits within it, so there is no wrapper to keep in step with its
/// contents — the shape that once let seven weeks of a declared eight-week block
/// vanish, because a stated count could disagree with what was stated. Blocks
/// run continuously and never restart, so a block ordinal also orders the whole
/// timeline. What makes block 3 an accumulation block is a line in `program.md`,
/// not a label here: a block is a number, and the character of one is prose the
/// coach writes for himself to read.
///
/// **Nothing in this format is a suggestion.** A set count, a rest, a target and
/// a load are recorded exactly as written. `id` is the document's stable
/// identity, so importing the same plan twice is a no-op rather than a
/// duplicate, and it names the archived copy the app keeps.
/// `catalogVersion` states which generation of `exercises.json` the
/// `ExerciseID`s were chosen from.
///
/// **A key this format does not have is refused, not dropped** — see
/// `DocumentRefusal`. A silently ignored key tells the writer a prescription
/// landed when none of it did.
///
/// **What it depends on.** `ExerciseID`, `Mass`, `Target` and `SessionIcon` from
/// `Domain`, and `DocumentRefusal`. Pure value types by design: the macOS server
/// writes these and must never link SwiftData, so the mapping into the store
/// lives in the app.
public struct PlanDocument: Codable, Hashable, Sendable, Identifiable {

    /// The format version this build writes. Bump it when a reader would need to
    /// behave differently, not for an additive field.
    ///
    /// **Version 6 is a break, and reads nothing earlier.** Every version up to
    /// 5 stated a routine of named blocks of days keyed by weekday, with an
    /// exercise's sets as either a count or a list. Version 6 has no routine, no
    /// block label, no weekday, and states every set. There is no honest reading
    /// of a version 5 document into it: block ordinals would have to be invented
    /// from list positions and weekdays discarded, which is interpretation
    /// wearing compatibility's clothes. The store resets with this format, so no
    /// earlier document has anywhere to land — an older one is refused naming
    /// both versions, which is what this format does with a *newer* one for the
    /// same reason.
    public static let currentVersion = 6

    /// The format version of this document, as written.
    public let version: Int
    /// The document's stable identity. Re-importing it changes nothing, and it
    /// names the copy the app archives.
    public let id: UUID
    /// The `ExerciseCatalogProviding.version` these exercise IDs were chosen
    /// from.
    public let catalogVersion: Int
    /// When the coach wrote the plan. The app records when it *arrived*
    /// separately, since a plan can be written long before it is imported.
    public let generatedAt: Date
    /// Every session this document prescribes. Order here carries no meaning:
    /// each session says where it sits.
    public let sessions: [PlanDocumentSession]

    public init(
        version: Int = PlanDocument.currentVersion,
        id: UUID,
        catalogVersion: Int,
        generatedAt: Date,
        sessions: [PlanDocumentSession] = []
    ) {
        self.version = version
        self.id = id
        self.catalogVersion = catalogVersion
        self.generatedAt = generatedAt
        self.sessions = sessions
    }

    /// Spelled out rather than left to synthesis: the reader needs to know every
    /// key this format has in order to refuse one it does not.
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, catalogVersion, generatedAt, sessions
    }

    /// The order of the checks is the order of the questions. Version is read
    /// first and judged before any key is held against the document, because a
    /// key this build has never heard of is exactly what another format is made
    /// of, and "unknown key" would misdirect the writer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw version > Self.currentVersion
                ? DocumentRefusal.laterVersion(version, understood: Self.currentVersion)
                : DocumentRefusal.earlierVersion(version, understood: Self.currentVersion)
        }
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))

        id = try container.decode(UUID.self, forKey: .id)
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        sessions = try container.decodeIfPresent(
            [PlanDocumentSession].self, forKey: .sessions) ?? []
    }

    /// Every block this document states, in order, without repeats.
    public var blockOrdinals: [Int] {
        Array(Set(sessions.map(\.blockOrdinal))).sorted()
    }

    /// The sessions of one block, in the order they are to be trained.
    public func sessions(inBlock ordinal: Int) -> [PlanDocumentSession] {
        sessions.filter { $0.blockOrdinal == ordinal }.sorted { $0.ordinal < $1.ordinal }
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so a plan
    /// is diffable and a Mac and a phone cannot disagree about an instant.
    public static func makeEncoder() -> JSONEncoder { DocumentCoding.makeEncoder() }

    /// The matching decoder. Use it rather than a bare `JSONDecoder`, whose
    /// default date strategy would reject everything `makeEncoder()` writes.
    public static func makeDecoder() -> JSONDecoder { DocumentCoding.makeDecoder() }
}
