import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// Supersets: how they are stored, ordered, and reported.
///
/// **One suite where there were three.** `SupersetStoreTests`, `SupersetOrderTests`
/// and `SupersetRoundsTests` split one subject across three files by which layer
/// happened to be under test, so a change to what a group *is* meant finding all
/// three. A superset is one idea and this is one suite.
///
/// **A group needs no row of its own.** Members share a `groupOrdinal` and sit
/// next to each other in `order`; a round is the *N*th working set of each,
/// taken in that order; the rest sits on the member the round ends with, because
/// that is where the clock actually runs.
@Suite("Supersets")
struct SupersetTests {

    private func group(rest: Int? = 180) -> PlanDocumentEntry {
        .group(PlanDocumentGroup(
            exercises: [
                StoreFixture.exercise(StoreFixture.bench, sets: 3, rest: nil),
                StoreFixture.exercise(StoreFixture.row, sets: 3, rest: nil),
            ],
            restSeconds: rest))
    }

    private func imported(_ entries: [PlanDocumentEntry]) throws -> Session {
        let context = try StoreFixture.imported(StoreFixture.plan(entries: entries))
        return try #require(try StoreFixture.sessions(in: context).first)
    }

    // MARK: - Storing

    @Test("Members share a group ordinal and sit next to each other")
    func membersAreStoredAsAGroup() throws {
        let session = try imported([group()])
        let exercises = session.orderedExercises

        #expect(exercises.count == 2)
        #expect(exercises.map(\.groupOrdinal) == [1, 1])
        #expect(exercises.map(\.order) == [0, 1])
    }

    @Test("The round's rest sits on the member it ends with, and nowhere else")
    func restLandsOnTheLastMember() throws {
        // The clock runs after the round, not between the movements in it, so a
        // rest on the first member would be a rest nobody takes.
        let exercises = try imported([group(rest: 180)]).orderedExercises
        #expect(exercises.map(\.restSeconds) == [nil, 180])
    }

    @Test("A grouped session and a plain one are told apart")
    func groupingSurvives() throws {
        let plain = try imported([.exercise(StoreFixture.exercise())])
        #expect(plain.orderedExercises.allSatisfy { $0.groupOrdinal == nil })
    }

    // MARK: - Reading it back

    @Test("The entries read back as the group they were written as")
    func groupingReadsBack() throws {
        let session = try imported([group()])
        let entries = SessionGrouping.entries(of: session.orderedExercises)

        #expect(entries.count == 1)
        let group = try #require(entries.first?.group)
        #expect(group.members.count == 2)
        #expect(group.letter == "A")
        #expect(group.restSeconds == 180)
    }

    @Test("A group of one is drawn as the plain exercise it is")
    func aGroupOfOneIsNotAGroup() throws {
        // The format refuses writing one, but a member can be removed — and a
        // card labelled "A" holding a single movement is a lie the screen would
        // tell.
        let session = try imported([group()])
        let lone = Array(session.orderedExercises.prefix(1))
        #expect(SessionGrouping.entries(of: lone).first?.group == nil)
    }

    @Test("The document reconstructs as a group, with its rest stated once")
    func itRoundTripsToTheDocument() throws {
        let rebuilt = PlanDocumentSession(reconstructing: try imported([group(rest: 150)]))
        let entry = try #require(rebuilt.entries.first)
        let group = try #require(entry.group)

        #expect(rebuilt.entries.count == 1, "one entry, not two exercises")
        #expect(group.restSeconds == 150)
        #expect(group.exercises.allSatisfy { $0.restSeconds == nil },
                "a member may not state its own rest, and the format refuses one that does")
    }

    // MARK: - The order it is trained in

    @Test("A round runs across the movements, not down one of them")
    func roundsRunAcross() throws {
        let session = try imported([group()])
        let order = SessionOrder.trainingOrder(of: session)

        // bench 1, row 1, bench 2, row 2, bench 3, row 3.
        #expect(order.map(\.exercise.exerciseID) == [
            StoreFixture.bench, StoreFixture.row,
            StoreFixture.bench, StoreFixture.row,
            StoreFixture.bench, StoreFixture.row,
        ])
    }

    @Test("Warm-ups lead, because nobody warms up between rounds")
    func warmupsComeFirst() throws {
        let warmed = PlanDocumentExercise(
            exerciseID: StoreFixture.bench,
            sets: [StoreFixture.set(load: 60, warmup: true), StoreFixture.set()])
        let session = try imported([
            .group(PlanDocumentGroup(
                exercises: [warmed, StoreFixture.exercise(StoreFixture.row, sets: 1, rest: nil)],
                restSeconds: 90))
        ])
        let order = SessionOrder.trainingOrder(of: session)

        #expect(order.first?.planned.isWarmup == true)
        #expect(order.dropFirst().allSatisfy { !$0.planned.isWarmup })
    }

    @Test("Unequal set counts degrade to what is actually there")
    func unequalMembersDegradeHonestly() throws {
        let session = try imported([
            .group(PlanDocumentGroup(
                exercises: [
                    StoreFixture.exercise(StoreFixture.bench, sets: 3, rest: nil),
                    StoreFixture.exercise(StoreFixture.row, sets: 2, rest: nil),
                ],
                restSeconds: 90))
        ])
        let order = SessionOrder.trainingOrder(of: session)

        #expect(order.count == 5, "three and two, not three and three")
        #expect(order.last?.exercise.exerciseID == StoreFixture.bench,
                "the last round is the bench alone, which is what happens on the floor")
    }
}
