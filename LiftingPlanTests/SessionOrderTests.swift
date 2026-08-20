import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// The order a session is actually trained in, and what is next.
///
/// The rest sheet shows one row at a time, so this is the answer it stands on:
/// get the order wrong and a lifter mid-superset is handed the wrong movement.
@Suite("The order a session is trained in")
@MainActor
struct SessionOrderTests {

    private static let bench = ExerciseID(rawValue: "barbell-bench-press")
    private static let row = ExerciseID(rawValue: "barbell-bent-over-row")
    private static let curl = ExerciseID(rawValue: "dumbbell-curl")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    private func exercise(
        _ id: ExerciseID, order: Int, sets: Int, warmups: Int = 0,
        groupID: UUID? = nil, position: Int? = nil
    ) -> PlannedExercise {
        let exercise = PlannedExercise(
            exerciseID: id, displayName: id.rawValue, order: order, targetSets: sets)
        exercise.groupID = groupID
        exercise.groupPosition = position
        exercise.loggedSets = (0..<(sets + warmups)).map {
            LoggedSet(setIndex: $0, reps: 5, isWarmup: $0 < warmups)
        }
        return exercise
    }

    private func day(_ exercises: [PlannedExercise]) throws -> WorkoutDay {
        let context = try context()
        let plan = TrainingPlan(title: "Block")
        let week = TrainingWeek(ordinal: 1)
        let day = WorkoutDay(weekday: .monday)
        day.exercises = exercises
        week.days = [day]
        plan.weeks = [week]
        context.insert(plan)
        try context.saveOrThrow()
        return day
    }

    @Test("An exercise on its own is trained down its rows")
    func plainExerciseRunsDownItsRows() throws {
        let day = try day([exercise(Self.bench, order: 0, sets: 3)])

        #expect(SessionOrder.trainingOrder(of: day).map(\.set.setIndex) == [0, 1, 2])
    }

    @Test("A warm-up comes before the working sets of the movement it warms up")
    func warmupsComeFirst() throws {
        let day = try day([exercise(Self.bench, order: 0, sets: 2, warmups: 1)])
        let order = SessionOrder.trainingOrder(of: day)

        #expect(order.map(\.set.isWarmup) == [true, false, false])
        #expect(order.map(\.identity.badge) == ["W", "1", "2"])
    }

    @Test("A superset is trained across its movements, round by round")
    func groupRunsAcrossItsMovements() throws {
        // The whole reason this exists: drawn down the panels, trained across
        // them. A lifter handed the second fly instead of the first pushdown is
        // being told to do the wrong movement.
        let group = UUID()
        let day = try day([
            exercise(Self.row, order: 0, sets: 2, groupID: group, position: 0),
            exercise(Self.curl, order: 1, sets: 2, groupID: group, position: 1),
        ])

        #expect(SessionOrder.trainingOrder(of: day).map(\.exercise.exerciseID)
            == [Self.row, Self.curl, Self.row, Self.curl])
    }

    @Test("A movement prescribed more rounds than its partner keeps its later rows")
    func unevenGroupKeepsEveryRow() throws {
        // Rounds of one, which is what he is actually doing by then.
        let group = UUID()
        let day = try day([
            exercise(Self.row, order: 0, sets: 3, groupID: group, position: 0),
            exercise(Self.curl, order: 1, sets: 1, groupID: group, position: 1),
        ])

        #expect(SessionOrder.trainingOrder(of: day).map(\.exercise.exerciseID)
            == [Self.row, Self.curl, Self.row, Self.row])
    }

    @Test("A group's warm-ups belong to their movement, not to a round")
    func groupWarmupsStayWithTheirMovement() throws {
        // Nobody warms up between rounds.
        let group = UUID()
        let day = try day([
            exercise(Self.row, order: 0, sets: 1, warmups: 1, groupID: group, position: 0),
            exercise(Self.curl, order: 1, sets: 1, groupID: group, position: 1),
        ])
        let order = SessionOrder.trainingOrder(of: day)

        #expect(order.map(\.set.isWarmup) == [true, false, false])
        #expect(order.first?.exercise.exerciseID == Self.row)
    }

    @Test("What is next is the first row nobody ticked, in training order")
    func nextIsTheFirstUnticked() throws {
        let day = try day([exercise(Self.bench, order: 0, sets: 3)])
        let order = SessionOrder.trainingOrder(of: day)
        order[0].set.isCompleted = true

        #expect(SessionOrder.next(in: day)?.set.setIndex == 1)
    }

    @Test("A row he skipped is what is next when he comes back to it")
    func nextIsByOrderRatherThanByTime() throws {
        // By the order the work is done in rather than by when it was ticked: a
        // lifter who skipped a row and came back is looking at the row he
        // skipped.
        let day = try day([exercise(Self.bench, order: 0, sets: 3)])
        let order = SessionOrder.trainingOrder(of: day)
        order[1].set.isCompleted = true
        order[2].set.isCompleted = true

        #expect(SessionOrder.next(in: day)?.set.setIndex == 0)
    }

    @Test("A session with every row ticked has nothing next")
    func filledSessionHasNothingNext() throws {
        let day = try day([exercise(Self.bench, order: 0, sets: 2)])
        for slot in SessionOrder.trainingOrder(of: day) { slot.set.isCompleted = true }

        #expect(SessionOrder.next(in: day) == nil)
    }
}
