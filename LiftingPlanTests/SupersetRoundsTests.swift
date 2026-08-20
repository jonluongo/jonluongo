import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// When a group's rest is owed.
///
/// The rest is owed when the *round* finishes, not when a set does — the one
/// behavioural difference a group makes, and the reason the grouping is worth
/// expressing at all.
///
/// This suite used to assert the layout of a screen that interleaved a group's
/// rows by round — A1, A2, A1, A2 — with a notation on each and the warm-ups
/// outside the rounds. The movements are drawn as movements now, each with its
/// own numbered rows, and everything that built those rows went with the screen.
/// What survives is the question the rest clock still asks.
@Suite("A superset, round by round")
struct SupersetRoundsTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let fly = ExerciseID(rawValue: "dumbbell-chest-fly")
    private static let pushdown = ExerciseID(rawValue: "cable-rope-pushdown")
    private static let curl = ExerciseID(rawValue: "barbell-curl")

    /// A stored group with `sets` rows on each member, none ticked.
    private func group(
        sets: [Int] = [3, 3],
        ids: [ExerciseID] = [SupersetRoundsTests.fly, SupersetRoundsTests.pushdown],
        restSeconds: Int? = 90
    ) throws -> (ExerciseGroup, ModelContext) {
        let context = ModelContext(try StoreContainer.inMemory())
        let day = WorkoutDay(weekday: .monday)
        let identity = UUID()
        day.exercises = zip(ids, sets).enumerated().map { position, pair in
            let exercise = PlannedExercise(
                exerciseID: pair.0, displayName: pair.0.rawValue, order: position,
                targetSets: pair.1, repRange: "12-15",
                restSeconds: position == ids.count - 1 ? restSeconds : nil)
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
        return (group, context)
    }

    // MARK: - The rest is owed to the round

    @Test("A round is not complete until every movement in it is ticked")
    func restWaitsForTheWholeRound() throws {
        let (group, _) = try group()
        let first = group.members.map { ($0.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }[0] }

        first[0].isCompleted = true
        #expect(
            !group.hasCompleteRound(containing: first[0]),
            "A1 alone does not finish the round")

        first[1].isCompleted = true
        #expect(group.hasCompleteRound(containing: first[1]))
    }

    @Test("Taking a set back un-finishes the round it was in")
    func takingASetBackEndsTheRound() throws {
        let (group, _) = try group()
        let first = group.members.map { ($0.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }[0] }
        for set in first { set.isCompleted = true }
        #expect(group.hasCompleteRound(containing: first[1]))

        first[0].isCompleted = false
        #expect(!group.hasCompleteRound(containing: first[1]))
    }

    @Test("A tri-set rests only when all three are ticked")
    func triSetWaitsForEveryMovement() throws {
        let (group, _) = try group(
            sets: [3, 3, 3], ids: [Self.fly, Self.pushdown, Self.curl])
        let first = group.members.map { ($0.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }[0] }

        first[0].isCompleted = true
        first[1].isCompleted = true
        #expect(
            !group.hasCompleteRound(containing: first[1]), "two of three is not a round")

        first[2].isCompleted = true
        #expect(group.hasCompleteRound(containing: first[2]))
    }

    @Test("A warm-up finishes no round")
    func warmupFinishesNoRound() throws {
        let (group, context) = try group()
        SetSeeding.addSet(to: group.members[0], warmup: true, in: context)
        let warmup = try #require((group.members[0].loggedSets ?? []).first { $0.isWarmup })
        warmup.isCompleted = true

        // A warm-up belongs to the movement it warms up, not to a round the
        // partner movement is also in.
        #expect(!group.hasCompleteRound(containing: warmup))
    }

    // MARK: - Which round

    @Test("A round that closed earlier does not owe rest for the one being trained")
    func anEarlierRoundDoesNotPayForThisOne() throws {
        // The failure: `hasCompleteRound` asked whether *any* round was
        // finished. From round two onward the answer was yes because round one
        // was, so ticking the first movement of a round started the group's
        // rest — the exact thing a superset exists not to do, and the lifter is
        // sent to wait 90 seconds instead of straight to the next movement.
        let (group, _) = try group()
        let sets = group.members.map { ($0.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex } }

        // Round one, closed properly.
        sets[0][0].isCompleted = true
        sets[1][0].isCompleted = true
        #expect(group.hasCompleteRound(containing: sets[1][0]), "the round he just closed")

        // Round two: the first movement only.
        sets[0][1].isCompleted = true
        #expect(
            !group.hasCompleteRound(containing: sets[0][1]),
            "the next movement follows immediately; nothing is owed yet")

        sets[1][1].isCompleted = true
        #expect(group.hasCompleteRound(containing: sets[1][1]))
    }

    @Test("A movement prescribed more sets than its partner rests on its own rounds")
    func aRoundOfOneStillCloses() throws {
        // Documented behaviour: the later positions are rounds of one, which is
        // what the lifter is actually doing by then.
        let (group, _) = try group(sets: [3, 2])
        let sets = group.members.map { ($0.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex } }
        for round in 0..<2 {
            sets[0][round].isCompleted = true
            sets[1][round].isCompleted = true
        }

        sets[0][2].isCompleted = true

        #expect(
            group.hasCompleteRound(containing: sets[0][2]),
            "nobody else is in this round, so ticking it closes it")
    }
}
