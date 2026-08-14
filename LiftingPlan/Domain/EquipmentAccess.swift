import Foundation

/// Maps the lifter's stated equipment access onto the concrete
/// `EquipmentType` values a catalog exercise may require.
///
/// The lifter answers a coarse question ("dumbbells only"); the catalog states
/// a precise requirement ("this needs a barbell"). Use this to turn the former
/// into a filter over the latter. Tiers widen monotonically — everything a
/// minimal home setup allows, a full gym allows too — and every tier includes
/// bodyweight, because a push-up needs nothing.
///
/// Depends on: `Equipment` and `EquipmentType`. No persistence, no UI.
enum EquipmentAccess {

    /// The equipment types a lifter at this access tier can actually use.
    static func permitted(for access: Equipment) -> Set<EquipmentType> {
        switch access {
        case .bodyweight:
            bodyweightTier
        case .homeMinimal:
            homeTier
        case .dumbbellsOnly:
            dumbbellTier
        case .fullGym:
            gymTier
        }
    }

    private static let bodyweightTier: Set<EquipmentType> = [.bodyweight]

    private static let dumbbellTier: Set<EquipmentType> =
        bodyweightTier.union([.dumbbell, .plate])

    private static let homeTier: Set<EquipmentType> =
        dumbbellTier.union([.band, .kettlebell, .medicineBall])

    private static let gymTier: Set<EquipmentType> =
        homeTier.union([
            .barbell, .machine, .cable, .ezBar, .trapBar,
            .sled, .cardioMachine, .other,
        ])
}
