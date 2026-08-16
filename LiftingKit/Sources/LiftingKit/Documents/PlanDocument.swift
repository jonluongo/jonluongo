import Foundation

/// A training plan exactly as Claude wrote it, as a tree of plain values.
///
/// This is the document that travels the other way from `TrainingSnapshot`:
/// Claude reads the snapshot, decides the training, and writes one of these;
/// the app imports it and the lifter sees workout tables. Encode it with
/// `makeEncoder()` and decode it with `makeDecoder()` so the macOS server and
/// the phone cannot disagree about how a date is written. The app maps it into
/// SwiftData with `PlanImporter`, which checks one thing and changes nothing.
///
/// **A block is a list of weeks, and the weeks may differ.** That is what makes
/// periodization sayable: week 3 can prescribe heavier work than week 1 and
/// week 4 can be a deload, rather than one week being repeated by whoever reads
/// it. A block of a single week states a single week.
///
/// **An exercise's sets may differ from one another.** That is what makes a
/// drop set, a ramp, a back-off set and a per-set note sayable — see
/// `PlanDocumentExercise.sets`, which is a count when the work is the same
/// throughout and a list when it is not. `intensity` states how hard the work
/// should be, on whatever scale the plan works in.
///
/// Nothing in this format is a suggestion to be adjusted. A set count, a rest,
/// a rep range, and a load are recorded exactly as written; `id` is the
/// document's stable identity, so importing the same plan twice is a no-op
/// rather than a duplicate. `catalogVersion` states which generation of
/// `exercises.json` the `ExerciseID`s inside were chosen from, so a plan
/// written against older catalog data is detectable rather than silently
/// reinterpreted.
///
/// **A key this format does not have is refused, not dropped** — see
/// `DocumentRefusal`. A silently ignored key tells the writer a prescription
/// landed when none of it did.
///
/// Depends on: `Weekday`, `ExerciseID`, and `Mass` from `Domain`, and
/// `DocumentRefusal`. Pure value types by design — the macOS server writes
/// these and must never link SwiftData, so the mapping into the store lives in
/// the app.
public struct PlanDocument: Codable, Hashable, Sendable, Identifiable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    ///
    /// Version 3 let an exercise list its sets one at a time and state how hard
    /// they should be: `sets` may now be a list rather than a count, which a
    /// version 2 reader could not read, and `intensity` is a key it did not
    /// have. Version 2 made the block a list of weeks. Version 1 stated one week
    /// as a bare `days` array, which is still read — that shape is now the way a
    /// single-week block is written, so there is one rule rather than two.
    /// Every one of those documents still imports.
    public static let currentVersion = 3

    /// The format version of this document, as written.
    public let version: Int
    /// The document's stable identity. Re-importing the same identity updates
    /// nothing and duplicates nothing.
    public let id: UUID
    /// The `ExerciseCatalogProviding.version` these exercise IDs were chosen
    /// from.
    public let catalogVersion: Int
    /// When the plan was written. The app records when it *arrived* separately,
    /// since a plan can be written before it is imported.
    public let generatedAt: Date
    /// Short name for the block, such as "Spring strength". May be empty.
    public let title: String
    /// What the block is for, in the coach's words. May be empty.
    public let goal: String
    /// How long a session in this block runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    /// Anything the coach wants the lifter to read alongside the plan. `nil`
    /// when there is none.
    public let notes: String?
    /// The block's weeks, in the order they are to be trained. A week's
    /// position in this list is its ordinal, so two weeks cannot claim to be
    /// week 3.
    public let weeks: [PlanDocumentWeek]

    /// How many weeks the block runs: the number of weeks it states.
    ///
    /// Derived rather than stored, because a separately stated count is a
    /// number that can disagree with the document holding it — and the reader
    /// that believed the count over the content is how seven weeks of a
    /// declared eight-week block used to vanish. A document may still *state*
    /// `weekCount`, and it is checked against this rather than ignored.
    public var weekCount: Int { weeks.count }

    public init(
        version: Int = PlanDocument.currentVersion,
        id: UUID,
        catalogVersion: Int,
        generatedAt: Date,
        title: String = "",
        goal: String = "",
        durationMinutes: Int? = nil,
        notes: String? = nil,
        weeks: [PlanDocumentWeek] = []
    ) {
        self.version = version
        self.id = id
        self.catalogVersion = catalogVersion
        self.generatedAt = generatedAt
        self.title = title
        self.goal = goal
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.weeks = weeks
    }

    /// A block of one week, stated as its days.
    ///
    /// The single-week case is the ordinary one and must not become verbose to
    /// write. The week it makes carries no label and is not a deload, because
    /// the caller said neither.
    public init(
        version: Int = PlanDocument.currentVersion,
        id: UUID,
        catalogVersion: Int,
        generatedAt: Date,
        title: String = "",
        goal: String = "",
        durationMinutes: Int? = nil,
        notes: String? = nil,
        days: [PlanDocumentDay]
    ) {
        self.init(
            version: version, id: id, catalogVersion: catalogVersion,
            generatedAt: generatedAt, title: title, goal: goal,
            durationMinutes: durationMinutes, notes: notes,
            weeks: [PlanDocumentWeek(days: days)]
        )
    }

    /// Spelled out rather than left to synthesis: the reader needs to know
    /// every key this format has in order to refuse one it does not.
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, catalogVersion, generatedAt
        case title, goal, durationMinutes, notes, weeks
    }

    /// The two keys a single-week block may state instead of `weeks`. Version 1
    /// wrote both; both are still read, and `weekCount` is checked rather than
    /// ignored.
    private enum SingleWeekCodingKeys: String, CodingKey {
        case days, weekCount
    }

    private static let acceptedKeys: Set<String> =
        Set(CodingKeys.allCases.map(\.stringValue)).union(["days", "weekCount"])

    /// Decoding requires only what makes a document a document: its format
    /// version, the catalog generation it was written against, its identity,
    /// and when it was written. Everything else is optional, because a plan
    /// that does not state a title, a length, or a rest is stating an absence
    /// — and a decoder that supplied one would be inventing a prescription.
    ///
    /// The order of the checks is the order of the questions: a document from a
    /// later format is refused as such before any of its keys are held against
    /// it, since a key this build has never heard of is exactly what a later
    /// format is made of and "unknown key" would misdirect.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.currentVersion else {
            throw DocumentRefusal.laterVersion(version, understood: Self.currentVersion)
        }
        try decoder.refuseUnknownKeys(besides: Self.acceptedKeys)

        id = try container.decode(UUID.self, forKey: .id)
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        weeks = try Self.weeks(from: decoder, container)
    }

    /// The block's weeks, however the block stated them.
    ///
    /// A bare `days` array is one week — the shape version 1 wrote, and the
    /// short way to say a single-week block. Stating both is refused rather
    /// than resolved: a reader that picked one would drop the other, and there
    /// is no telling which the writer meant.
    private static func weeks(
        from decoder: any Decoder, _ container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [PlanDocumentWeek] {
        let single = try decoder.container(keyedBy: SingleWeekCodingKeys.self)
        let stated = try container.decodeIfPresent([PlanDocumentWeek].self, forKey: .weeks)
        let days = try single.decodeIfPresent([PlanDocumentDay].self, forKey: .days)

        if stated != nil, days != nil {
            throw DocumentRefusal.contradiction(
                "This plan states both 'weeks' and 'days', and only one of them can be the "
                    + "block. Nothing was taken in. Send 'weeks' — a single-week block is one "
                    + "entry in it — or send 'days' alone.")
        }
        let weeks = stated ?? days.map { [PlanDocumentWeek(days: $0)] } ?? []

        if let claimed = try single.decodeIfPresent(Int.self, forKey: .weekCount),
            claimed != weeks.count {
            throw DocumentRefusal.contradiction(
                "This plan says it runs \(claimed) weeks but states \(weeks.count). Nothing was "
                    + "taken in, because the weeks it does not state would simply be missing. "
                    + "Send one entry in 'weeks' for every week of the block, each with its own "
                    + "days; 'weekCount' is then whatever you sent and need not be stated. A plan "
                    + "left over from an earlier build says this — it stated a length beside a "
                    + "single week of 'days' — and writing it again is the whole of the fix.")
        }
        return weeks
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so a plan
    /// is diffable and a Mac and a phone cannot disagree about an instant.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The matching decoder. Use it rather than a bare `JSONDecoder`, whose
    /// default date strategy would reject everything `makeEncoder()` writes.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One week of a `PlanDocument`.
///
/// **Weeks are stated one at a time because they differ.** A block that ramps
/// says so by prescribing more in week 3 than in week 1, and a deload says so
/// with `isDeload` — the flag `TrainingWeek` and `SnapshotWeek` have always
/// carried and nothing could previously write. A week's ordinal is its position
/// in the document's `weeks`, so nothing has to reconcile a stated number with
/// where the week actually sits.
///
/// Depends on: `PlanDocumentDay`, `DocumentRefusal`.
public struct PlanDocumentWeek: Codable, Hashable, Sendable {

    /// What the plan calls this week, such as "Accumulation". `nil` when the
    /// plan did not name it — a week with no name has no name, and "Week 1" is
    /// the reader's way of saying where it sits, not something the plan said.
    public let label: String?
    /// Whether the plan marks this week as a deload. `false` when it did not
    /// say so, which is the whole of what can be known: a week not called a
    /// deload is not one.
    public let isDeload: Bool
    /// This week's training days, in the order they should be read. A day with
    /// no exercises is a rest day, not an omission.
    public let days: [PlanDocumentDay]

    public init(label: String? = nil, isDeload: Bool = false, days: [PlanDocumentDay] = []) {
        self.label = label
        self.isDeload = isDeload
        self.days = days
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, isDeload, days
    }

    /// Nothing is required: a week that says only what it trains is an ordinary
    /// week. An unknown key is refused, as everywhere else in this format.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        isDeload = try container.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        days = try container.decodeIfPresent([PlanDocumentDay].self, forKey: .days) ?? []
    }
}
