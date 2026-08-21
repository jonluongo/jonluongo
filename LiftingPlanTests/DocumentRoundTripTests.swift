import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What the store holds, said back as the document it came from.
///
/// **This suite is the reason there are two vocabularies and not three.** A
/// prescription used to live in the document, in the models, and in a tree of
/// snapshot types that restated it — and the first and third disagreed about how
/// a superset is written. The snapshot carries the document itself now, and
/// `PlanDocumentSession(reconstructing:)` is the bridge. What proves the bridge
/// is lossless is asserting it, which is what these do.
///
/// **A field that survives here is a field the coach gets back.** One that does
/// not is a prescription he wrote and will never see again.
@Suite("What the store gives back")
struct DocumentRoundTripTests {

    private func reconstructed(_ document: PlanDocument) throws -> PlanDocumentSession {
        let context = try StoreFixture.imported(document)
        let session = try #require(try StoreFixture.sessions(in: context).first)
        return PlanDocumentSession(reconstructing: session)
    }

    /// Names are filled in from the catalog at both ends and never stored, so a
    /// comparison clears them on both sides — otherwise *unchanged* would mean
    /// *named differently*.
    private func unnamed(_ session: PlanDocumentSession) -> PlanDocumentSession {
        PlanDocumentSession(
            blockOrdinal: session.blockOrdinal, ordinal: session.ordinal,
            focus: session.focus, icon: session.icon,
            entries: session.entries.map { entry in
                switch entry {
                case .exercise(let exercise): .exercise(stripped(exercise))
                case .group(let group): .group(PlanDocumentGroup(
                    exercises: group.exercises.map(stripped), restSeconds: group.restSeconds))
                }
            })
    }

    private func stripped(_ exercise: PlanDocumentExercise) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: exercise.exerciseID, displayName: "",
            restSeconds: exercise.restSeconds, coachNote: exercise.coachNote,
            sets: exercise.sets)
    }

    @Test("A session comes back as the session it went in as")
    func aSessionSurvivesWhole() throws {
        let written = PlanDocumentSession(
            blockOrdinal: 2, ordinal: 3, focus: "Push", icon: .strength,
            entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench, restSeconds: 210,
                coachNote: "Three down, explode up.",
                sets: [
                    StoreFixture.set(load: 60, warmup: true),
                    StoreFixture.set(.repetitions(low: 5, high: 6), load: 100),
                    StoreFixture.set(.repetitionsToFailure, load: 80),
                ]))])
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [written])

        #expect(try reconstructed(document) == unnamed(written))
    }

    @Test("Every measure comes back as the measure it was")
    func everyMeasureSurvives() throws {
        let written = PlanDocumentSession(
            blockOrdinal: 1, ordinal: 1,
            entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench,
                sets: [
                    StoreFixture.set(.repetitions(low: 8, high: 12), load: nil),
                    StoreFixture.set(.time(low: 45, high: nil), load: nil),
                    StoreFixture.set(.distance(low: 40, high: nil, unit: .metres), load: nil),
                    StoreFixture.set(.repetitionsToFailure, load: nil),
                ]))])

        let back = try reconstructed(PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [written]))

        #expect(back.exercises.first?.sets.map(\.target) == [
            .repetitions(low: 8, high: 12), .time(low: 45, high: nil),
            .distance(low: 40, high: nil, unit: .metres), .repetitionsToFailure,
        ])
    }

    @Test("A carry keeps the unit it was prescribed in")
    func aCarryKeepsItsUnit() throws {
        let written = PlanDocumentSession(
            blockOrdinal: 1, ordinal: 1,
            entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench,
                sets: [StoreFixture.set(
                    .distance(low: 40, high: nil, unit: .yards), load: nil)]))])

        let back = try reconstructed(PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [written]))

        #expect(back.exercises.first?.sets.first?.target
            == .distance(low: 40, high: nil, unit: .yards),
            "forty yards is not forty metres and nothing here converts one to the other")
    }

    @Test("An unstated value comes back unstated rather than as a zero")
    func absenceSurvives() throws {
        let written = PlanDocumentSession(
            blockOrdinal: 1, ordinal: 1,
            entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench, restSeconds: nil, coachNote: nil,
                sets: [PlanDocumentSet(
                    intensity: IntensityTarget(scale: .rpe, value: "8"))]))])

        let back = try reconstructed(PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [written]))
        let exercise = try #require(back.exercises.first)

        #expect(exercise.restSeconds == nil)
        #expect(exercise.coachNote == nil)
        #expect(exercise.sets.first?.load == nil, "the lifter picks the bar")
        #expect(exercise.sets.first?.target == nil)
        #expect(exercise.sets.first?.intensity?.value == "8")
    }

    @Test("A session the coach named nothing comes back named nothing")
    func anUnnamedSessionStaysUnnamed() throws {
        let back = try reconstructed(PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1,
                entries: [.exercise(StoreFixture.exercise())])]))

        #expect(back.focus.isEmpty)
        #expect(back.icon == nil, "a mark the app chose would be the app deciding")
    }

    @Test("A rest day comes back as a rest day, not as an omission")
    func aRestDaySurvives() throws {
        let back = try reconstructed(PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: StoreFixture.instant,
            sessions: [PlanDocumentSession(blockOrdinal: 1, ordinal: 1, focus: "Rest")]))

        #expect(back.entries.isEmpty)
        #expect(back.focus == "Rest")
    }
}
