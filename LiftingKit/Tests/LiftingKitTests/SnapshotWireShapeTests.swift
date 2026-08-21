import Testing
import Foundation
@testable import LiftingKit

/// The snapshot as JSON: which keys are written, and which are never written.
///
/// **This is about the file, not the API.** `TrainingSnapshotTests` asserts what
/// survives a round trip through Swift; this asserts what a reader on the other
/// end actually finds — because the reader on the other end is a separate
/// process that was compiled at a different time, and a shape that only holds
/// when both sides share a build is not a wire format.
@Suite("Snapshot wire shape")
struct SnapshotWireShapeTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func snapshot(
        sessions: [SnapshotSession] = [], performances: [SnapshotPerformedExercise] = []
    ) -> TrainingSnapshot {
        TrainingSnapshot(
            exportedAt: Self.instant, catalogVersion: 5,
            sessions: sessions, performances: performances)
    }

    private func session() -> SnapshotSession {
        SnapshotSession(
            prescription: PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push",
                entries: [.exercise(PlanDocumentExercise(
                    exerciseID: bench, displayName: "Bench", restSeconds: 180,
                    sets: [PlanDocumentSet(target: .repetitions(low: 5, high: nil))]))]),
            generatedAt: Self.instant)
    }

    private func object(_ snapshot: TrainingSnapshot) throws -> [String: Any] {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func text(_ snapshot: TrainingSnapshot) throws -> String {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        return try #require(String(data: data, encoding: .utf8))
    }

    // MARK: - The keys that exist

    @Test("The envelope states exactly five keys")
    func theEnvelopeIsFiveKeys() throws {
        let written = try object(snapshot(sessions: [session()]))
        #expect(Set(written.keys) == ["version", "exportedAt", "catalogVersion",
                                      "sessions", "performances"])
    }

    @Test("Nothing about the user is written, ever")
    func theUserIsNotOnThisWire() throws {
        // Who he is, what he owns, what he avoids and what he weighs are prose
        // in `ACCOUNT.md`. A field here would be a second place to say them, and
        // the two would drift.
        let written = try text(snapshot(sessions: [session()]))
        for gone in ["profile", "bodyweight", "baselines", "avoidedPatterns",
                     "availableEquipment", "experience", "constraints", "statedAt"] {
            #expect(!written.contains(gone), "\(gone)")
        }
    }

    @Test("A session writes the prescription itself, under one key")
    func aSessionCarriesTheDocument() throws {
        let sessions = try #require(
            try object(snapshot(sessions: [session()]))["sessions"] as? [[String: Any]])
        let first = try #require(sessions.first)

        #expect(first["prescription"] != nil, "one description of a session, not two")
        let prescription = try #require(first["prescription"] as? [String: Any])
        #expect(prescription["blockOrdinal"] as? Int == 1)
        #expect(prescription["focus"] as? String == "Push")
        #expect(prescription["entries"] != nil)
    }

    @Test("A performance holds its sets, rather than the log holding one row per set")
    func performancesNestTheirSets() throws {
        let written = try object(snapshot(performances: [
            SnapshotPerformedExercise(
                exerciseID: bench, occurredAt: Self.instant, blockOrdinal: 1, sessionOrdinal: 1,
                sets: [
                    SnapshotPerformedSet(setIndex: 0, reps: 5, completedAt: Self.instant),
                    SnapshotPerformedSet(setIndex: 1, reps: 5, completedAt: Self.instant),
                ])
        ]))
        let performances = try #require(written["performances"] as? [[String: Any]])
        #expect(performances.count == 1, "one exercise on one day is one row")

        let sets = try #require(performances.first?["sets"] as? [[String: Any]])
        #expect(sets.count == 2)
        #expect(performances.first?["exerciseID"] as? String == "barbell-bench-press")
        #expect(performances.first?["blockOrdinal"] as? Int == 1)
    }

    // MARK: - The keys that are absent rather than null

    @Test("An absent value is absent, not written as null")
    func absenceIsNotWritten() throws {
        // `null` is the app saying "no value" as a value, which is a different
        // statement from having none. A reader cannot tell them apart later.
        let written = try object(snapshot(performances: [
            SnapshotPerformedExercise(
                exerciseID: bench, occurredAt: Self.instant,
                sets: [SnapshotPerformedSet(setIndex: 0, completedAt: Self.instant)])
        ]))
        let performance = try #require((written["performances"] as? [[String: Any]])?.first)

        #expect(performance["userNote"] == nil)
        #expect(performance["blockOrdinal"] == nil, "a stated baseline has no session")

        let set = try #require((performance["sets"] as? [[String: Any]])?.first)
        for absent in ["load", "reps", "durationSeconds", "distance"] {
            #expect(set[absent] == nil, "\(absent)")
        }
    }

    @Test("A working set writes no warm-up marker")
    func aWorkingSetWritesNothing() throws {
        let written = try text(snapshot(performances: [
            SnapshotPerformedExercise(
                exerciseID: bench, occurredAt: Self.instant,
                sets: [SnapshotPerformedSet(setIndex: 0, reps: 5, completedAt: Self.instant)])
        ]))
        #expect(!written.contains("isWarmup"))
    }

    // MARK: - Dates

    @Test("Dates are ISO 8601, so a Mac and a phone cannot disagree about an instant")
    func datesAreISO8601() throws {
        let written = try text(snapshot(sessions: [session()]))
        #expect(written.contains("\"exportedAt\":\"2023-11-14T22:13:20Z\"")
            || written.contains("\"exportedAt\" : \"2023-11-14T22:13:20Z\""))
    }

    // MARK: - Writable by something else

    @Test("A hand-written snapshot reads, so the shape is not a private arrangement")
    func aHandWrittenSnapshotReads() throws {
        let data = Data("""
            {
              "version": 7,
              "exportedAt": "2023-11-14T22:13:20Z",
              "catalogVersion": 5,
              "sessions": [{
                "prescription": {
                  "blockOrdinal": 1, "ordinal": 1, "focus": "Push",
                  "entries": [{"exerciseID": "barbell-bench-press",
                               "displayName": "Bench",
                               "sets": [{"target": "5"}]}]
                },
                "generatedAt": "2023-11-14T22:13:20Z"
              }],
              "performances": [{
                "exerciseID": "barbell-bench-press",
                "occurredAt": "2023-11-14T22:13:20Z",
                "source": "logged",
                "blockOrdinal": 1, "sessionOrdinal": 1,
                "sets": [{"setIndex": 0, "reps": 5,
                          "load": {"value": 225, "unit": "lb"},
                          "completedAt": "2023-11-14T22:13:20Z"}]
              }]
            }
            """.utf8)

        let read = try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)

        #expect(read.sessions.count == 1)
        #expect(read.sessions.first?.prescription.focus == "Push")
        #expect(read.sessions.first?.isFinished == false)
        #expect(read.performances.count == 1)
        #expect(read.performances.first?.sets.first?.reps == 5)
        #expect(read.performances.first?.sets.first?.load == Mass(value: 225, unit: .pounds))
    }

    @Test("An unknown key inside a performance is refused, naming it")
    func anUnknownKeyInsideAPerformanceIsRefused() throws {
        let data = Data("""
            {"version": 7, "exportedAt": "2023-11-14T22:13:20Z", "catalogVersion": 5,
             "performances": [{"exerciseID": "barbell-bench-press",
                               "occurredAt": "2023-11-14T22:13:20Z",
                               "weekday": 2, "sets": []}]}
            """.utf8)
        let error = #expect(throws: DocumentRefusal.self) {
            try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
        }
        #expect(try #require(error?.errorDescription).contains("weekday"))
    }
}
