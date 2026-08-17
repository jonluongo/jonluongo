import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// How a group's logged sets are laid out on the logging screen.
///
/// The unit of work is the round, so the rows interleave: round one is A1 then
/// A2, round two is A1 then A2 again. And the rest is owed when the *round*
/// finishes, not when a set does — the one behavioural difference a group makes,
/// and the reason the grouping is worth expressing at all.
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

    private func rounds(_ group: ExerciseGroup) -> GroupRounds {
        GroupRounds(group: group, plans: [], unit: .pounds)
    }

    // MARK: - Interleaved by round

    @Test("Round one is A1 then A2, and round two is A1 then A2 again")
    func rowsInterleaveByRound() throws {
        let (group, _) = try group()
        let laid = rounds(group)

        #expect(laid.rounds.map(\.number) == [1, 2, 3])
        #expect(laid.rounds.allSatisfy { $0.rows.count == 2 })
        #expect(laid.rounds[0].rows.map(\.member.exerciseID) == [Self.fly, Self.pushdown])
        #expect(laid.rounds[1].rows.map(\.member.exerciseID) == [Self.fly, Self.pushdown])
    }

    @Test("A row is badged with its movement's notation and says the round aloud")
    func rowsAreBadgedAndSpoken() throws {
        let (group, _) = try group()
        let laid = rounds(group)

        #expect(laid.rounds[0].rows.map(\.identity.badge) == ["A1", "A2"])
        #expect(laid.rounds[1].rows[0].identity.badge == "A1")
        #expect(laid.rounds[1].rows[0].identity.spoken
            == "dumbbell-chest-fly, A1, round 2")
        #expect(laid.rounds[2].rows[1].identity.spoken
            == "cable-rope-pushdown, A2, round 3")
    }

    @Test("A tri-set lays out three rows a round")
    func triSetHasThreeRowsARound() throws {
        let (group, _) = try group(
            sets: [3, 3, 3], ids: [Self.fly, Self.pushdown, Self.curl])
        let laid = rounds(group)

        #expect(laid.rounds.count == 3)
        #expect(laid.rounds[0].rows.map(\.identity.badge) == ["A1", "A2", "A3"])
    }

    @Test("Movements prescribed different counts run until the longest is done")
    func unevenGroupKeepsEverySet() throws {
        let (group, _) = try group(sets: [4, 3])
        let laid = rounds(group)

        #expect(laid.rounds.count == 4)
        #expect(laid.rounds[3].rows.count == 1, "only A1 has a fourth set")
        #expect(laid.rounds[3].rows[0].identity.badge == "A1")
        #expect(laid.rounds.flatMap(\.rows).count == 7, "no prescribed set is dropped")
    }

    @Test("A warm-up belongs to its movement, not to a round")
    func warmupsSitOutsideTheRounds() throws {
        let (group, context) = try group()
        let member = group.members[0]
        SetSeeding.addSet(to: member, warmup: true, in: context)
        let laid = rounds(group)

        #expect(laid.warmups.count == 1)
        #expect(laid.warmups[0].round == nil)
        #expect(laid.warmups[0].identity.badge == "W")
        #expect(laid.warmups[0].identity.spoken == "dumbbell-chest-fly, A1, warm-up set")
        #expect(laid.rounds.count == 3, "the warm-up added no round")
    }

    // MARK: - The rest is owed to the round

    @Test("A round is not complete until every movement in it is ticked")
    func restWaitsForTheWholeRound() throws {
        let (group, _) = try group()
        let laid = rounds(group)

        laid.rounds[0].rows[0].set.isCompleted = true
        #expect(!rounds(group).isComplete(round: 1), "A1 alone does not finish the round")

        laid.rounds[0].rows[1].set.isCompleted = true
        #expect(rounds(group).isComplete(round: 1))
        #expect(!rounds(group).isComplete(round: 2))
    }

    @Test("Taking a set back un-finishes the round it was in")
    func takingASetBackEndsTheRound() throws {
        let (group, _) = try group()
        for row in rounds(group).rounds[0].rows { row.set.isCompleted = true }
        #expect(rounds(group).isComplete(round: 1))

        rounds(group).rounds[0].rows[0].set.isCompleted = false
        #expect(!rounds(group).isComplete(round: 1))
    }

    @Test("A warm-up finishes no round")
    func warmupFinishesNoRound() throws {
        let (group, _) = try group()
        #expect(!rounds(group).isComplete(round: nil))
    }

    // MARK: - The prescription still reaches every row

    @Test("Each row carries its own set's prescription, not the exercise's average")
    func eachRowCarriesItsOwnPrescription() throws {
        let context = ModelContext(try StoreContainer.inMemory())
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(weekday: .monday, entries: [
                .group(PlanDocumentGroup(exercises: [
                    PlanDocumentExercise(
                        exerciseID: Self.fly, displayName: "Fly",
                        sets: [
                            SetPrescription(suggestedLoad: Mass(value: 20, unit: .pounds)),
                            SetPrescription(suggestedLoad: Mass(value: 25, unit: .pounds)),
                            SetPrescription(repRange: "8", notes: "to failure"),
                        ],
                        repRange: "12"),
                    PlanDocumentExercise(
                        exerciseID: Self.pushdown, displayName: "Pushdown",
                        sets: 3, repRange: "15"),
                ], restSeconds: 90))
            ])]
        )
        try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        let plan = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        let week = try #require(plan.orderedWeeks.first)
        let day = try #require(week.orderedDays.first)
        SetSeeding.seedMissingSets(for: day.orderedExercises, in: context)
        guard case .group(let group)? = day.entries.first else {
            Issue.record("the day holds one group")
            return
        }
        let laid = rounds(group)

        #expect(laid.rounds.map { $0.rows[0].loadTarget } == ["20", "25", "—"])
        #expect(laid.rounds.map { $0.rows[0].prescribed?.repRange } == ["12", "12", "8"])
        #expect(laid.rounds[2].rows[0].prescribed?.notes == "to failure")
        #expect(laid.rounds.map { $0.rows[1].prescribed?.repRange } == ["15", "15", "15"])
    }

    @Test("A set the lifter added past the prescription is his own, not the plan's")
    func addedRowIsNotPrescribed() throws {
        let (group, context) = try group()
        SetSeeding.addSet(to: group.members[0], warmup: false, in: context)
        let laid = rounds(group)

        #expect(laid.rounds.count == 4)
        #expect(laid.rounds[3].rows[0].prescribed == nil)
        #expect(laid.rounds[3].rows[0].loadTarget == "—")
    }
}
