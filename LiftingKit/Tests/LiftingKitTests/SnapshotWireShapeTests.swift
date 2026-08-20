import Foundation
import Testing
@testable import LiftingKit

/// What the snapshot actually says on the wire.
///
/// The app writes this file and a separate process reads it, so the shape is a
/// contract rather than an implementation detail: a key renamed here is a key
/// the coach stops seeing, silently. These pin the shape by reading the encoded
/// JSON rather than by round-tripping Swift values, which would pass whatever
/// the two sides happened to agree on.
///
/// **The shape changed in version 3.** A block used to be restated as a tree of
/// snapshot types beside the plan document it came from — the same prescription
/// written twice, and written differently: nested one side, flattened the other.
/// A routine carries the document itself now, and every logged set is one row of
/// a flat series that names where it sits.
@Suite("Snapshot wire shape")
struct SnapshotWireShapeTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let routineID = UUID(uuidString: "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1")!
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    // MARK: - Fixtures

    private func document(
        exercises: [PlanDocumentExercise] = [],
        entries: [PlanDocumentEntry]? = nil,
        notes: String? = nil
    ) -> PlanDocument {
        PlanDocument(
            id: Self.routineID, catalogVersion: 5, generatedAt: Self.instant,
            title: "Autumn strength", goal: "Add 20 lb", durationMinutes: 60, notes: notes,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Push", durationMinutes: 60,
                entries: entries ?? exercises.map(PlanDocumentEntry.exercise))])
    }

    private func logged(
        reps: Int = 5, load: Mass? = Mass(value: 225, unit: .pounds),
        durationSeconds: Int? = nil, distance: Distance? = nil
    ) -> LoggedSetRecord {
        LoggedSetRecord(
            routineID: Self.routineID, blockOrdinal: 1, weekday: .monday, exerciseOrder: 0,
            exerciseID: Self.bench, setIndex: 0, isWarmup: false, isCompleted: true,
            completedAt: Self.instant, load: load, reps: reps,
            durationSeconds: durationSeconds, distance: distance)
    }

    private func snapshot(
        document: PlanDocument? = nil, log: [LoggedSetRecord] = []
    ) -> TrainingSnapshot {
        TrainingSnapshot(
            catalogVersion: 5, generatedAt: Self.instant,
            routines: [SnapshotRoutine(
                document: document ?? self.document(),
                startDate: Self.instant, completedAt: nil,
                sessions: [SnapshotSession(
                    blockOrdinal: 1, weekday: .monday, completedAt: Self.instant)])],
            log: log)
    }

    private func object(_ snapshot: TrainingSnapshot) throws -> [String: Any] {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func firstLogRow(_ snapshot: TrainingSnapshot) throws -> [String: Any] {
        let log = try #require(try object(snapshot)["log"] as? [[String: Any]])
        return try #require(log.first)
    }

    // MARK: - A block is the document the coach wrote

    @Test("A routine carries the plan document itself, under 'document'")
    func routineCarriesTheDocument() throws {
        let written = document(
            exercises: [PlanDocumentExercise(
                exerciseID: Self.bench, displayName: "Barbell Bench Press", sets: 3,
                repRange: "5", restSeconds: 180)],
            notes: "Take the deload.")
        let routines = try #require(
            try object(snapshot(document: written))["routines"] as? [[String: Any]])
        let carried = try #require(routines.first?["document"] as? [String: Any])

        #expect(carried["title"] as? String == "Autumn strength")
        #expect(carried["notes"] as? String == "Take the deload.")
        // The document's own version travels with it, so a reader knows which
        // format the prescription inside was written in.
        #expect(carried["version"] as? Int == PlanDocument.currentVersion)
        #expect(routines.first?["startDate"] as? String == "2023-11-14T22:13:20Z")
    }

    @Test("A routine's document decodes back as the document it was")
    func documentSurvivesTheWire() throws {
        let written = document(entries: [.group(PlanDocumentGroup(
            exercises: [
                PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press", sets: 3),
                PlanDocumentExercise(
                    exerciseID: ExerciseID(rawValue: "barbell-curl"),
                    displayName: "Barbell Curl", sets: 3),
            ],
            restSeconds: 90))])
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot(document: written))
        let read = try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)

        // A superset survives as a group rather than as a marker on each member,
        // because it is the coach's own document that came back.
        #expect(read.routines.first?.document == written)
    }

    @Test("What the record knows, and not what it does not, sits beside the document")
    func recordFactsSitBesideIt() throws {
        let routines = try #require(try object(snapshot())["routines"] as? [[String: Any]])
        let sessions = try #require(routines.first?["sessions"] as? [[String: Any]])

        #expect(sessions.first?["blockOrdinal"] as? Int == 1)
        // Calendar's numbering, 1 = Sunday, which is what `Weekday` is.
        #expect(sessions.first?["weekday"] as? Int == Weekday.monday.rawValue)
        #expect(sessions.first?["completedAt"] as? String == "2023-11-14T22:13:20Z")
        // A block nothing has superseded states no closing date rather than a
        // null one: the key is absent.
        #expect(routines.first?["completedAt"] == nil)
    }

    // MARK: - The log is flat, and every row says where it sits

    @Test("A logged set names the block, the week, the day, the movement and the set")
    func logRowNamesItsPosition() throws {
        let row = try firstLogRow(snapshot(log: [logged()]))

        #expect(row["routineID"] as? String == Self.routineID.uuidString)
        #expect(row["blockOrdinal"] as? Int == 1)
        #expect(row["weekday"] as? Int == Weekday.monday.rawValue)
        #expect(row["exerciseOrder"] as? Int == 0)
        #expect(row["exerciseID"] as? String == "barbell-bench-press")
        #expect(row["setIndex"] as? Int == 0)
        #expect(row["isWarmup"] as? Bool == false)
        #expect(row["isCompleted"] as? Bool == true)
    }

    @Test("A counted set writes reps, and no duration and no distance at all")
    func countedSetWritesRepsOnly() throws {
        let row = try firstLogRow(snapshot(log: [logged(reps: 5)]))

        #expect(row["reps"] as? Int == 5)
        // Absent rather than null or zero: a counted set was not held for no
        // time and did not travel no distance.
        #expect(row["durationSeconds"] == nil)
        #expect(row["distance"] == nil)
    }

    @Test("A held set writes its seconds and reports no reps")
    func heldSetWritesSeconds() throws {
        let row = try firstLogRow(
            snapshot(log: [logged(reps: 0, load: nil, durationSeconds: 34)]))

        #expect(row["durationSeconds"] as? Int == 34)
        #expect(row["reps"] as? Int == 0)
        #expect(row["distance"] == nil)
        #expect(row["load"] == nil)
    }

    @Test("A carried set writes a value and the unit it was carried in")
    func carriedSetWritesItsUnit() throws {
        let row = try firstLogRow(snapshot(log: [logged(
            reps: 0, load: nil, distance: Distance(value: 40, unit: .metres))]))
        let distance = try #require(row["distance"] as? [String: Any])

        // The unit travels with the number. Two carries in different units are
        // two facts, and a reader that assumed one would report a distance
        // nobody covered.
        #expect(distance["value"] as? Double == 40)
        #expect(distance["unit"] as? String == "m")
        #expect(row["durationSeconds"] == nil)
    }

    @Test("A load is written in the unit it was entered in, never converted")
    func loadKeepsItsUnit() throws {
        let row = try firstLogRow(snapshot(log: [logged(
            load: Mass(value: 100, unit: .kilograms))]))
        let load = try #require(row["load"] as? [String: Any])

        #expect(load["value"] as? Double == 100)
        #expect(load["unit"] as? String == "kg")
    }

    // MARK: - The format says which one it is

    @Test("The snapshot states version 5, and a reader that finds another refuses it")
    func versionIsStatedAndEnforced() throws {
        #expect(TrainingSnapshot.currentVersion == 5)
        #expect(try object(snapshot())["version"] as? Int == 5)

        // Both directions: the shape moved, so neither an older nor a newer file
        // can be read as though sections were merely absent.
        for stated in [4, 6] {
            let data = Data("""
                {"version": \(stated), "catalogVersion": 5,
                 "generatedAt": "2023-11-14T22:13:20Z"}
                """.utf8)
            #expect(throws: DocumentRefusal.self) {
                try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
            }
        }
    }

    @Test("A hand-written snapshot reads, so the shape is writable by something else")
    func handWrittenSnapshotDecodes() throws {
        let data = Data("""
            {
              "version": 5,
              "catalogVersion": 5,
              "generatedAt": "2023-11-14T22:13:20Z",
              "routines": [{
                "document": {
                  "version": 4, "id": "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1",
                  "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
                  "title": "Autumn strength",
                  "weeks": [{"days": [{"weekday": 2, "exercises": [
                    {"exerciseID": "barbell-bench-press", "displayName": "Bench",
                     "sets": 3, "repRange": "5"}]}]}]
                },
                "startDate": "2023-11-14T22:13:20Z",
                "sessions": [{"blockOrdinal": 1, "weekday": 2}]
              }],
              "log": [{
                "routineID": "3E7F7E2E-2B47-4C51-9E58-52C1D1F0A0B1",
                "blockOrdinal": 1, "weekday": 2, "exerciseOrder": 0,
                "exerciseID": "barbell-bench-press", "setIndex": 0,
                "isWarmup": false, "isCompleted": true,
                "completedAt": "2023-11-14T22:13:20Z", "reps": 5
              }]
            }
            """.utf8)

        let read = try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
        #expect(read.routines.count == 1)
        #expect(read.routines.first?.document.title == "Autumn strength")
        #expect(read.routines.first?.sessions.first?.completedAt == nil)
        #expect(read.log.count == 1)
        #expect(read.log.first?.reps == 5)
        #expect(read.log.first?.durationSeconds == nil)
    }

    @Test("A lifter with no blocks writes no routines and no log, rather than failing")
    func emptyRecordIsANormalDocument() throws {
        let empty = TrainingSnapshot(catalogVersion: 5, generatedAt: Self.instant)
        let data = try TrainingSnapshot.makeEncoder().encode(empty)
        let read = try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)

        #expect(read.routines.isEmpty)
        #expect(read.log.isEmpty)
    }
}
