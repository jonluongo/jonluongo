import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// Whose clock the rest sheet is editing, and what a choice made on it is
/// filed under.
///
/// **The key is the load-bearing part.** A lifter's own rest length is kept per
/// exercise, so the key this carries decides which exercise his choice attaches
/// to. Get it wrong for a group and he sets the rest on a superset and finds it
/// on a movement he never touched — silently, because both look like a rest
/// length in the same sheet.
///
/// The type had no tests, and the rule is stated only in a doc comment: a
/// group's rest is the one after its *last* movement, because that is where the
/// rest is actually taken.
@Suite("Whose rest is being edited")
struct RestTargetTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let press = ExerciseID(rawValue: "dumbbell-seated-overhead-press")
    private static let pushdown = ExerciseID(rawValue: "cable-rope-pushdown")

    /// A day holding one group of two, imported the way a plan arrives.
    private func groupedDay() throws -> WorkoutDay {
        let context = ModelContext(try StoreContainer.inMemory())
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant, title: "Block",
            days: [
                PlanDocumentDay(
                    weekday: .monday, focus: "Push",
                    entries: [
                        .exercise(
                            PlanDocumentExercise(
                                exerciseID: Self.bench, displayName: "Bench", sets: 3,
                                repRange: "5", restSeconds: 180)),
                        .group(
                            PlanDocumentGroup(
                                exercises: [
                                    PlanDocumentExercise(
                                        exerciseID: Self.press, displayName: "Press",
                                        sets: 3, repRange: "8-10"),
                                    PlanDocumentExercise(
                                        exerciseID: Self.pushdown, displayName: "Pushdown",
                                        sets: 3, repRange: "12-15"),
                                ],
                                restSeconds: 90)),
                    ])
            ])
        let plan = try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled())
        let week = try #require(plan.orderedWeeks.first)
        return try #require(week.orderedDays.first)
    }

    private func group(in day: WorkoutDay) throws -> ExerciseGroup {
        let entry = try #require(
            SessionGrouping.entries(of: day.orderedExercises).first { entry in
                if case .group = entry { return true }
                return false
            })
        guard case .group(let group) = entry else { throw RestTargetTestFailure() }
        return group
    }

    // MARK: - A group's rest belongs to the movement it ends with

    @Test("A group's choice is filed under the movement its round ends with")
    func aGroupIsKeyedOnItsLastMovement() throws {
        let day = try groupedDay()
        let target = try #require(RestTarget(group: try group(in: day)))

        // The rest is taken after the pushdown, not after the press, so that is
        // the exercise a choice about this group is recorded against. Keyed on
        // the first, the lifter's 2 minutes would attach to a movement nothing
        // is rested after.
        #expect(target.key == Self.pushdown)
        #expect(target.prescribedSeconds == 90)
    }

    @Test("An exercise on its own is keyed and timed as itself")
    func anExerciseIsKeyedOnItself() throws {
        let day = try groupedDay()
        let bench = try #require(
            day.orderedExercises.first { $0.exerciseID == Self.bench })
        let target = RestTarget(exercise: bench)

        #expect(target.key == Self.bench)
        #expect(target.prescribedSeconds == 180)
        #expect(target.name == "Bench")
    }

    // MARK: - Two sheets, never one identity

    @Test("A group and an exercise inside it are never the same sheet")
    func identitiesDoNotCollide() throws {
        let day = try groupedDay()
        let group = try group(in: day)
        let last = try #require(group.members.last)

        // They share a key on purpose — the group's rest *is* that exercise's —
        // so only the identity keeps the two sheets apart. Presented by `item:`,
        // one identity would mean opening one and being shown the other.
        #expect(RestTarget(exercise: last).key == RestTarget(group: group)?.key)
        #expect(RestTarget(exercise: last).id != RestTarget(group: group)?.id)
    }

    @Test("Every exercise in a day has an identity of its own")
    func everyExerciseIsDistinct() throws {
        let day = try groupedDay()
        let identities = day.orderedExercises.map { RestTarget(exercise: $0).id }

        #expect(Set(identities).count == identities.count)
    }
}

private struct RestTargetTestFailure: Error {}
