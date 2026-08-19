import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The colour a block is known by, and who chooses it.
///
/// The same arrangement as the exercise catalog and a session's mark: the app
/// owns the set, the coach picks from it, and a name outside it fails loudly
/// rather than being taken in and drawn as nothing.
@Suite("A block's colour")
struct BlockTintTests {

    private static let instant = Date(timeIntervalSince1970: 1_772_409_600)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func document(tint: BlockTint?) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            title: "Upper Volume", tint: tint,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Push",
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: 3, repRange: "5")])]
        )
    }

    private func plan(after tint: BlockTint?) throws -> TrainingPlan {
        let context = try context()
        try PlanImporter.import(
            document(tint: tint), into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        return try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
    }

    // MARK: - What the coach chose

    @Test("A colour the plan chose reaches the block")
    func chosenTintIsStored() throws {
        #expect(try plan(after: .teal).tint == .teal)
    }

    @Test("A block the plan left uncoloured carries no colour")
    func absentTintStaysAbsent() throws {
        // Not a default, and not the first of the list: a block with no colour
        // draws the ordinary neutral, which is what the list has always drawn.
        #expect(try plan(after: nil).tint == nil)
    }

    @Test("A colour this build cannot draw fails the import and names itself")
    func unknownTintIsRefusedByName() throws {
        let context = try context()

        #expect(throws: PlanImportError.unknownTint(BlockTint(rawValue: "chartreuse"))) {
            try PlanImporter.import(
                document(tint: BlockTint(rawValue: "chartreuse")), into: context,
                catalog: try ExerciseCatalog.bundled(), importedAt: Self.instant)
        }
        #expect(try context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
    }

    // MARK: - What goes back

    @Test("The colour goes back in the snapshot, so the next block can differ")
    func tintSurvivesTheRoundTrip() throws {
        let context = try context()
        try PlanImporter.import(
            document(tint: .rust), into: context,
            catalog: try ExerciseCatalog.bundled(), importedAt: Self.instant)

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        #expect(snapshot.plans.first?.tint == .rust)
    }

    // MARK: - The set itself

    @Test("Every colour the app offers is one it can draw, and they are distinct")
    func everyOfferedColourResolves() {
        for tint in BlockTint.all {
            #expect(tint.isKnown)
        }
        #expect(Set(BlockTint.all.map(\.rawValue)).count == BlockTint.all.count)
        #expect(BlockTint(rawValue: " Teal ") == .teal)
        #expect(BlockTint(rawValue: "chartreuse").isKnown == false)
    }
}
