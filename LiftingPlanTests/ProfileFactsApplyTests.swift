import Testing
import SwiftData
import Foundation
import LiftingKit

@testable import LiftingPlan

/// Recording what the lifter weighs and what he can already lift.
///
/// Nothing in the app or either document could write these before, so Claude was
/// permanently told the lifter had no bodyweight and no strength anchor — and a
/// first block for any lift had nothing to set a load against. What the
/// assertions guard is that the series stays a series: a second weigh-in on a
/// new day must not replace the first, and a restatement of a day must.
@MainActor
@Suite("Recording bodyweight and baselines")
struct ProfileFactsApplyTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let aWeekEarlier = instant.addingTimeInterval(-7 * 24 * 60 * 60)

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func catalog() throws -> ExerciseCatalog {
        try ExerciseCatalog.bundled()
    }

    private func update(
        bodyweight: [BodyweightReading] = [],
        baselines: [BaselineStatement] = [],
        equipment: StatedValue<[EquipmentType]> = .unchanged
    ) -> ProfileUpdate {
        ProfileUpdate(
            id: UUID(), generatedAt: Self.instant, equipment: equipment,
            bodyweight: bodyweight, baselines: baselines
        )
    }

    private func metrics(in context: ModelContext) throws -> [BodyMetric] {
        try context.fetch(
            FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date)]))
    }

    private func baselines(in context: ModelContext) throws -> [StrengthBaseline] {
        try context.fetch(FetchDescriptor<StrengthBaseline>())
    }

    private let bench = ExerciseID(rawValue: "barbell-bench-press")

    // MARK: - Bodyweight reaches the store, and the snapshot

    @Test("A bodyweight recorded through an update reaches the snapshot")
    func bodyweightReachesTheSnapshot() throws {
        // The exact path that used to drop it on the floor.
        let context = try context()

        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(date: Self.instant, mass: Mass(value: 182, unit: .pounds))
            ]),
            to: context, catalog: try catalog())
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(snapshot.bodyMetrics.count == 1)
        #expect(snapshot.bodyMetrics.first?.bodyweight == Mass(value: 182, unit: .pounds))
        #expect(snapshot.profile?.bodyweight == Mass(value: 182, unit: .pounds))
    }

    @Test("Two readings on different days both survive, because a trend needs both")
    func twoDaysAreASeries() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(
                    date: Self.aWeekEarlier, mass: Mass(value: 178, unit: .pounds))
            ]),
            to: context, catalog: try catalog())
        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(date: Self.instant, mass: Mass(value: 182, unit: .pounds))
            ]),
            to: context, catalog: try catalog())

        #expect(try metrics(in: context).map(\.bodyweight?.value) == [178, 182])
    }

    @Test("A reading restated for a day it already has corrects that day rather than doubling it")
    func sameDayIsACorrection() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(date: Self.instant, mass: Mass(value: 172, unit: .pounds))
            ]),
            to: context, catalog: try catalog())
        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(
                    date: Self.instant.addingTimeInterval(3600),
                    mass: Mass(value: 182, unit: .pounds))
            ]),
            to: context, catalog: try catalog())

        #expect(try metrics(in: context).count == 1, "a lifter has one bodyweight on a day")
        #expect(try metrics(in: context).first?.bodyweight?.value == 182)
    }

    @Test("A reading that named no day is filed under the day the update was written")
    func undatedReadingUsesTheDocumentDate() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(date: nil, mass: Mass(value: 182, unit: .pounds))
            ]),
            to: context, catalog: try catalog())

        #expect(try metrics(in: context).first?.date == Self.instant)
    }

    @Test("An update that says nothing about his weight leaves the series alone")
    func silenceLeavesTheSeries() throws {
        let context = try context()
        try ProfileUpdater.apply(
            update(bodyweight: [
                BodyweightReading(date: Self.instant, mass: Mass(value: 182, unit: .pounds))
            ]),
            to: context, catalog: try catalog())

        try ProfileUpdater.apply(
            update(equipment: .stated([.barbell])), to: context, catalog: try catalog())

        #expect(try metrics(in: context).count == 1)
    }

    // MARK: - Baselines

    @Test("A stated baseline reaches the snapshot, so a first block has a load anchor")
    func baselineReachesTheSnapshot() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(baselines: [
                BaselineStatement(
                    exerciseID: bench, load: Mass(value: 205, unit: .pounds), reps: 5,
                    recordedAt: Self.aWeekEarlier)
            ]),
            to: context, catalog: try catalog())
        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)

        #expect(snapshot.baselines.count == 1)
        #expect(snapshot.baselines.first?.exerciseID == bench)
        #expect(snapshot.baselines.first?.load == Mass(value: 205, unit: .pounds))
        #expect(snapshot.baselines.first?.reps == 5)
        #expect(snapshot.baselines.first?.recordedAt == Self.aWeekEarlier)
    }

    @Test("A second baseline for the same lift replaces it, since a lift has one starting point")
    func baselineReplacesItsLift() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(baselines: [
                BaselineStatement(exerciseID: bench, load: nil, reps: 5, recordedAt: nil)
            ]),
            to: context, catalog: try catalog())
        try ProfileUpdater.apply(
            update(baselines: [
                BaselineStatement(
                    exerciseID: bench, load: Mass(value: 225, unit: .pounds), reps: 3,
                    recordedAt: nil)
            ]),
            to: context, catalog: try catalog())

        #expect(try baselines(in: context).count == 1)
        #expect(try baselines(in: context).first?.reps == 3)
    }

    @Test("A baseline naming an exercise the catalog does not have is refused, and nothing lands")
    func unknownBaselineExerciseIsRefused() throws {
        // History is keyed on exercise identity, so an invented ID would anchor
        // a series nothing else will ever join — the rule PlanImporter applies.
        let context = try context()

        #expect(throws: ProfileUpdateError.unknownExercise(ExerciseID(rawValue: "moon-press"))) {
            try ProfileUpdater.apply(
                update(
                    bodyweight: [
                        BodyweightReading(
                            date: Self.instant, mass: Mass(value: 182, unit: .pounds))
                    ],
                    baselines: [
                        BaselineStatement(
                            exerciseID: ExerciseID(rawValue: "moon-press"), load: nil, reps: 5,
                            recordedAt: nil)
                    ]),
                to: context, catalog: try self.catalog())
        }
        #expect(try baselines(in: context).isEmpty)
        #expect(try metrics(in: context).isEmpty, "a refused update writes nothing at all")
    }

    // MARK: - The gym he actually has

    @Test("What he owns is what the snapshot says he can train with")
    func ownedEquipmentReachesTheSnapshot() throws {
        let context = try context()

        try ProfileUpdater.apply(
            update(equipment: .stated([.barbell, .band])), to: context, catalog: try catalog())
        let available = try #require(
            try SnapshotExporter.export(from: context, catalogVersion: 5)
                .profile?.availableEquipment)

        #expect(Set(available) == [.barbell, .band, .bodyweight])
        #expect(!available.contains(.cable))
    }

    @Test("A lifter who has stated nothing reports unknown, not a full gym and not nothing at all")
    func unstatedEquipmentIsUnknown() throws {
        let context = try context()
        try ProfileUpdater.apply(
            update(equipment: .stated([.barbell])), to: context, catalog: try catalog())

        try ProfileUpdater.apply(
            update(equipment: .unstated), to: context, catalog: try catalog())

        #expect(
            try SnapshotExporter.export(from: context, catalogVersion: 5)
                .profile?.availableEquipment == nil)
    }

    @Test("An equipment type this build has never heard of is stored and reported intact")
    func unknownEquipmentSurvivesTheStore() throws {
        let context = try context()
        let unknown = EquipmentType(rawValue: "reverse hyper")

        try ProfileUpdater.apply(
            update(equipment: .stated([unknown])), to: context, catalog: try catalog())

        #expect(
            try SnapshotExporter.export(from: context, catalogVersion: 5)
                .profile?.availableEquipment?.contains(unknown) == true)
    }
}
