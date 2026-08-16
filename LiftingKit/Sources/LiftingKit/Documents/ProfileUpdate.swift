import Foundation

/// A change to the lifter's standing facts, as Claude learned them in
/// conversation.
///
/// This travels the same way a `PlanDocument` does — the MCP server writes one
/// into the shared folder, the app notices it and applies it — and it is the
/// only way facts about the lifter enter the app, because the app asks him
/// nothing. Encode it with `makeEncoder()` and decode it with `makeDecoder()`
/// so the Mac and the phone cannot disagree about how a date is written.
///
/// **It is a patch, not a record.** A field it does not mention is left exactly
/// as it was; that is what lets Claude record one thing it just learned ("he has
/// a rack now") without restating, and possibly clobbering, everything else. A
/// field it sets to `null` returns to not-known, which is how a fact recorded in
/// error is taken back rather than merely overwritten with another guess.
///
/// **Two of its facts are series rather than values.** `bodyweight` and
/// `baselines` are lists of records, each keyed on what it is about — a
/// bodyweight reading on its day, a baseline on its lift. A record for a key the
/// store does not have is added and one for a key it has replaces that entry, so
/// appending to the series and correcting a mistaken entry are the same verb and
/// no history is ever silently dropped. They are not `StatedValue` fields, and
/// deliberately: a wholesale replacement is exactly what would destroy the trend
/// the first time Claude recorded a single weigh-in.
///
/// `id` is the update's stable identity: an update already applied is applied
/// once, so a document left sitting in the folder does not keep re-imposing
/// itself over a later change.
///
/// Depends on: `StatedValue`, `MassUnit`, `ExperienceLevel`, `EquipmentType`,
/// `MovementPattern`, `ExerciseID`, `Weekday`, `BodyweightReading` and
/// `BaselineStatement`. Pure value types by design — the macOS server writes
/// these and must never link SwiftData, so the mapping into the store lives in
/// the app.
public struct ProfileUpdate: Codable, Hashable, Sendable, Identifiable {

    /// The format version this build writes. Bump it when a reader would need
    /// to behave differently, not for an additive field.
    ///
    /// Version 2 replaced the coarse `equipmentAccess` tier with `equipment`,
    /// the open set of what the lifter actually owns, and added the two facts
    /// nothing could previously write at all: `bodyweight` and `baselines`. A
    /// version 1 document is still read — its tier is expanded into the
    /// equipment it stood for, and a tier this build does not recognize is
    /// carried as an equipment type rather than refused.
    public static let currentVersion = 2

    /// The format version of this document, as written.
    public let version: Int
    /// The update's stable identity. Applying the same identity twice changes
    /// nothing the second time.
    public let id: UUID
    /// When the update was written. The app records when it *arrived*
    /// separately, since an update can be written before it is applied. It is
    /// also the day a bodyweight reading or a baseline that named no date
    /// belongs to.
    public let generatedAt: Date

    /// How the app renders weights. Not a training fact — it is the one thing
    /// the lifter can still set for himself in Settings.
    public let displayUnit: StatedValue<MassUnit>
    public let experience: StatedValue<ExperienceLevel>
    /// What he owns, as an open set of equipment types. Replaces the stored set
    /// wholesale rather than adding to it — a patch that could only add could
    /// never record a gym membership that lapsed. An empty set is a lifter who
    /// owns nothing; `unstated` is a lifter nobody has asked.
    public let equipment: StatedValue<[EquipmentType]>
    /// What he is training for, in his words. Cleared to no stated goal.
    public let goal: StatedValue<String>
    /// Injuries and limitations, in his words. Cleared to no stated constraint.
    public let constraints: StatedValue<String>
    /// Movement patterns to keep out of his training. Replaces the stored list
    /// wholesale rather than adding to it — a patch that could only add could
    /// never record a shoulder that healed.
    public let avoidedPatterns: StatedValue<[MovementPattern]>
    /// Specific exercises to keep out of his training. Replaces wholesale, for
    /// the same reason.
    public let avoidedExercises: StatedValue<[ExerciseID]>
    /// The days he says he wants to train. Replaces wholesale.
    public let preferredWeekdays: StatedValue<[Weekday]>
    /// How long he wants a session to run.
    public let preferredDurationMinutes: StatedValue<Int>
    /// Bodyweight readings to record, each on its own day. Empty when this
    /// update says nothing about his weight — never a clearing of the series.
    public let bodyweight: [BodyweightReading]
    /// Starting strength to record, each on its own lift. Empty when this update
    /// states none.
    public let baselines: [BaselineStatement]

    public init(
        version: Int = ProfileUpdate.currentVersion,
        id: UUID,
        generatedAt: Date,
        displayUnit: StatedValue<MassUnit> = .unchanged,
        experience: StatedValue<ExperienceLevel> = .unchanged,
        equipment: StatedValue<[EquipmentType]> = .unchanged,
        goal: StatedValue<String> = .unchanged,
        constraints: StatedValue<String> = .unchanged,
        avoidedPatterns: StatedValue<[MovementPattern]> = .unchanged,
        avoidedExercises: StatedValue<[ExerciseID]> = .unchanged,
        preferredWeekdays: StatedValue<[Weekday]> = .unchanged,
        preferredDurationMinutes: StatedValue<Int> = .unchanged,
        bodyweight: [BodyweightReading] = [],
        baselines: [BaselineStatement] = []
    ) {
        self.version = version
        self.id = id
        self.generatedAt = generatedAt
        self.displayUnit = displayUnit
        self.experience = experience
        self.equipment = equipment
        self.goal = goal
        self.constraints = constraints
        self.avoidedPatterns = avoidedPatterns
        self.avoidedExercises = avoidedExercises
        self.preferredWeekdays = preferredWeekdays
        self.preferredDurationMinutes = preferredDurationMinutes
        self.bodyweight = bodyweight
        self.baselines = baselines
    }

    /// Whether this update would change nothing at all. An empty patch is not
    /// an error — it is a caller that learned nothing — but it is worth being
    /// able to say so rather than reporting a write that meant nothing.
    public var statesNothing: Bool {
        displayUnit.isUnchanged && experience.isUnchanged && equipment.isUnchanged
            && goal.isUnchanged && constraints.isUnchanged && avoidedPatterns.isUnchanged
            && avoidedExercises.isUnchanged && preferredWeekdays.isUnchanged
            && preferredDurationMinutes.isUnchanged && bodyweight.isEmpty && baselines.isEmpty
    }

    /// This update laid over one that has not been applied yet.
    ///
    /// The folder holds one update at a time, so a second one written before
    /// the phone has taken the first in would otherwise replace it and lose
    /// what it said. Fold instead: this update's fields win where it states
    /// anything, and the earlier one's stand where it does not. The result
    /// keeps *this* update's identity and timestamp, because it is the document
    /// that will actually be written.
    ///
    /// The two series fold record by record on their own keys, so a weigh-in
    /// from the earlier update survives a later one about a different day and is
    /// corrected by a later one about the same day — the same rule the app
    /// applies when it stores them.
    ///
    /// Only correct against an update that is genuinely still waiting. Folding
    /// in one the phone has already applied would re-impose facts the lifter
    /// may have changed since.
    public func superseding(_ earlier: ProfileUpdate) -> ProfileUpdate {
        ProfileUpdate(
            version: version,
            id: id,
            generatedAt: generatedAt,
            displayUnit: displayUnit.superseding(earlier.displayUnit),
            experience: experience.superseding(earlier.experience),
            equipment: equipment.superseding(earlier.equipment),
            goal: goal.superseding(earlier.goal),
            constraints: constraints.superseding(earlier.constraints),
            avoidedPatterns: avoidedPatterns.superseding(earlier.avoidedPatterns),
            avoidedExercises: avoidedExercises.superseding(earlier.avoidedExercises),
            preferredWeekdays: preferredWeekdays.superseding(earlier.preferredWeekdays),
            preferredDurationMinutes: preferredDurationMinutes.superseding(
                earlier.preferredDurationMinutes),
            bodyweight: Self.folded(bodyweight, over: earlier.bodyweight, keyedBy: \.date),
            baselines: Self.folded(baselines, over: earlier.baselines, keyedBy: \.exerciseID)
        )
    }

    /// The earlier records with these laid over them: one about a key the
    /// earlier list does not have is appended, and one about a key it does have
    /// takes that record's place. Order is the earlier list's, so a series stays
    /// in the order it was built up in.
    private static func folded<Record, Key: Hashable>(
        _ later: [Record], over earlier: [Record], keyedBy key: (Record) -> Key
    ) -> [Record] {
        var folded = earlier
        for record in later {
            if let existing = folded.firstIndex(where: { key($0) == key(record) }) {
                folded[existing] = record
            } else {
                folded.append(record)
            }
        }
        return folded
    }
}
