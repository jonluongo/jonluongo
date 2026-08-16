import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What happens to a profile written by an earlier build the first time this
/// one opens it.
///
/// The lightweight migration keeps every column — that was verified by
/// reconstructing an old store on disk and reopening it, not by reading the
/// code — but a renamed column is left stranded, and this is what reads it
/// across. The line these draw is the one that matters: a gym the lifter
/// stated is carried, and the `Equipment.fullGym` a removed setup form filled
/// in for him before he had said anything is not.
@Suite("Upgrading a store an older build wrote")
struct StoreUpgradeTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// A profile as an older build left it, in a fresh store.
    private func upgraded(
        tier: String?, setupCompleted: Bool?
    ) throws -> (UserProfile, Bool) {
        let context = try context()
        let profile = UserProfile(
            retiredEquipmentAccess: tier, hasCompletedSetup: setupCompleted)
        context.insert(profile)
        try context.save()
        let carried = try StoreUpgrade.run(in: context)
        return (profile, carried)
    }

    // MARK: - A stated gym is carried across

    @Test("A gym stated after the setup form was removed is carried across")
    func statedGymIsCarried() throws {
        let (profile, carried) = try upgraded(
            tier: Equipment.homeMinimal.rawValue, setupCompleted: nil)

        #expect(carried)
        #expect(profile.ownedEquipment != nil, "he said what he had; it must not be lost")
        #expect(profile.permittedEquipment == EquipmentAccess.permitted(for: .homeMinimal))
    }

    @Test("A gym stated in the setup form is carried across")
    func gymFromCompletedSetupIsCarried() throws {
        let (profile, carried) = try upgraded(
            tier: Equipment.fullGym.rawValue, setupCompleted: true)

        #expect(carried)
        #expect(profile.permittedEquipment == EquipmentAccess.permitted(for: .fullGym))
    }

    @Test("A tier this build has never heard of is carried as what it says, not dropped")
    func unknownTierIsCarried() throws {
        let (profile, carried) = try upgraded(tier: "garage rack and bands", setupCompleted: true)

        #expect(carried)
        #expect(profile.ownedEquipment == [EquipmentType(rawValue: "garage rack and bands")])
    }

    // MARK: - A fabricated one is not

    @Test("The default a removed setup form filled in is not carried across")
    func unstatedDefaultIsNotCarried() throws {
        let (profile, carried) = try upgraded(
            tier: Equipment.fullGym.rawValue, setupCompleted: false)

        #expect(!carried)
        #expect(
            profile.ownedEquipment == nil,
            "nobody ever said this; not known must not become a full gym")
        #expect(profile.permittedEquipment == nil)
    }

    @Test("A profile that stated nothing at all still states nothing")
    func nothingStatedStaysUnknown() throws {
        let (profile, carried) = try upgraded(tier: nil, setupCompleted: nil)

        #expect(!carried)
        #expect(profile.ownedEquipment == nil)
    }

    // MARK: - It runs once, and only where there is nothing already

    @Test("A profile that already knows what he owns is left exactly as it is")
    func currentProfileIsUntouched() throws {
        let context = try context()
        let profile = UserProfile(ownedEquipment: [.barbell, .band])
        context.insert(profile)
        try context.save()

        #expect(try !StoreUpgrade.run(in: context))
        #expect(profile.ownedEquipment == [.barbell, .band])
    }

    @Test("Running the upgrade a second time changes nothing")
    func upgradeIsIdempotent() throws {
        let context = try context()
        let profile = UserProfile(
            retiredEquipmentAccess: Equipment.homeMinimal.rawValue, hasCompletedSetup: nil)
        context.insert(profile)
        try context.save()

        #expect(try StoreUpgrade.run(in: context))
        let carriedEquipment = profile.ownedEquipment
        #expect(try !StoreUpgrade.run(in: context), "the column was read once and cleared")
        #expect(profile.ownedEquipment == carriedEquipment)
    }

    @Test("Nothing else about the profile is disturbed")
    func nothingElseChanges() throws {
        let context = try context()
        let profile = UserProfile(
            retiredEquipmentAccess: Equipment.fullGym.rawValue, hasCompletedSetup: true)
        profile.goal = "get strong"
        profile.constraints = "left shoulder"
        profile.bodyweight = Mass(value: 182, unit: .pounds)
        context.insert(profile)
        try context.save()

        _ = try StoreUpgrade.run(in: context)

        #expect(profile.goal == "get strong")
        #expect(profile.constraints == "left shoulder")
        #expect(profile.bodyweight == Mass(value: 182, unit: .pounds))
    }

    @Test("A store with nothing in it upgrades quietly")
    func emptyStoreIsFine() throws {
        #expect(try !StoreUpgrade.run(in: try context()))
    }
}
