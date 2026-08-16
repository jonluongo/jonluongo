import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Applying what Claude learned to the stored profile.
///
/// This is the only way a training fact enters the app, so what the assertions
/// guard is the merge: an omitted field must survive untouched, an explicit
/// clear must return the fact to not-known rather than to a default, and an
/// update must not be applied twice.
@MainActor
@Suite("Profile updater")
struct ProfileUpdaterTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    /// The real bundled catalog. The one thing an apply checks is that a
    /// baseline names an exercise that exists in it.
    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func update(
        id: UUID = UUID(),
        displayUnit: StatedValue<MassUnit> = .unchanged,
        experience: StatedValue<ExperienceLevel> = .unchanged,
        equipment: StatedValue<[EquipmentType]> = .unchanged,
        goal: StatedValue<String> = .unchanged,
        constraints: StatedValue<String> = .unchanged,
        avoidedPatterns: StatedValue<[MovementPattern]> = .unchanged,
        avoidedExercises: StatedValue<[ExerciseID]> = .unchanged,
        preferredWeekdays: StatedValue<[Weekday]> = .unchanged,
        preferredDurationMinutes: StatedValue<Int> = .unchanged
    ) -> ProfileUpdate {
        ProfileUpdate(
            id: id, generatedAt: Self.instant, displayUnit: displayUnit,
            experience: experience, equipment: equipment, goal: goal,
            constraints: constraints, avoidedPatterns: avoidedPatterns,
            avoidedExercises: avoidedExercises, preferredWeekdays: preferredWeekdays,
            preferredDurationMinutes: preferredDurationMinutes
        )
    }

    private func profiles(in context: ModelContext) throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>())
    }

    // MARK: - What it records

    @Test("Every stated fact is written to the profile exactly as stated")
    func statedFactsAreRecorded() throws {
        let context = try context()
        context.insert(UserProfile())
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(
                displayUnit: .stated(.kilograms), experience: .stated(.beginner),
                equipment: .stated([.dumbbell, .band]), goal: .stated("Get stronger"),
                constraints: .stated("Left shoulder hurts overhead"),
                avoidedPatterns: .stated([.verticalPress]),
                avoidedExercises: .stated([ExerciseID(rawValue: "barbell-upright-row")]),
                preferredWeekdays: .stated([.monday, .thursday]),
                preferredDurationMinutes: .stated(45)),
            to: context, catalog: try catalog())

        #expect(profile.displayUnit == .kilograms)
        #expect(profile.experience == .beginner)
        #expect(profile.ownedEquipment.map(Set.init) == [.dumbbell, .band])
        #expect(profile.goal == "Get stronger")
        #expect(profile.constraints == "Left shoulder hurts overhead")
        #expect(profile.avoidedPatterns == [.verticalPress])
        #expect(profile.avoidedExercises == [ExerciseID(rawValue: "barbell-upright-row")])
        #expect(profile.preferredWeekdays == [.monday, .thursday])
        #expect(profile.preferredDurationMinutes == 45)
    }

    @Test("An update that arrives before the first launch made a profile still lands")
    func updateWithNoProfileYetCreatesOne() throws {
        let context = try context()

        let profile = try ProfileUpdater.apply(
            update(equipment: .stated([.barbell, .cable])), to: context, catalog: try catalog())

        #expect(try profiles(in: context).count == 1)
        #expect(profile.ownedEquipment.map(Set.init) == [.barbell, .cable])
    }

    @Test("The change is saved, not merely made in memory")
    func theChangeIsSaved() throws {
        let context = try context()
        try ProfileUpdater.apply(
            update(goal: .stated("Bigger bench")), to: context, catalog: try catalog())

        // Refetched rather than read back off the returned object.
        #expect(try profiles(in: context).first?.goal == "Bigger bench")
        #expect(!context.hasChanges)
    }

    // MARK: - Merging

    @Test("A fact the update says nothing about is left exactly as it was")
    func omittedFactsSurvive() throws {
        let context = try context()
        context.insert(UserProfile(
            experience: .advanced, ownedEquipment: [.barbell, .cable], goal: "Get stronger",
            preferredWeekdays: [.monday]))
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(equipment: .stated([.dumbbell])), to: context, catalog: try catalog())

        #expect(profile.ownedEquipment.map(Set.init) == [.dumbbell])
        #expect(profile.experience == .advanced)
        #expect(profile.goal == "Get stronger")
        #expect(profile.preferredWeekdays == [.monday])
    }

    @Test("A fact the update takes back returns to not-known, not to a default")
    func clearedFactsBecomeUnknown() throws {
        // The reason this case exists: a fact recorded in error has to be
        // removable, and 'Full gym' is not a way to say 'nobody has said'.
        let context = try context()
        context.insert(UserProfile(
            experience: .advanced, ownedEquipment: [.barbell, .cable], goal: "Get stronger",
            preferredDurationMinutes: 60))
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(
                experience: .unstated, equipment: .unstated, goal: .unstated,
                preferredDurationMinutes: .unstated),
            to: context, catalog: try catalog())

        #expect(profile.experience == nil)
        #expect(profile.ownedEquipment == nil)
        #expect(profile.permittedEquipment == nil)
        #expect(profile.goal.isEmpty)
        #expect(profile.preferredDurationMinutes == nil)
    }

    @Test("A stated list replaces the stored one rather than adding to it")
    func listsReplaceRatherThanAccumulate() throws {
        // A patch that could only add could never record a shoulder that healed.
        let context = try context()
        context.insert(UserProfile(avoidedPatterns: [.verticalPress, .hinge]))
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(avoidedPatterns: .stated([.hinge])), to: context, catalog: try catalog())

        #expect(profile.avoidedPatterns == [.hinge])
    }

    @Test("An emptied list clears the avoidance rather than leaving it in place")
    func emptyListClearsAnAvoidance() throws {
        let context = try context()
        context.insert(UserProfile(avoidedPatterns: [.verticalPress]))
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(avoidedPatterns: .stated([])), to: context, catalog: try catalog())

        #expect(profile.avoidedPatterns.isEmpty)
    }

    @Test("Taking back the display unit leaves the app able to render a weight")
    func clearedDisplayUnitStaysRenderable() throws {
        // The one field that cannot be absent: there is no such thing as a
        // weight shown in no unit. Not a training opinion — a rendering one.
        let context = try context()
        context.insert(UserProfile(displayUnit: .kilograms))
        try context.saveOrThrow()

        let profile = try ProfileUpdater.apply(
            update(displayUnit: .unstated), to: context, catalog: try catalog())

        #expect(profile.displayUnit == .pounds)
    }

    // MARK: - Applied once

    @Test("The same update applied twice does not undo a change made in between")
    func alreadyAppliedUpdateIsIgnored() throws {
        // An update sits in the shared folder until a newer one replaces it, so
        // it is announced again at every launch.
        let context = try context()
        let identity = UUID()
        try ProfileUpdater.apply(
            update(id: identity, displayUnit: .stated(.pounds)), to: context,
            catalog: try catalog())
        let profile = try #require(try profiles(in: context).first)
        profile.displayUnit = .kilograms
        try context.saveOrThrow()

        try ProfileUpdater.apply(
            update(id: identity, displayUnit: .stated(.pounds)), to: context,
            catalog: try catalog())

        #expect(try profiles(in: context).first?.displayUnit == .kilograms)
        #expect(try profiles(in: context).count == 1)
    }

    @Test("A different update is applied even after an earlier one")
    func laterUpdateStillApplies() throws {
        let context = try context()
        try ProfileUpdater.apply(
            update(goal: .stated("Bigger bench")), to: context, catalog: try catalog())
        try ProfileUpdater.apply(
            update(goal: .stated("Bigger squat")), to: context, catalog: try catalog())

        #expect(try profiles(in: context).first?.goal == "Bigger squat")
    }

    @Test("Applying an update moves the profile's timestamp, so the newest one is found")
    func applyingMovesTheTimestamp() throws {
        let context = try context()
        context.insert(UserProfile())
        try context.saveOrThrow()

        let applied = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = try ProfileUpdater.apply(
            update(goal: .stated("Bigger bench")), to: context, catalog: try catalog(),
            appliedAt: applied)

        #expect(profile.updatedAt == applied)
    }
}
