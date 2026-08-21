import Foundation
import Testing
@testable import LiftingKit

/// That a plan need not carry a name the catalog already holds.
///
/// The display name is display only — never an identity, never a join key — and
/// the catalog that owns it is linked by the server that writes plans and by the
/// app that reads them. Asking the coach for it was a key per exercise whose
/// only possible outcomes were agreeing with the catalog or disagreeing with it.
@Suite("Naming a plan from the catalog")
struct PlanDocumentNamingTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func catalog() throws -> ExerciseCatalog { try ExerciseCatalog.bundled() }

    private func document(
        _ exercises: [PlanDocumentExercise], entries: [PlanDocumentEntry]? = nil
    ) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1,
                entries: entries ?? exercises.map(PlanDocumentEntry.exercise))])
    }

    private func named(_ document: PlanDocument) throws -> [PlanDocumentExercise] {
        document.named(using: try catalog()).sessions.flatMap(\.exercises)
    }

    @Test("A movement with no name is given the catalog's")
    func blankNameIsFilled() throws {
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "", sets: Array(repeating: PlanDocumentSet(target: Target(shorthand: "5")), count: 3))])

        #expect(try named(written).first?.displayName == "Barbell Bench Press")
    }

    @Test("A name the coach did state reaches the lifter unchanged")
    func statedNameIsKept() throws {
        // He may have a reason for it, and it is his document.
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Comp Bench", sets: Array(repeating: PlanDocumentSet(), count: 3))])

        #expect(try named(written).first?.displayName == "Comp Bench")
    }

    @Test("An ID the catalog does not have keeps whatever name it came with")
    func unknownIDIsLeftAlone() throws {
        // Refusing an unknown ID belongs to `write_plan` and to `PlanImporter`;
        // doing it here as well would report the wrong failure.
        let written = document([PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "not-an-exercise"), displayName: "", sets: Array(repeating: PlanDocumentSet(), count: 3))])

        #expect(try named(written).first?.displayName == "")
    }

    @Test("Naming reaches the members of a group")
    func groupMembersAreNamed() throws {
        let written = document([], entries: [.group(PlanDocumentGroup(
            exercises: [
                PlanDocumentExercise(exerciseID: Self.bench, displayName: "", sets: Array(repeating: PlanDocumentSet(), count: 3)),
                PlanDocumentExercise(
                    exerciseID: ExerciseID(rawValue: "dumbbell-curl"), displayName: "", sets: Array(repeating: PlanDocumentSet(), count: 3)),
            ],
            restSeconds: 90))])

        #expect(try named(written).map(\.displayName)
            == ["Barbell Bench Press", "Dumbbell Curl"])
    }

    @Test("Nothing else about the document moves, and a ramp stays a ramp")
    func onlyTheNameChanges() throws {
        let ramp = [
            PlanDocumentSet(
                target: .repetitions(low: 5, high: nil),
                load: Mass(value: 135, unit: .pounds)),
            PlanDocumentSet(
                target: .repetitions(low: 3, high: nil),
                load: Mass(value: 185, unit: .pounds)),
        ]
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "", restSeconds: 180,
            coachNote: "Pause it. Three down, explode up.", sets: ramp)])

        let read = try #require(try named(written).first)
        #expect(read.sets == ramp, "every set as written, in order")
        #expect(read.restSeconds == 180)
        #expect(read.coachNote == "Pause it. Three down, explode up.")
    }

    @Test("A document that states no name at all still decodes")
    func absentKeyDecodes() throws {
        let data = Data("""
            {"version": 6, "id": "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1",
             "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
             "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
               {"exerciseID": "barbell-bench-press", "sets": [{"target": "5"}]}]}]}
            """.utf8)

        let decoded = try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
        #expect(decoded.sessions.first?.exercises.first?.displayName == "")
        #expect(try named(decoded).first?.displayName == "Barbell Bench Press")
    }
}
