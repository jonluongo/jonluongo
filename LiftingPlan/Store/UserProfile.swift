import Foundation
import SwiftData
import LiftingKit

/// Who the lifter is: the standing facts that have been recorded about him, his
/// equipment, and when he wants to train.
///
/// This is a record of what he said, not a set of conclusions drawn from it —
/// what to do with these facts is decided elsewhere. Read it to answer
/// questions about the lifter.
///
/// **The app never asks him any of this.** There is no setup screen and no
/// form; every training fact here arrived as a `ProfileUpdate` Claude wrote
/// after learning it in conversation, applied by `ProfileUpdater`. That is why
/// `experience` and `ownedEquipment` are optional: a fresh profile is empty, and
/// "nobody has said" must not be storable only as "full gym, intermediate". A
/// default there would be an assertion about him that no one ever made.
///
/// **His gym is an open set of equipment, not a tier.** A real gym is not one:
/// "barbell and bands but no rack" is what a great many people train in, and
/// forcing it into the nearest tier either grants him machines he does not have
/// or denies him the bar he does.
///
/// Exactly one instance is expected. CloudKit forbids unique constraints, so
/// that invariant is enforced in application code rather than by the schema.
/// `displayUnit` controls what new entries default to and how weights are
/// shown; it never rewrites what was already logged, and it is the one thing
/// here the lifter can still set for himself, in Settings. `avoidedPatterns`
/// and `avoidedExercises` make the free-text `constraints` field enforceable
/// rather than merely advisory: `constraints` still carries nuance ("my left
/// shoulder hurts overhead") that a list cannot express, but the structured
/// lists are what a reader can actually filter the catalog on — `list_exercises`
/// does exactly that, reading them off the snapshot.
///
/// Every property is optional or defaulted, as CloudKit requires.
/// Depends on: `Mass` and `ExerciseID`, `MovementPattern` from Domain.
@Model
final class UserProfile {
    /// Not a training opinion, and not a claim about the lifter — the app has
    /// to render a number in some unit before anyone has said which.
    private var displayUnitRaw: String = MassUnit.pounds.rawValue
    /// `nil` until someone states it. Never a stand-in level.
    private var experienceRaw: String?
    /// What he owns, as raw equipment-type values. `nil` until someone states
    /// it — an empty list is a lifter who owns nothing, which is a different
    /// answer from a lifter nobody has asked. Never a stand-in gym.
    private var ownedEquipmentRawValues: [String]?
    /// What he is training for, in his words. Empty means he has not said.
    var goal: String = ""
    /// Injuries and constraints, in the lifter's own words. Fed to the model.
    var constraints: String = ""
    /// The lifter's current bodyweight, as last entered. `nil` until set.
    /// `BodyMetric` holds the tracked history; this is a convenience copy of
    /// the latest reading for callers that don't need the series.
    var bodyweight: Mass?
    private var avoidedPatternRawValues: [String] = []
    private var avoidedExerciseRawValues: [String] = []
    /// The days the lifter said he wants to train. Empty means he has not said.
    private var preferredWeekdayRawValues: [Int] = []
    /// How long he wants a session to run. `nil` means he has not said.
    var preferredDurationMinutes: Int?
    /// The last `ProfileUpdate` applied to this profile, so an update sitting
    /// in the shared folder is applied once rather than re-imposed at every
    /// launch over something changed since.
    var appliedProfileUpdateID: UUID?
    var updatedAt: Date = Date()

    init(
        displayUnit: MassUnit = .pounds,
        experience: ExperienceLevel? = nil,
        ownedEquipment: [EquipmentType]? = nil,
        goal: String = "", constraints: String = "", bodyweight: Mass? = nil,
        avoidedPatterns: Set<MovementPattern> = [], avoidedExercises: Set<ExerciseID> = [],
        preferredWeekdays: Set<Weekday> = [], preferredDurationMinutes: Int? = nil,
        appliedProfileUpdateID: UUID? = nil
    ) {
        self.displayUnitRaw = displayUnit.rawValue
        self.experienceRaw = experience?.rawValue
        self.ownedEquipmentRawValues = ownedEquipment?.map(\.rawValue)
        self.goal = goal
        self.constraints = constraints
        self.bodyweight = bodyweight
        self.avoidedPatternRawValues = avoidedPatterns.map(\.rawValue).sorted()
        self.avoidedExerciseRawValues = avoidedExercises.map(\.rawValue).sorted()
        self.preferredWeekdayRawValues = preferredWeekdays.map(\.rawValue).sorted()
        self.preferredDurationMinutes = preferredDurationMinutes
        self.appliedProfileUpdateID = appliedProfileUpdateID
        self.updatedAt = Date()
    }

    var displayUnit: MassUnit {
        get { MassUnit(rawValue: displayUnitRaw) ?? .pounds }
        set { displayUnitRaw = newValue.rawValue }
    }

    /// Rough training age, as he described it. `nil` means nobody has said.
    var experience: ExperienceLevel? {
        get { experienceRaw.flatMap(ExperienceLevel.init(rawValue:)) }
        set { experienceRaw = newValue?.rawValue }
    }

    /// The equipment he says he owns. `nil` means nobody has said; `[]` means he
    /// owns none. A type this build has never heard of is carried unchanged —
    /// he owns what he says he owns.
    var ownedEquipment: [EquipmentType]? {
        get { ownedEquipmentRawValues?.map(EquipmentType.init(rawValue:)) }
        set { ownedEquipmentRawValues = newValue?.map(\.rawValue) }
    }

    /// The equipment types this lifter can actually train with, or `nil` when
    /// nobody has said what he has.
    ///
    /// `nil` rather than an empty set on purpose: an empty set says he can
    /// perform nothing, which is a far stronger claim than not knowing, and a
    /// reader filtering on it would find no exercise at all.
    var permittedEquipment: Set<EquipmentType>? {
        ownedEquipment.map(EquipmentAccess.permitted(owning:))
    }

    /// Movement patterns excluded from his training, e.g. for an injury.
    var avoidedPatterns: Set<MovementPattern> {
        get { Set(avoidedPatternRawValues.map(MovementPattern.init(rawValue:))) }
        set { avoidedPatternRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Specific exercises excluded from his training, e.g. a substitution
    /// the lifter has already ruled out.
    var avoidedExercises: Set<ExerciseID> {
        get { Set(avoidedExerciseRawValues.map(ExerciseID.init(rawValue:))) }
        set { avoidedExerciseRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// The days the lifter wants to train, as last stated. This is his
    /// availability, not a schedule the app chose; an empty set means he has
    /// not said yet. A `TrainingPlan` records the days it actually trains,
    /// which need not match.
    var preferredWeekdays: Set<Weekday> {
        get { Set(preferredWeekdayRawValues.compactMap(Weekday.init(rawValue:))) }
        set { preferredWeekdayRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Training days in Monday-first display order.
    var orderedPreferredWeekdays: [Weekday] {
        Weekday.displayOrder.filter { preferredWeekdays.contains($0) }
    }
}
