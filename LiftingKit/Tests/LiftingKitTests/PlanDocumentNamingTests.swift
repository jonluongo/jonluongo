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
            days: [PlanDocumentDay(
                weekday: .monday,
                entries: entries ?? exercises.map(PlanDocumentEntry.exercise))])
    }

    private func named(_ document: PlanDocument) throws -> [PlanDocumentExercise] {
        document.named(using: try catalog())
            .blocks.flatMap(\.days).flatMap(\.entries).flatMap(\.exercises)
    }

    @Test("A movement with no name is given the catalog's")
    func blankNameIsFilled() throws {
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "", sets: 3, repRange: "5")])

        #expect(try named(written).first?.displayName == "Barbell Bench Press")
    }

    @Test("A name the coach did state reaches the lifter unchanged")
    func statedNameIsKept() throws {
        // He may have a reason for it, and it is his document.
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "Comp Bench", sets: 3)])

        #expect(try named(written).first?.displayName == "Comp Bench")
    }

    @Test("An ID the catalog does not have keeps whatever name it came with")
    func unknownIDIsLeftAlone() throws {
        // Refusing an unknown ID belongs to `write_plan` and to `PlanImporter`;
        // doing it here as well would report the wrong failure.
        let written = document([PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "not-an-exercise"), displayName: "", sets: 3)])

        #expect(try named(written).first?.displayName == "")
    }

    @Test("Naming reaches the members of a group")
    func groupMembersAreNamed() throws {
        let written = document([], entries: [.group(PlanDocumentGroup(
            exercises: [
                PlanDocumentExercise(exerciseID: Self.bench, displayName: "", sets: 3),
                PlanDocumentExercise(
                    exerciseID: ExerciseID(rawValue: "dumbbell-curl"), displayName: "", sets: 3),
            ],
            restSeconds: 90))])

        #expect(try named(written).map(\.displayName)
            == ["Barbell Bench Press", "Dumbbell Curl"])
    }

    @Test("Nothing else about the document moves, and a ramp stays a ramp")
    func onlyTheNameChanges() throws {
        let ramp = [
            SetPrescription(repRange: "5", suggestedLoad: Mass(value: 135, unit: .pounds)),
            SetPrescription(repRange: "3", suggestedLoad: Mass(value: 185, unit: .pounds)),
        ]
        let written = document([PlanDocumentExercise(
            exerciseID: Self.bench, displayName: "", sets: ramp,
            repRange: "5", restSeconds: 180, tempo: "3-0-1-0", notes: "Pause it")])

        let read = try #require(try named(written).first)
        #expect(read.statedSets == ramp)
        #expect(read.sets == 2)
        #expect(read.restSeconds == 180)
        #expect(read.tempo == "3-0-1-0")
        #expect(read.notes == "Pause it")
    }

    @Test("A document that states no name at all still decodes")
    func absentKeyDecodes() throws {
        let data = Data("""
            {"version": 4, "id": "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1",
             "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
             "days": [{"weekday": 2, "exercises": [
               {"exerciseID": "barbell-bench-press", "sets": 3, "repRange": "5"}]}]}
            """.utf8)

        let decoded = try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
        #expect(decoded.blocks.first?.days.first?.entries.first?
            .exercises.first?.displayName == "")
        #expect(try named(decoded).first?.displayName == "Barbell Bench Press")
    }
}
