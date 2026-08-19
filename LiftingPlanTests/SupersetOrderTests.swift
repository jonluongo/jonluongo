import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What to do next inside a group.
///
/// A superset is trained across its movements and drawn down them — each gets
/// its own panel — so the order the work happens in runs across the panels while
/// the order it is written in runs down them. This is the question that closes
/// that gap, and it answers it from the grouping the plan already prescribed
/// rather than from any opinion about how to train.
@Suite("The next set of a group")
struct SupersetOrderTests {

    private static let fly = ExerciseID(rawValue: "cable-bench-chest-fly")
    private static let pushdown = ExerciseID(rawValue: "cable-rope-pushdown")
    private static let curl = ExerciseID(rawValue: "barbell-curl")

    /// A stored group whose members have `sets` working rows each, none ticked.
    private func group(
        sets: [Int] = [3, 3],
        ids: [ExerciseID] = [SupersetOrderTests.fly, SupersetOrderTests.pushdown]
    ) throws -> ExerciseGroup {
        let context = ModelContext(try StoreContainer.inMemory())
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        let identity = UUID()
        day.exercises = zip(ids, sets).enumerated().map { position, pair in
            let exercise = PlannedExercise(
                exerciseID: pair.0, displayName: pair.0.rawValue,
                order: position, targetSets: pair.1, repRange: "12-15")
            exercise.groupID = identity
            exercise.groupPosition = position
            exercise.loggedSets = (0..<pair.1).map {
                LoggedSet(setIndex: $0, reps: 0, isWarmup: false)
            }
            return exercise
        }
        context.insert(day)
        guard case .group(let group)? = day.entries.first else {
            Issue.record("the day holds one group")
            throw CancellationError()
        }
        return group
    }

    private func working(_ member: PlannedExercise) -> [LoggedSet] {
        (member.loggedSets ?? []).filter { !$0.isWarmup }.sorted { $0.setIndex < $1.setIndex }
    }

    // MARK: - Across, then down

    @Test("After the first movement's set comes the second movement's, same position")
    func acrossTheRoundFirst() throws {
        let group = try group()
        let first = working(group.members[0])[0]
        first.isCompleted = true

        #expect(group.setAfter(first, of: group.members[0]) === working(group.members[1])[0])
    }

    @Test("After the last movement of a round comes the first movement's next set")
    func downToTheNextRound() throws {
        let group = try group()
        let closing = working(group.members[1])[0]
        for member in group.members { working(member)[0].isCompleted = true }

        #expect(group.setAfter(closing, of: group.members[1]) === working(group.members[0])[1])
    }

    @Test("A tri-set runs A then B then C before it comes back to A")
    func triSetRunsAcrossAllThree() throws {
        let group = try group(sets: [2, 2, 2], ids: [Self.fly, Self.pushdown, Self.curl])
        let first = working(group.members[0])[0]
        first.isCompleted = true

        let second = try #require(group.setAfter(first, of: group.members[0]))
        #expect(second === working(group.members[1])[0])
        second.isCompleted = true
        #expect(group.setAfter(second, of: group.members[1]) === working(group.members[2])[0])
    }

    // MARK: - What it declines to answer

    @Test("A set already ticked is skipped rather than offered again")
    func ticketSetsAreNotOffered() throws {
        let group = try group()
        let first = working(group.members[0])[0]
        working(group.members[1])[0].isCompleted = true
        first.isCompleted = true

        // The partner's first set is done, so the next thing is the second round.
        #expect(group.setAfter(first, of: group.members[0]) === working(group.members[0])[1])
    }

    @Test("A group with everything ticked offers nothing")
    func finishedGroupOffersNothing() throws {
        let group = try group()
        for member in group.members {
            for set in working(member) { set.isCompleted = true }
        }
        let last = working(group.members[1])[2]

        #expect(group.setAfter(last, of: group.members[1]) == nil)
    }

    @Test("A movement prescribed fewer sets is not invented one")
    func unevenGroupIsNotPaddedOut() throws {
        // Four sets against two: past the partner's last, the rounds are the
        // first movement's alone, and nothing is offered from a movement that
        // has no set there.
        let group = try group(sets: [4, 2])
        let third = working(group.members[0])[2]
        third.isCompleted = true

        #expect(group.setAfter(third, of: group.members[0]) === working(group.members[0])[3])
    }

    @Test("A warm-up is never offered as the next thing to do")
    func warmupsAreNotPartOfARound() throws {
        let group = try group()
        let member = group.members[1]
        let warmup = LoggedSet(setIndex: 99, reps: 0, isWarmup: true)
        member.loggedSets?.append(warmup)
        let first = working(group.members[0])[0]
        first.isCompleted = true

        let next = try #require(group.setAfter(first, of: group.members[0]))
        #expect(next.isWarmup == false)
        #expect(next === working(member)[0])
    }
}
