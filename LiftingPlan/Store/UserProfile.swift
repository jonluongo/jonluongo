import Foundation
import SwiftData

/// Who the lifter is: the standing facts that shape every generated plan.
///
/// Exactly one instance is expected. CloudKit forbids unique constraints, so
/// that invariant is enforced in application code rather than by the schema.
/// `displayUnit` controls what new entries default to and how weights are
/// shown; it never rewrites what was already logged.
///
/// Every property has a default, as CloudKit requires.
@Model
final class UserProfile {
    private var displayUnitRaw: String = MassUnit.pounds.rawValue
    private var experienceRaw: String = ExperienceLevel.intermediate.rawValue
    private var equipmentAccessRaw: String = Equipment.fullGym.rawValue
    var goal: String = ""
    /// Injuries and constraints, in the lifter's own words. Fed to the model.
    var constraints: String = ""
    var hasCompletedSetup: Bool = false
    var updatedAt: Date = Date()

    init(
        displayUnit: MassUnit = .pounds,
        experience: ExperienceLevel = .intermediate,
        equipmentAccess: Equipment = .fullGym,
        goal: String = "", constraints: String = "", hasCompletedSetup: Bool = false
    ) {
        self.displayUnitRaw = displayUnit.rawValue
        self.experienceRaw = experience.rawValue
        self.equipmentAccessRaw = equipmentAccess.rawValue
        self.goal = goal
        self.constraints = constraints
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
}
