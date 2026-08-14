import Testing
@testable import LiftingPlan

@Suite("Equipment access")
struct EquipmentAccessTests {

    @Test("Bodyweight access permits only bodyweight movements")
    func bodyweightOnly() {
        #expect(EquipmentAccess.permitted(for: .bodyweight) == [.bodyweight])
    }

    @Test("Every tier permits bodyweight, because you can always do a push-up")
    func bodyweightAlwaysAvailable() {
        for tier in Equipment.allCases {
            #expect(EquipmentAccess.permitted(for: tier).contains(.bodyweight),
                    "\(tier) should permit bodyweight")
        }
    }

    @Test("A full gym permits barbell, machine, and cable work")
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

    @Test("A minimal home setup permits bands but not machines")
    func homeMinimal() {
        let permitted = EquipmentAccess.permitted(for: .homeMinimal)
        #expect(permitted.contains(.band))
        #expect(permitted.contains(.dumbbell))
        #expect(!permitted.contains(.machine))
    }

    @Test("Access tiers widen monotonically from bodyweight to full gym")
    func tiersNest() {
        let bodyweight = EquipmentAccess.permitted(for: .bodyweight)
        let home = EquipmentAccess.permitted(for: .homeMinimal)
        let gym = EquipmentAccess.permitted(for: .fullGym)
        #expect(bodyweight.isSubset(of: home))
        #expect(home.isSubset(of: gym))
    }

    @Test("Every permitted type is one the catalog actually uses")
    func permittedTypesAreReal() throws {
        let catalog = try ExerciseCatalog.bundled()
        let inCatalog = Set(catalog.all.map(\.equipment))
        for tier in Equipment.allCases {
            for type in EquipmentAccess.permitted(for: tier) {
                #expect(inCatalog.contains(type),
                        "\(tier) permits \(type), which no catalog exercise uses")
            }
        }
    }

    /// `.pool` is a deliberate gap, not an oversight: no access tier answers
    /// "does the lifter have pool access", so swim exercises tagged `.pool`
    /// cannot be prescribed by any tier today. This locks that decision in
    /// so a future change to `EquipmentAccess` either keeps it intentional
    /// or updates this test alongside adding real pool-access support —
    /// never silently.
    @Test("No access tier grants pool access yet")
    func poolIsNotYetReachableByAnyTier() {
        for tier in Equipment.allCases {
            #expect(!EquipmentAccess.permitted(for: tier).contains(.pool),
                    "\(tier) unexpectedly permits .pool")
        }
    }
}
