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
/// shown; it never rewrites what was already logged. It is not a form the app
/// puts in front of him either — pounds or kilos is a fact about how he thinks,
/// he says it in conversation, and `ProfileUpdate.displayUnit` carries it. `avoidedPatterns`
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
    /// The coarse tier an earlier build recorded his gym as, before equipment
    /// became the open set of what he owns. **Retired: read once, never
    /// written.** It is still declared because the column is still in the
    /// store on his phone, and a fact he stated is not something to leave
    /// stranded in a column nothing reads — `StoreUpgrade` carries it across
    /// and clears it. See there for which values are carried and which are the
    /// app's own discarded default.
    private var equipmentAccessRaw: String?
    /// Whether the lifter finished the setup form a build two schema
    /// generations back put in front of him. **Retired: read once, never
    /// written.** It survives only to tell a gym he actually stated from the
    /// `Equipment.fullGym` that build filled in for him before he had said
    /// anything, which is the one thing that decides whether the tier above is
    /// a fact or a fabrication. `nil` on any store written after that form was
    /// removed.
    private var hasCompletedSetup: Bool?
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

    /// A profile as an older build wrote it, for the one caller that has to
    /// read one: the test that proves an upgrade carries a stated gym across
    /// and leaves a fabricated one behind.
    ///
    /// Nothing in the app calls this. The two columns it fills are retired and
    /// are never written at runtime — but a rule about what is in them cannot
    /// be trusted if the only way to see it work is to install an old build.
    init(retiredEquipmentAccess: String?, hasCompletedSetup: Bool?) {
        self.equipmentAccessRaw = retiredEquipmentAccess
        self.hasCompletedSetup = hasCompletedSetup
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

    // MARK: - Reading what an earlier build recorded

    /// Moves a gym stated under the retired `equipmentAccess` tier into the
    /// equipment he owns, and returns whether anything moved.
    ///
    /// **A stated fact is carried; a fabricated one is not.** The tier column
    /// holds two quite different things depending on which build wrote it. On a
    /// store from the build that still had a setup form, `Equipment.fullGym`
    /// was filled in before the lifter had said anything at all, and
    /// `hasCompletedSetup` is `false` — carrying that across would assert a gym
    /// nobody ever described, which is the one thing this profile must never
    /// do. Anything else in that column is something he or Claude actually
    /// stated, and dropping it silently is the other thing it must never do.
    /// So: carried, unless it is the discarded default on a store whose owner
    /// never finished the form.
    ///
    /// The tier expands into the equipment types it stood for, because that is
    /// what a tier ever meant here — it survives as input shorthand and never
    /// as something stored. Called once by `StoreUpgrade`, which saves; the
    /// column is cleared either way, so it is read once and never again.
    /// A profile that already knows what he owns is left alone.
    func carryForwardRetiredEquipment() -> Bool {
        defer {
            equipmentAccessRaw = nil
            hasCompletedSetup = nil
        }
        guard let stated = equipmentAccessRaw, ownedEquipmentRawValues == nil else { return false }
        guard !(hasCompletedSetup == false && stated == Equipment.fullGym.rawValue) else {
            return false
        }
        guard let tier = Equipment(rawValue: stated) else {
            // Not a tier this build offers, so it is not one to expand. It is
            // still something someone said he has, and it round-trips as an
            // equipment type of its own rather than being dropped.
            ownedEquipment = [EquipmentType(rawValue: stated)]
            return true
        }
        ownedEquipment = EquipmentAccess.permitted(for: tier).sorted { $0.rawValue < $1.rawValue }
        return true
    }
}
