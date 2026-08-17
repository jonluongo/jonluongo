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
    private func exportedDay() throws -> SnapshotDay {
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
        let snapshot = try SnapshotExporter.export(
            from: context, catalogVersion: 5, generatedAt: Self.instant)
        let plan = try #require(snapshot.plans.first)
        let week = try #require(plan.weeks.first)
        return try #require(week.days.first)
    }

    @Test("Every movement is still one of the day's exercises, in prescribed order")
    func exercisesStayFlatAndOrdered() throws {
        let day = try exportedDay()

        #expect(day.exercises.map(\.exerciseID) == [Self.bench, Self.fly, Self.pushdown])
        #expect(day.exercises.map(\.order) == [0, 1, 2])
    }

    @Test("A grouped exercise reports the group it was performed in, and its place in the round")
    func groupedExercisesReportTheirGroup() throws {
        let exercises = try exportedDay().exercises
        let first = try #require(exercises[1].group)
        let second = try #require(exercises[2].group)

        #expect(first.id == second.id, "both were the same group")
        #expect(first.notation == "A1")
        #expect(second.notation == "A2")
        #expect(first.size == 2)
        #expect(first.restSeconds == 90, "the rest after the round is the group's")
        #expect(second.restSeconds == 90)
    }

    @Test("An exercise performed on its own reports no group")
    func ungroupedExerciseReportsNoGroup() throws {
        let exercises = try exportedDay().exercises

        #expect(exercises[0].group == nil)
        #expect(exercises[0].restSeconds == 180, "its own rest is still its own")
    }

    @Test("A member's own rest is the rest taken after it, which is none but the last")
    func memberRestIsTheRestAfterIt() throws {
        let exercises = try exportedDay().exercises

        #expect(exercises[1].restSeconds == nil)
        #expect(exercises[2].restSeconds == 90)
    }

    @Test("The grouping survives the encoder both clients share")
    func groupingSurvivesTheWire() throws {
        let day = try exportedDay()
        let data = try TrainingSnapshot.makeEncoder().encode(day)
        let decoded = try TrainingSnapshot.makeDecoder().decode(SnapshotDay.self, from: data)

        #expect(decoded.exercises[1].group?.notation == "A1")
        #expect(decoded.exercises[0].group == nil)
    }
}
