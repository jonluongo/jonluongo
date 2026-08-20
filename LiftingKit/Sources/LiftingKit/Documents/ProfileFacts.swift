import Foundation

/// One dated bodyweight reading, as it was told to whoever recorded it.
///
/// **What it does.** Names a day and what the lifter weighed on it. It is one
/// point of a series rather than a current value: a single mutable number
/// answers "what does he weigh" and destroys the answer to "which way is it
/// going", and the second question is the one a coach actually asks — it is also
/// the question the store's `BodyMetric` was built as a dated series to answer.
///
/// **How it is used.** A `ProfileUpdate` carries any number of these and the app
/// records each against its day. **A reading is keyed on its date.** A day the
/// log does not have is added; a day it already has is replaced, because a
/// lifter has one bodyweight on a given day and a second statement about that
/// day is a correction of the first rather than a second measurement. That is
/// how appending and correcting are one verb: to fix a reading, state that day
/// again.
///
/// **What it depends on.** `Mass` and `DocumentRefusal`. `date` is `nil` when
/// nobody said which day, and reads as the day the update was written — that is
/// when the fact was recorded, not a guess about when he stood on the scale.
/// `mass` is required and is carried in the unit it was given in: a reading with
/// no weight in it is not a reading.
public struct BodyweightReading: Codable, Hashable, Sendable {

    /// The day the reading is about. `nil` when the update did not say.
    public let date: Date?
    /// What he weighed, in the unit it was stated in. Never converted.
    public let mass: Mass

    public init(date: Date?, mass: Mass) {
        self.date = date
        self.mass = mass
    }

    /// The day this reading belongs to, given when the update carrying it was
    /// written. A reading that named no day belongs to the day it was recorded.
    public func resolvedDate(from generatedAt: Date) -> Date { date ?? generatedAt }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case date, mass
    }

    /// Only the weight is required. A key this format does not have is refused
    /// with the key named rather than dropped — a body-fat percentage silently
    /// discarded is a fact reported as recorded and written down nowhere.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        mass = try container.decode(Mass.self, forKey: .mass)
    }
}

/// What the lifter stated he could already do on one lift, before any of it was
/// logged.
///
/// **What it does.** Names a lift, a load and a rep count — the anchor a first
/// plan needs, because a block written for a lifter with no history has nothing
/// else to set a load against.
///
/// **How it is used.** A `ProfileUpdate` carries any number of these and the app
/// records each against its lift. **A baseline is keyed on its `exerciseID`.** A
/// lift has one starting point, so a second statement about the same lift
/// replaces the first rather than sitting beside it as a rival answer; progress
/// after that point lives in the log, which is where it can be seen set by set.
///
/// **What it depends on.** `ExerciseID`, `Mass`, `DocumentRefusal`. `load` is
/// `nil` for a bodyweight baseline rather than zero, so "no external weight" and
/// "an empty bar" stay distinguishable. `recordedAt` is `nil` when nobody said
/// when, and reads as when the update was written. The `exerciseID` is checked
/// against the catalog before anything is stored, for the reason `PlanImporter`
/// checks one: history is keyed on exercise identity, and an invented ID would
/// anchor a series nothing else will ever join.
public struct BaselineStatement: Codable, Hashable, Sendable {

    public let exerciseID: ExerciseID
    /// The weight as stated, in the unit stated. `nil` means bodyweight.
    public let load: Mass?
    public let reps: Int
    /// When the lifter could do it. `nil` when the update did not say.
    public let recordedAt: Date?

    public init(exerciseID: ExerciseID, load: Mass?, reps: Int, recordedAt: Date?) {
        self.exerciseID = exerciseID
        self.load = load
        self.reps = reps
        self.recordedAt = recordedAt
    }

    /// When this baseline was recorded, given when the update carrying it was
    /// written.
    public func resolvedDate(from generatedAt: Date) -> Date { recordedAt ?? generatedAt }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case exerciseID, load, reps, recordedAt
    }

    /// The lift and the reps are required — a baseline that cannot say which
    /// movement, or how many, anchors nothing — and the reps have to be at
    /// least one, for the same reason. An unknown key is refused by
    /// name, as everywhere else in this format.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseID = try container.decode(ExerciseID.self, forKey: .exerciseID)
        load = try container.decodeIfPresent(Mass.self, forKey: .load)
        reps = try container.decode(Int.self, forKey: .reps)
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt)

        // **A baseline of no repetitions anchors nothing**, which is the same
        // reason the key is required at all. Zero would be recorded as a fact
        // and shown to the lifter as *225 lb × 0* — a set nobody performed,
        // sitting in the one place the record says what he can already do.
        guard reps > 0 else {
            throw DocumentRefusal.contradiction(
                "The baseline for '\(exerciseID.rawValue)' says \(reps) repetitions. A "
                    + "baseline is the most he has done on a lift, so it has to be at least "
                    + "one — nothing was taken in. Send the reps he actually did, or leave the "
                    + "baseline out until he says.")
        }
    }
}
