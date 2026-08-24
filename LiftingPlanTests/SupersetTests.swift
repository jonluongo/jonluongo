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

        // Asked of the slot, not of the prescription behind it — a row may now
        // have no prescription, and warm-up is a fact about the row either way.
        #expect(order.first?.isWarmup == true)
        #expect(order.dropFirst().filter(\.isWarmup).isEmpty)
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

/// Work the user did that nobody prescribed.
///
/// **The defect this closes.** `TrainingSlot.planned` was non-optional, so
/// `trainingOrder` could only build rows from prescriptions — and `addSet`
/// writes a `PerformedSet` with no prescription behind it. Pressing *Add extra
/// set* put a row in the store, exported it to the coach as real volume, and
/// changed nothing on screen. He pressed it, saw nothing, and pressed again.
@MainActor
@Suite("A set nobody prescribed")
struct AddedSetTests {

    private func session() throws -> (ModelContext, Session, PlannedExercise) {
        let context = try StoreFixture.imported(StoreFixture.plan(sessions: 1))
        let session = try #require(try StoreFixture.sessions(in: context).first)
        return (context, session, try #require(session.orderedExercises.first))
    }

    private func log(_ context: ModelContext, _ session: Session) -> SessionLog {
        SessionLog(
            session: session, context: context,
            restTimer: RestTimerModel(), restPreferences: RestPreferences())
    }

    @Test("An added set is a row")
    func anAddedSetDraws() throws {
        let (context, session, exercise) = try session()
        let before = SessionOrder.trainingOrder(of: session).count

        try log(context, session).addSet(to: exercise, warmup: false)

        let after = SessionOrder.trainingOrder(of: session)
        #expect(after.count == before + 1)
        #expect(after.last?.planned == nil, "nothing prescribed it")
        #expect(after.last?.isDone == true, "it is in the record the moment it exists")
    }

    @Test("An added warm-up says it is one")
    func anAddedWarmupIsNamed() throws {
        let (context, session, exercise) = try session()

        try log(context, session).addSet(to: exercise, warmup: true)

        let added = try #require(SessionOrder.trainingOrder(of: session).last)
        #expect(added.isWarmup)
        #expect(added.identity == .warmup, "and takes no set number")
    }

    @Test("Added rows come after the prescription, in the order they happened")
    func addedRowsComeLast() throws {
        let (context, session, exercise) = try session()
        let prescribed = SessionOrder.trainingOrder(of: session).count
        let log = log(context, session)

        try log.addSet(to: exercise, warmup: false, at: Date().addingTimeInterval(60))
        try log.addSet(to: exercise, warmup: false, at: Date().addingTimeInterval(120))

        let order = SessionOrder.trainingOrder(of: session)
        #expect(order.prefix(prescribed).allSatisfy { $0.planned != nil })
        #expect(order.suffix(2).allSatisfy { $0.planned == nil })
    }

    @Test("Taking an added set back removes the row, because nothing is left of it")
    func untickingAnAddedSetRemovesIt() throws {
        // **This is the delete affordance.** A prescribed row empties when it is
        // taken back — the coach still asked for it. An added row exists only
        // because its record does, so taking the record back leaves nothing to
        // draw. A second control would do the same thing twice.
        let (context, session, exercise) = try session()
        let before = SessionOrder.trainingOrder(of: session).count
        let log = log(context, session)
        try log.addSet(to: exercise, warmup: false)

        let added = try #require(SessionOrder.trainingOrder(of: session).last)
        #expect(added.vanishesWhenTakenBack)
        try log.takeBack(added)

        #expect(SessionOrder.trainingOrder(of: session).count == before)
    }

    @Test("Taking a prescribed set back keeps its row")
    func untickingAPrescribedSetKeepsIt() throws {
        let (context, session, exercise) = try session()
        _ = exercise
        let log = log(context, session)
        let slot = try #require(SessionOrder.trainingOrder(of: session).first)
        try log.record(slot, load: Mass(value: 100, unit: .pounds), work: .repetitions(5))
        let count = SessionOrder.trainingOrder(of: session).count

        try log.takeBack(try #require(SessionOrder.trainingOrder(of: session).first))

        #expect(SessionOrder.trainingOrder(of: session).count == count)
        #expect(SessionOrder.trainingOrder(of: session).first?.isDone == false)
    }
}
