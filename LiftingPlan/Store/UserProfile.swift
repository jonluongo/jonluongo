import Foundation
import SwiftData
import LiftingKit

/// Who the lifter is: the standing facts he has stated about himself, his
/// equipment, and when he wants to train.
///
/// This is a record of what he said, not a set of conclusions drawn from it —
/// what to do with these facts is decided elsewhere. Read it to answer
/// questions about the lifter.
///
/// Exactly one instance is expected. CloudKit forbids unique constraints, so
/// that invariant is enforced in application code rather than by the schema.
/// `displayUnit` controls what new entries default to and how weights are
/// shown; it never rewrites what was already logged. `avoidedPatterns` and
/// `avoidedExercises` make the free-text `constraints` field enforceable
/// rather than merely advisory: `constraints` still carries nuance ("my left
/// shoulder hurts overhead") that a list cannot express, but the structured
/// lists are what `permits(...)` can actually filter the catalog on.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Mass` and `ExerciseID`, `MovementPattern` from Domain.
@Model
final class UserProfile {
    private var displayUnitRaw: String = MassUnit.pounds.rawValue
    private var experienceRaw: String = ExperienceLevel.intermediate.rawValue
    private var equipmentAccessRaw: String = Equipment.fullGym.rawValue
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
    var hasCompletedSetup: Bool = false
    var updatedAt: Date = Date()

    init(
        displayUnit: MassUnit = .pounds,
        experience: ExperienceLevel = .intermediate,
        equipmentAccess: Equipment = .fullGym,
        goal: String = "", constraints: String = "", bodyweight: Mass? = nil,
        avoidedPatterns: Set<MovementPattern> = [], avoidedExercises: Set<ExerciseID> = [],
        preferredWeekdays: Set<Weekday> = [], preferredDurationMinutes: Int? = nil,
        hasCompletedSetup: Bool = false
    ) {
        self.displayUnitRaw = displayUnit.rawValue
        self.experienceRaw = experience.rawValue
        self.equipmentAccessRaw = equipmentAccess.rawValue
        self.goal = goal
        self.constraints = constraints
        self.bodyweight = bodyweight
        self.avoidedPatternRawValues = avoidedPatterns.map(\.rawValue).sorted()
        self.avoidedExerciseRawValues = avoidedExercises.map(\.rawValue).sorted()
        self.preferredWeekdayRawValues = preferredWeekdays.map(\.rawValue).sorted()
        self.preferredDurationMinutes = preferredDurationMinutes
        self.hasCompletedSetup = hasCompletedSetup
        self.updatedAt = Date()
    }

    var displayUnit: MassUnit {
        get { MassUnit(rawValue: displayUnitRaw) ?? .pounds }
        set { displayUnitRaw = newValue.rawValue }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .intermediate }
        set { experienceRaw = newValue.rawValue }
    }

    var equipmentAccess: Equipment {
        get { Equipment(rawValue: equipmentAccessRaw) ?? .fullGym }
        set { equipmentAccessRaw = newValue.rawValue }
    }

    /// The equipment types this lifter can actually train with.
    var permittedEquipment: Set<EquipmentType> {
        EquipmentAccess.permitted(for: equipmentAccess)
    }

    /// Movement patterns excluded from plan generation, e.g. for an injury.
    var avoidedPatterns: Set<MovementPattern> {
        get { Set(avoidedPatternRawValues.map(MovementPattern.init(rawValue:))) }
        set { avoidedPatternRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Specific exercises excluded from plan generation, e.g. a substitution
    /// the lifter has already ruled out.
    var avoidedExercises: Set<ExerciseID> {
        get { Set(avoidedExerciseRawValues.map(ExerciseID.init(rawValue:))) }
        set { avoidedExerciseRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// The days the lifter wants to train, as stated in setup. This is his
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

    /// Whether this lifter's constraints allow the movement pattern.
    func permits(pattern: MovementPattern) -> Bool { !avoidedPatterns.contains(pattern) }

    /// Whether this lifter's constraints allow the specific exercise.
    func permits(exercise id: ExerciseID) -> Bool { !avoidedExercises.contains(id) }
}
