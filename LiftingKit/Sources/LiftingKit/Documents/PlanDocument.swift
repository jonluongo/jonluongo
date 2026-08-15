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
/// Nothing in this format is a suggestion to be adjusted. A set count, a rest,
/// a rep range, and a load are recorded exactly as written; `id` is the
/// document's stable identity, so importing the same plan twice is a no-op
/// rather than a duplicate. `catalogVersion` states which generation of
/// `exercises.json` the `ExerciseID`s inside were chosen from, so a plan
/// written against older catalog data is detectable rather than silently
/// reinterpreted.
///
/// Depends on: `Weekday`, `ExerciseID`, and `Mass` from `Domain`. Pure value
/// types by design — the macOS server writes these and must never link
/// SwiftData, so the mapping into the store lives in the app.
public struct PlanDocument: Codable, Hashable, Sendable, Identifiable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    public static let currentVersion = 1

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
    /// How many weeks the block runs. `nil` when the plan did not say.
    public let weekCount: Int?
    /// How long a session in this block runs. `nil` when the plan did not say.
    public let durationMinutes: Int?
    /// Anything the coach wants the lifter to read alongside the plan. `nil`
    /// when there is none.
    public let notes: String?
    /// The block's training days, in the order they should be read. A day with
    /// no exercises is a rest day, not an omission.
    public let days: [PlanDocumentDay]

    public init(
        version: Int = PlanDocument.currentVersion,
        id: UUID,
        catalogVersion: Int,
        generatedAt: Date,
        title: String = "",
        goal: String = "",
        weekCount: Int? = nil,
        durationMinutes: Int? = nil,
        notes: String? = nil,
        days: [PlanDocumentDay] = []
    ) {
        self.version = version
        self.id = id
        self.catalogVersion = catalogVersion
        self.generatedAt = generatedAt
        self.title = title
        self.goal = goal
        self.weekCount = weekCount
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.days = days
    }

    /// Decoding requires only what makes a document a document: its format
    /// version, the catalog generation it was written against, its identity,
    /// and when it was written. Everything else is optional, because a plan
    /// that does not state a title, a length, or a rest is stating an absence
    /// — and a decoder that supplied one would be inventing a prescription.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(UUID.self, forKey: .id)
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        weekCount = try container.decodeIfPresent(Int.self, forKey: .weekCount)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        days = try container.decodeIfPresent([PlanDocumentDay].self, forKey: .days) ?? []
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

/// One training day of a `PlanDocument`.
///
/// Read `exercises` in the order given — that is the order the work is meant to
/// be done in, and nothing downstream re-sorts it. An empty `exercises` is a
/// rest day the plan named on purpose, not a day that failed to be filled in.
///
/// Depends on: `Weekday`, `PlanDocumentExercise`.
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

    /// Only `weekday` is required: a day that cannot say when it happens is not
    /// a day, while a day with no focus and no stated length is perfectly
    /// ordinary.
    public init(from decoder: any Decoder) throws {
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
/// Depends on: `ExerciseID`, `Mass`.
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

    /// The identity, the name, and the set count are required; a prescription
    /// that cannot say which movement or how much work is not a prescription.
    /// The rest is optional so that an absence stays an absence.
    public init(from decoder: any Decoder) throws {
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
