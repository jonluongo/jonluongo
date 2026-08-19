import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What the snapshot says about a session that was trained in rounds.
///
/// Claude reads back what was actually done, and a superset reported as six
/// unrelated sets loses the fact that they were performed in rounds — the coach
/// cannot judge a session he cannot see the shape of.
@Suite("A superset in the snapshot")
struct SupersetSnapshotTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let fly = ExerciseID(rawValue: "dumbbell-chest-fly")
    private static let pushdown = ExerciseID(rawValue: "cable-rope-pushdown")

    private func exercise(_ id: ExerciseID, restSeconds: Int? = nil) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: id, displayName: id.rawValue, sets: 3, repRange: "12-15",
            restSeconds: restSeconds)
    }

    /// A store holding one ungrouped press and one superset, exported.
    private func exported() throws -> TrainingSnapshot {
        let context = ModelContext(try StoreContainer.inMemory())
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, focus: "Push", entries: [
                .exercise(exercise(Self.bench, restSeconds: 180)),
                .group(PlanDocumentGroup(
                    exercises: [exercise(Self.fly), exercise(Self.pushdown)], restSeconds: 90)),
            ])]
        )
        try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        return try SnapshotExporter.export(
            from: context, catalogVersion: 5, generatedAt: Self.instant)
    }

    @Test("Every movement is still one of the day's exercises, in prescribed order")
    func exercisesStayFlatAndOrdered() throws {
        // Reading the day's entries flat is what a caller counting movements
        // does; the grouping is still stated, one level up.
        #expect(try exported().firstDayExercises.map(\.exerciseID)
            == [Self.bench, Self.fly, Self.pushdown])
    }

    @Test("The superset comes back as a group, not as a marker on each member")
    func groupSurvivesAsAGroup() throws {
        let day = try #require(try exported().firstDay)

        #expect(day.entries.count == 2, "one exercise and one group, not three exercises")
        let group = try #require(day.entries[1].group)
        #expect(group.exercises.map(\.exerciseID) == [Self.fly, Self.pushdown])
        #expect(group.restSeconds == 90, "the rest after the round is the group's")
    }

    @Test("An exercise performed on its own keeps its own rest and is not a group")
    func ungroupedExerciseIsNotAGroup() throws {
        let day = try #require(try exported().firstDay)

        #expect(day.entries[0].group == nil)
        #expect(day.entries[0].exercises[0].restSeconds == 180)
    }

    @Test("No member states a rest of its own: a rest inside a group is one nobody takes")
    func membersStateNoRest() throws {
        let group = try #require(try exported().firstDay?.entries[1].group)

        #expect(group.exercises.allSatisfy { $0.restSeconds == nil })
    }

    @Test("The grouping survives the encoder both clients share")
    func groupingSurvivesTheWire() throws {
        let snapshot = try exported()
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)

        #expect(decoded.firstDay?.entries[1].group?.exercises.count == 2)
        #expect(decoded.firstDay?.entries[0].group == nil)
    }
}
