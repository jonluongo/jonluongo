import Foundation

/// What a lifter can train with, given what he owns.
///
/// **What it does.** Turns the equipment the lifter has said he has into the set
/// of `EquipmentType` values a catalog exercise may require of him, and expands
/// a coarse tier into that same vocabulary when a caller used one as shorthand.
///
/// **How it is used.** `UserProfile.permittedEquipment` and
/// `SnapshotProfile.availableEquipment` are what this produces, and
/// `list_exercises` and the app filter the catalog on it. A lifter who has not
/// said what he owns has no set at all — the caller holds `nil`, never `[]`,
/// because an empty set claims he can perform nothing, which is a far stronger
/// statement than not knowing.
///
/// **What it depends on.** `Equipment` and `EquipmentType`. No persistence and
/// no UI, and no opinion about training: what stands in a garage is a fact about
/// the garage, not a judgement about what to do in it.
public enum EquipmentAccess {

    /// What a lifter who owns exactly these can train with.
    ///
    /// His own set, and `.bodyweight` besides: a movement that requires no
    /// equipment requires none of his, so a lifter who owns a barbell can still
    /// do a push-up and a lifter who owns nothing at all can still do one. That
    /// follows from what the taxonomy value means rather than from any
    /// assumption about him. An equipment type this build has never heard of is
    /// carried through unchanged — he owns what he says he owns.
    public static func permitted(
        owning owned: some Sequence<EquipmentType>
    ) -> Set<EquipmentType> {
        Set(owned).union(requiringNothing)
    }

    /// The equipment types a coarse tier stands for.
    ///
    /// **Shorthand, and only shorthand.** A tier is a way of saying several
    /// things at once; it is not what is stored and not what anything filters
    /// on, so a lifter whose gym no tier describes — a barbell and bands but no
    /// rack — says what he owns instead of being forced into the nearest tier.
    /// Tiers widen monotonically, and every one of them includes bodyweight.
    public static func permitted(for tier: Equipment) -> Set<EquipmentType> {
        switch tier {
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

    /// What a movement needing no equipment needs. Not a tier and not a claim
    /// about anyone: it is the definition of `.bodyweight`.
    private static let requiringNothing: Set<EquipmentType> = [.bodyweight]

    private static let bodyweightTier: Set<EquipmentType> = requiringNothing

    private static let dumbbellTier: Set<EquipmentType> =
        bodyweightTier.union([.dumbbell, .plate])

    private static let homeTier: Set<EquipmentType> =
        dumbbellTier.union([.band, .kettlebell, .medicineBall])

    private static let gymTier: Set<EquipmentType> =
        homeTier.union([
            .barbell, .machine, .cable, .ezBar, .trapBar,
            .sled, .cardioMachine, .other,
        ])

    // `.pool` and `.suspension` belong to no tier above, and with an owned set
    // that is no longer a gap that costs anyone anything: a lifter with pool
    // access or a pair of straps says so directly, and swim and suspension work
    // becomes available to him and to nobody else. What a tier must not do is
    // *assume* either — nothing about "full gym" says there is a pool in the
    // building, and granting swim work to a lifter with no pool is exactly the
    // equipment mismatch this type exists to prevent.
}
