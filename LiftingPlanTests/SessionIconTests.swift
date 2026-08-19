import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The mark a session carries, and who chooses it.
///
/// The app owns the set and refuses anything outside it; the coach chooses which
/// one a session gets. That is the same arrangement as the exercise catalog, and
/// it exists for the same reason: a value the app cannot honour must fail
/// loudly, because taking it in and drawing nothing tells the writer his choice
/// landed when it did not.
@Suite("The mark on a session")
struct SessionIconTests {

    private static let instant = Date(timeIntervalSince1970: 1_772_409_600)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func document(icon: SessionIcon?) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Push", icon: icon,
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: 3, repRange: "5")])]
        )
    }

    private func day(after icon: SessionIcon?) throws -> WorkoutDay {
        let context = try context()
        try PlanImporter.import(
            document(icon: icon), into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        let plan = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        let week = try #require(plan.orderedWeeks.first)
        return try #require(week.orderedDays.first)
    }

    // MARK: - What the coach chose

    @Test("A mark the plan chose reaches the session")
    func chosenIconIsStored() throws {
        #expect(try day(after: .intervals).icon == .intervals)
    }

    @Test("A session the plan marked nothing carries nothing")
    func absentIconStaysAbsent() throws {
        // Not a default. The app never picks a mark: a day with none draws none,
        // and the name starts where it always did.
        #expect(try day(after: nil).icon == nil)
    }

    @Test("A mark this build cannot draw fails the import and names itself")
    func unknownIconIsRefusedByName() throws {
        let context = try context()

        #expect(throws: PlanImportError.unknownIcon(SessionIcon(rawValue: "deadlift"))) {
            try PlanImporter.import(
                document(icon: SessionIcon(rawValue: "deadlift")), into: context,
                catalog: try ExerciseCatalog.bundled(), importedAt: Self.instant)
        }
        // Nothing at all was written: a partial import that drops the mark would
        // look like a plan the coach did not write.
        #expect(try context.fetch(FetchDescriptor<TrainingPlan>()).isEmpty)
    }

    // MARK: - What goes back

    @Test("The mark goes back in the snapshot, so a later plan can match it")
    func iconSurvivesTheRoundTrip() throws {
        let context = try context()
        try PlanImporter.import(
            document(icon: .strength), into: context,
            catalog: try ExerciseCatalog.bundled(), importedAt: Self.instant)

        let snapshot = try SnapshotExporter.export(from: context, catalogVersion: 5)
        let day = try #require(snapshot.plans.first?.weeks.first?.days.first)
        #expect(day.icon == .strength)
    }

    // MARK: - The set itself

    @Test("Every mark the app offers is one it can draw")
    func everyOfferedMarkResolves() {
        // The tool schema is built from `all`, so a name offered to the coach
        // that this view had no symbol for would be a promise the app breaks.
        for icon in SessionIcon.all {
            #expect(icon.isKnown)
            #expect(SessionIconView.symbol(for: icon).isEmpty == false)
        }
        #expect(Set(SessionIcon.all.map(\.rawValue)).count == SessionIcon.all.count)
    }

    @Test("A name is read the way it is written, whatever the casing")
    func namesAreCanonicalised() {
        #expect(SessionIcon(rawValue: " Strength ") == .strength)
        #expect(SessionIcon(rawValue: "STRENGTH") == .strength)
        #expect(SessionIcon(rawValue: "deadlift").isKnown == false)
    }
}
