import Foundation

/// Everything the app knows about one lifter, as a tree of plain values.
///
/// This is the document the app writes when it backgrounds and Claude reads
/// through the MCP server: who the lifter is, his bodyweight history, his
/// strength baselines, and every plan with every set logged against it. Build
/// one with the app's `SnapshotExporter`, encode it with `makeEncoder()`, and
/// decode it with `makeDecoder()` so both clients agree on how dates are
/// written. `version` identifies this format; `catalogVersion` records which
/// generation of `exercises.json` the exercise IDs inside were selected from,
/// so a reader can tell a snapshot built against older catalog data rather
/// than silently reinterpreting it.
///
/// Every weight is carried as the lifter entered it. Nothing here converts a
/// load into a common unit — `Mass` compares exactly on representation, and a
/// snapshot that canonicalized would misreport what was actually lifted.
/// Absent values stay absent: no profile, no rest prescription, and no load are
/// all `nil`, never a substituted default.
///
/// Depends on: `Mass`, `ExerciseID`, and the taxonomies in `Domain`. Pure value
/// types by design — the macOS server links this package and must never link
/// SwiftData, so the mapping from the stored models lives in the app.
public struct TrainingSnapshot: Codable, Hashable, Sendable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    ///
    /// Version 2 dropped the per-set `rpe` a lifter used to be asked for. That
    /// is a removal rather than an addition, so a reader that went looking for
    /// the key would find a version 1 document answering it and a version 2 one
    /// silent, and needs to know which it is holding. A version 1 snapshot
    /// still reads: `rpe` is simply a key this format no longer has, and the
    /// sets around it are unchanged.
    public static let currentVersion = 2

    /// The format version of this document, as written.
    public let version: Int
    /// The `ExerciseCatalogProviding.version` these exercise IDs came from.
    public let catalogVersion: Int
    /// When the snapshot was produced. A reader uses it to judge staleness.
    public let generatedAt: Date
    /// The lifter's standing facts. `nil` when the store holds no profile
    /// record at all — an empty store is a normal state, not an error. A
    /// profile that is present but says nothing about him is `nil` in every
    /// field instead, which is a different and equally normal state.
    public let profile: SnapshotProfile?
    /// Bodyweight readings, oldest first. Empty when none were recorded.
    public let bodyMetrics: [SnapshotBodyMetric]
    /// Stated starting strength per exercise, oldest first.
    public let baselines: [SnapshotBaseline]
    /// Every training block the lifter has, oldest first.
    public let plans: [SnapshotPlan]

    public init(
        version: Int = TrainingSnapshot.currentVersion,
        catalogVersion: Int,
        generatedAt: Date,
        profile: SnapshotProfile? = nil,
        bodyMetrics: [SnapshotBodyMetric] = [],
        baselines: [SnapshotBaseline] = [],
        plans: [SnapshotPlan] = []
    ) {
        self.version = version
        self.catalogVersion = catalogVersion
        self.generatedAt = generatedAt
        self.profile = profile
        self.bodyMetrics = bodyMetrics
        self.baselines = baselines
        self.plans = plans
    }

    /// Decoding tolerates an absent section, so a snapshot from a lifter with
    /// no plans yet — or one written before a section existed — reads as empty
    /// rather than failing. The three version and timestamp fields are
    /// required: a document that cannot say what it is or when it was made is
    /// not a snapshot.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        catalogVersion = try container.decode(Int.self, forKey: .catalogVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        profile = try container.decodeIfPresent(SnapshotProfile.self, forKey: .profile)
        bodyMetrics = try container.decodeIfPresent(
            [SnapshotBodyMetric].self, forKey: .bodyMetrics) ?? []
        baselines = try container.decodeIfPresent(
            [SnapshotBaseline].self, forKey: .baselines) ?? []
        plans = try container.decodeIfPresent([SnapshotPlan].self, forKey: .plans) ?? []
    }

    /// The encoder both clients use. ISO 8601 dates and sorted keys, so a
    /// snapshot is diffable and a Mac and a phone cannot disagree about an
    /// instant.
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

/// The lifter's standing facts: his equipment, his experience, his
/// constraints, and when he wants to train.
///
/// Read it to know who a plan is for. It is a record of what he said, not a
/// conclusion drawn from it — and the app asks him nothing, so everything here
/// arrived through a `ProfileUpdate` Claude wrote after learning it.
///
/// **A fact nobody has stated is absent, never a default.** `experience` and
/// `availableEquipment` are optional because "he has not said" and "he said full
/// gym" are different answers, and a reader given the second when the first is
/// true will plan confidently for a lifter who does not exist. Free text and
/// lists say the same thing with an empty value, which is documented on each.
///
/// `availableEquipment` is what he can actually train with: the open set of
/// equipment he said he owns, and bodyweight besides. It is not a tier, because
/// a real gym is not one — "barbell and bands but no rack" is what a lot of
/// people train in. It is `nil`, never `[]`, when nobody has said: an empty list
/// would read as a lifter who can perform nothing, which is a much stronger
/// claim than not knowing.
///
/// Depends on: `Mass`, `ExerciseID`, `MovementPattern`, `EquipmentType`,
/// `ExperienceLevel`, `Weekday`.
public struct SnapshotProfile: Codable, Hashable, Sendable {

    /// How weights are shown and what new entries are entered in. It never
    /// rewrites what was already logged. Always present: the app has to render
    /// a number somehow, so this is a display setting rather than a claim about
    /// the lifter.
    public let displayUnit: MassUnit
    /// Rough training age, as he described it. `nil` when he has not said.
    public let experience: ExperienceLevel?
    /// What he can train with: the equipment he said he owns, and bodyweight
    /// besides. `nil` when he has not said — not known, as distinct from none.
    public let availableEquipment: [EquipmentType]?
    /// What he is training for, in his own words. Empty means he has not said.
    public let goal: String
    /// Injuries and limitations, in his own words. Empty means he has not said.
    public let constraints: String
    /// The last bodyweight entered, in the unit entered. `nil` until set.
    public let bodyweight: Mass?
    public let avoidedPatterns: [MovementPattern]
    public let avoidedExercises: [ExerciseID]
    /// The days he said he wants to train. Empty means he has not said.
    public let preferredWeekdays: [Weekday]
    /// How long he wants a session to run. `nil` means he has not said.
    public let preferredDurationMinutes: Int?
    /// The last `ProfileUpdate` this profile took in. A writer reads it to tell
    /// an update still waiting in the folder from one already applied, which is
    /// the difference between folding a new update onto it and re-imposing
    /// facts the lifter may have changed since. `nil` when none has been
    /// applied.
    public let appliedProfileUpdateID: UUID?
    public let updatedAt: Date

    public init(
        displayUnit: MassUnit, experience: ExperienceLevel?,
        availableEquipment: [EquipmentType]?, goal: String, constraints: String,
        bodyweight: Mass?, avoidedPatterns: [MovementPattern],
        avoidedExercises: [ExerciseID], preferredWeekdays: [Weekday],
        preferredDurationMinutes: Int?, appliedProfileUpdateID: UUID? = nil, updatedAt: Date
    ) {
        self.displayUnit = displayUnit
        self.experience = experience
        self.availableEquipment = availableEquipment
        self.goal = goal
        self.constraints = constraints
        self.bodyweight = bodyweight
        self.avoidedPatterns = avoidedPatterns
        self.avoidedExercises = avoidedExercises
        self.preferredWeekdays = preferredWeekdays
        self.preferredDurationMinutes = preferredDurationMinutes
        self.appliedProfileUpdateID = appliedProfileUpdateID
        self.updatedAt = updatedAt
    }
}

/// One dated bodyweight reading.
///
/// Read the series to see a trend. `bodyweight` is `nil` rather than zero when
/// a reading was not entered. Depends on: `Mass`.
public struct SnapshotBodyMetric: Codable, Hashable, Sendable {
    public let date: Date
    /// The reading as entered, in the unit entered. `nil` when not recorded.
    public let bodyweight: Mass?

    public init(date: Date, bodyweight: Mass?) {
        self.date = date
        self.bodyweight = bodyweight
    }
}

/// What the lifter stated he could do on one exercise before any history
/// existed.
///
/// Read it as the starting point for a movement with no logged sets yet.
/// `load` is `nil` for a bodyweight baseline rather than zero, so "no external
/// weight" and "an empty bar" stay distinguishable. Depends on: `ExerciseID`,
/// `Mass`.
public struct SnapshotBaseline: Codable, Hashable, Sendable {
    public let exerciseID: ExerciseID
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    public let load: Mass?
    public let reps: Int
    public let recordedAt: Date

    public init(exerciseID: ExerciseID, load: Mass?, reps: Int, recordedAt: Date) {
        self.exerciseID = exerciseID
        self.load = load
        self.reps = reps
        self.recordedAt = recordedAt
    }
}
