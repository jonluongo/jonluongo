import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// The one place a prescription enters the store.
///
/// **The refusals here are the guard on data integrity**, which is the single
/// thing this app insists on. History is keyed by exercise identity, so an ID
/// the catalog does not have would fragment a lift's history irreparably — that
/// is not a training decision, it is the difference between a database and a
/// pile of text.
///
/// **And the merge rule is what lets the coach write a week at a time.** He may
/// rewrite a session nothing has been logged against and may not touch one the
/// user has been through: a set he ticked is the record of what happened.
@Suite("Taking a plan in")
struct PlanImportTests {

    private func catalog() throws -> ExerciseCatalog { try StoreFixture.catalog() }

    // MARK: - What lands

    @Test("Every prescribed set arrives as a row")
    func everySetIsARow() throws {
        // No defaults to override and no second code path: a ramp, a drop set
        // and three identical sets are one shape.
        let context = try StoreFixture.imported(StoreFixture.plan(entries: [
            .exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench,
                sets: [
                    StoreFixture.set(load: 60, warmup: true),
                    StoreFixture.set(load: 80, warmup: true),
                    StoreFixture.set(.repetitions(low: 5, high: 6), load: 100),
                ]))
        ]))
        let exercise = try #require(
            try StoreFixture.sessions(in: context).first?.orderedExercises.first)

        #expect(exercise.orderedSets.count == 3)
        #expect(exercise.orderedSets.map(\.isWarmup) == [true, true, false])
        #expect(exercise.orderedSets.map { $0.load?.value } == [60, 80, 100])
        #expect(exercise.workingSets.count == 1, "warm-ups are not working volume")
    }

    @Test("A prescribed value is stored exactly as prescribed")
    func nothingIsClamped() throws {
        // No clamping a set count, no capping rest, no substituting a default
        // target, no seeding a load from a rule.
        let context = try StoreFixture.imported(StoreFixture.plan(entries: [
            .exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench, restSeconds: 3600,
                sets: Array(repeating: StoreFixture.set(
                    .repetitions(low: 1, high: nil), load: 200), count: 20)))
        ]))
        let exercise = try #require(
            try StoreFixture.sessions(in: context).first?.orderedExercises.first)

        #expect(exercise.restSeconds == 3600)
        #expect(exercise.orderedSets.count == 20)
    }

    @Test("A session arrives with no performance against it")
    func nothingIsSeeded() throws {
        // A performed row exists only if it happened. Rows used to be created
        // for every prescribed set the moment a screen opened, which is where
        // `isCompleted` and `reps = 0` both came from.
        let context = try StoreFixture.imported(StoreFixture.plan())
        let session = try #require(try StoreFixture.sessions(in: context).first)

        #expect((session.performedExercises ?? []).isEmpty)
        #expect(!session.hasBeenTrained)
    }

    @Test("A group's rest lands on the member the round ends with")
    func groupRestIsDistributed() throws {
        let context = try StoreFixture.imported(StoreFixture.plan(entries: [
            .group(PlanDocumentGroup(
                exercises: [
                    StoreFixture.exercise(StoreFixture.bench, rest: nil),
                    StoreFixture.exercise(StoreFixture.row, rest: nil),
                ],
                restSeconds: 120))
        ]))
        let exercises = try #require(
            try StoreFixture.sessions(in: context).first?.orderedExercises)

        #expect(exercises.map(\.restSeconds) == [nil, 120])
        #expect(exercises.map(\.groupOrdinal) == [1, 1])
    }

    // MARK: - Refusal

    @Test("An exercise the catalog does not have is refused, naming it")
    func anUnknownExerciseIsRefused() throws {
        // The one thing this app insists on. A fabricated key fragments a
        // lift's history irreparably.
        let stranger = ExerciseID(rawValue: "moon-press")
        let context = try StoreFixture.context()

        let error = #expect(throws: PlanImportError.self) {
            try PlanImporter.import(
                StoreFixture.plan(entries: [.exercise(StoreFixture.exercise(stranger))]),
                into: context, catalog: try catalog())
        }

        #expect(error == .unknownExercise(stranger))
        #expect(try StoreFixture.sessions(in: context).isEmpty, "nothing was taken in")
    }

    @Test("A mark this build cannot draw is refused, naming it")
    func anUnknownIconIsRefused() throws {
        // The app must never pick one: a glyph inferred from the word "Push"
        // would be the app deciding what a session trains.
        let context = try StoreFixture.context()
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1,
                icon: SessionIcon(rawValue: "deadlift"),
                entries: [.exercise(StoreFixture.exercise())])])

        #expect(throws: PlanImportError.self) {
            try PlanImporter.import(document, into: context, catalog: try catalog())
        }
        #expect(try StoreFixture.sessions(in: context).isEmpty)
    }

    @Test("A refusal takes nothing in, including the sessions that were fine")
    func aRefusalIsWholesale() throws {
        // A plan half-imported and half-reported as an error is the failure that
        // reports success: the writer is told his prescription landed when only
        // part of it did.
        let context = try StoreFixture.context()
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [
                PlanDocumentSession(
                    blockOrdinal: 1, ordinal: 1,
                    entries: [.exercise(StoreFixture.exercise())]),
                PlanDocumentSession(
                    blockOrdinal: 1, ordinal: 2,
                    entries: [.exercise(StoreFixture.exercise(
                        ExerciseID(rawValue: "moon-press")))]),
            ])

        #expect(throws: PlanImportError.self) {
            try PlanImporter.import(document, into: context, catalog: try catalog())
        }
        #expect(try StoreFixture.sessions(in: context).isEmpty,
                "the first session was readable and still did not land")
    }

    // MARK: - Merging

    @Test("A block the coach adds lands beside the one already there")
    func laterBlocksAppend() throws {
        // This is what lets him write a week at a time.
        let context = try StoreFixture.imported(StoreFixture.plan(block: 1))
        try PlanImporter.import(
            StoreFixture.plan(block: 2), into: context, catalog: try catalog())

        #expect(try StoreFixture.sessions(in: context).map(\.blockOrdinal) == [1, 2])
    }

    @Test("A session nothing has been logged against is rewritten whole")
    func anUntrainedSessionIsRebuilt() throws {
        let context = try StoreFixture.imported(StoreFixture.plan())
        try PlanImporter.import(
            StoreFixture.plan(entries: [.exercise(StoreFixture.exercise(StoreFixture.squat))]),
            into: context, catalog: try catalog())

        let exercises = try #require(
            try StoreFixture.sessions(in: context).first?.orderedExercises)
        #expect(exercises.count == 1)
        #expect(exercises.first?.exerciseID == StoreFixture.squat)
    }

    @Test("An unchanged document arriving twice changes nothing")
    func reimportingIsANoOp() throws {
        let document = StoreFixture.plan()
        let context = try StoreFixture.imported(document)

        #expect(try !PlanImporter.wouldChange(document, in: context, catalog: try catalog()))
        try PlanImporter.import(document, into: context, catalog: try catalog())
        #expect(try StoreFixture.sessions(in: context).count == 1)
    }

    @Test("A session he has trained is refused by ordinal, with nothing taken in")
    @MainActor
    func aTrainedSessionCannotBeRewritten() throws {
        let context = try StoreFixture.imported(StoreFixture.plan())
        let session = try #require(try StoreFixture.sessions(in: context).first)
        let slot = try #require(SessionOrder.trainingOrder(of: session).first)
        try SessionLog(
            session: session, context: context, restTimer: RestTimerModel(),
            restPreferences: RestPreferences()
        ).record(slot, load: Mass(value: 100, unit: .kilograms), work: .repetitions(5))

        let error = #expect(throws: PlanImportError.self) {
            try PlanImporter.import(
                StoreFixture.plan(entries: [
                    .exercise(StoreFixture.exercise(StoreFixture.squat))
                ]),
                into: context, catalog: try catalog())
        }

        #expect(error == .trainedSessionChanged(block: 1, ordinal: 1))
        #expect(session.orderedExercises.first?.exerciseID == StoreFixture.bench,
                "what he trained is still what the record says he trained")
    }

    @Test("A session he finished without ticking anything is trained too")
    @MainActor
    func finishingCountsAsTraining() throws {
        // He went through it. A plan that rewrites it would be rewriting what
        // happened, whether or not he filled the table in.
        let context = try StoreFixture.imported(StoreFixture.plan())
        let session = try #require(try StoreFixture.sessions(in: context).first)
        try SessionLog(
            session: session, context: context, restTimer: RestTimerModel(),
            restPreferences: RestPreferences()
        ).finish()

        #expect(throws: PlanImportError.self) {
            try PlanImporter.import(
                StoreFixture.plan(entries: [
                    .exercise(StoreFixture.exercise(StoreFixture.squat))
                ]),
                into: context, catalog: try catalog())
        }
    }
}
