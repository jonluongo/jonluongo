import Testing

@testable import LiftingKit

/// What the lifter can train with, given what he owns.
///
/// The assertions that matter are about the open set: a real gym is not a tier,
/// so "barbell and bands but no rack" has to be sayable, and a lifter who has
/// said nothing has to stay unknown rather than becoming a full gym.
@Suite("Equipment access")
struct EquipmentAccessTests {

    // MARK: - What he owns is what he can use

    @Test("What he owns is what he can train with")
    func ownedIsPermitted() {
        let permitted = EquipmentAccess.permitted(owning: [.barbell, .band])

        #expect(permitted.contains(.barbell))
        #expect(permitted.contains(.band))
        #expect(!permitted.contains(.cable))
        #expect(!permitted.contains(.machine))
    }

    @Test("A gym no tier describes is expressible: barbell and bands but no rack")
    func garageGymIsExpressible() {
        // Forced into a tier this lifter is either granted 109 machine and
        // cable movements he cannot do, or denied every barbell one.
        let permitted = EquipmentAccess.permitted(owning: [.barbell, .band, .plate])

        #expect(permitted.isSuperset(of: [.barbell, .band, .plate]))
        #expect(permitted.isDisjoint(with: [.cable, .machine, .sled]))
    }

    @Test("A movement that needs no equipment needs none of his")
    func bodyweightNeedsNothing() {
        #expect(EquipmentAccess.permitted(owning: [.barbell]).contains(.bodyweight))
        #expect(EquipmentAccess.permitted(owning: []) == [.bodyweight])
    }

    @Test("An equipment type this build has never heard of is still something he owns")
    func unknownOwnedTypeIsCarried() {
        let unknown = EquipmentType(rawValue: "reverse hyper")
        #expect(!unknown.isKnown)

        #expect(EquipmentAccess.permitted(owning: [unknown]).contains(unknown))
    }

    // MARK: - Tiers, as shorthand only

    @Test("Bodyweight-only shorthand stands for bodyweight alone")
    func bodyweightTier() {
        #expect(EquipmentAccess.permitted(for: .bodyweight) == [.bodyweight])
    }

    @Test("Every tier stands for bodyweight, because you can always do a push-up")
    func bodyweightAlwaysAvailable() {
        for tier in Equipment.allCases {
            #expect(
                EquipmentAccess.permitted(for: tier).contains(.bodyweight),
                "\(tier) should permit bodyweight")
        }
    }

    @Test("A full gym stands for barbell, machine, and cable work")
    func fullGym() {
        let permitted = EquipmentAccess.permitted(for: .fullGym)
        #expect(permitted.contains(.barbell))
        #expect(permitted.contains(.machine))
        #expect(permitted.contains(.cable))
    }

    @Test("Dumbbells-only excludes barbell, machine, and cable")
    func dumbbellsOnly() {
        let permitted = EquipmentAccess.permitted(for: .dumbbellsOnly)
        #expect(permitted.contains(.dumbbell))
        #expect(!permitted.contains(.barbell))
        #expect(!permitted.contains(.machine))
        #expect(!permitted.contains(.cable))
    }

    @Test("A minimal home setup stands for bands but not machines")
    func homeMinimal() {
        let permitted = EquipmentAccess.permitted(for: .homeMinimal)
        #expect(permitted.contains(.band))
        #expect(permitted.contains(.dumbbell))
        #expect(!permitted.contains(.machine))
    }

    @Test("Shorthand tiers widen monotonically from bodyweight to full gym")
    func tiersNest() {
        let bodyweight = EquipmentAccess.permitted(for: .bodyweight)
        let home = EquipmentAccess.permitted(for: .homeMinimal)
        let gym = EquipmentAccess.permitted(for: .fullGym)
        #expect(bodyweight.isSubset(of: home))
        #expect(home.isSubset(of: gym))
    }

    @Test("Every type a tier stands for is one the catalog actually uses")
    func permittedTypesAreReal() throws {
        let catalog = try ExerciseCatalog.bundled()
        let inCatalog = Set(catalog.all.map(\.equipment))
        for tier in Equipment.allCases {
            for type in EquipmentAccess.permitted(for: tier) {
                #expect(
                    inCatalog.contains(type),
                    "\(tier) permits \(type), which no catalog exercise uses")
            }
        }
    }

    /// `.pool` and `.suspension` belong to no tier, and with an owned set that
    /// is no longer a gap: a lifter who has pool access or a pair of straps says
    /// so directly. What a tier must not do is *assume* either — nothing about
    /// "full gym" says there is a pool in it, and granting swim work to a lifter
    /// with no pool is the equipment mismatch this taxonomy exists to prevent.
    @Test("No shorthand tier assumes a pool or a suspension trainer, but owning one says so")
    func poolAndSuspensionAreOwnedRatherThanAssumed() {
        for tier in Equipment.allCases {
            #expect(!EquipmentAccess.permitted(for: tier).contains(.pool))
            #expect(!EquipmentAccess.permitted(for: tier).contains(.suspension))
        }
        #expect(EquipmentAccess.permitted(owning: [.pool]).contains(.pool))
        #expect(EquipmentAccess.permitted(owning: [.suspension]).contains(.suspension))
    }
}
