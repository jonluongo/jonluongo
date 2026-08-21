import Foundation
import Testing
@testable import LiftingKit

/// The mark a session carries, on the wire.
///
/// The app owns the set of marks and the coach picks from it, so the name has to
/// survive the journey exactly: written under the key he was told to write it
/// under, read back as what he wrote, and absent when he chose nothing. A round
/// trip alone would not prove it — rename the key on both halves at once and the
/// round trip stays green while every mark becomes invisible to the reader on the
/// other side of the file — so these read the encoded JSON as untyped values and
/// decode documents written by hand.
@Suite("A session's mark on the wire")
struct SessionIconWireTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func exercise() -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press", sets: Array(repeating: PlanDocumentSet(target: Target(shorthand: "5")), count: 3))
    }

    private func decodedPlan(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    // MARK: - Written where he was told to write it

    @Test("A chosen mark is written under `icon`, and read back as itself")
    func iconSurvivesTheWire() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push", icon: .intervals,
                entries: [.exercise(exercise())])])

        let data = try PlanDocument.makeEncoder().encode(document)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try #require(object["sessions"] as? [[String: Any]])
        #expect(days.first?["icon"] as? String == "intervals")

        let read = try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
        #expect(read.sessions.first?.icon == .intervals)
    }

    @Test("A day that chose no mark writes no key, and reads back as none")
    func absentIconWritesNothing() throws {
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push",
                entries: [.exercise(exercise())])])

        let data = try PlanDocument.makeEncoder().encode(document)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let days = try #require(object["sessions"] as? [[String: Any]])

        // Absence stays absence: a `null` would be the app writing "no mark" as
        // a value, which is a different statement from having chosen none.
        #expect(days.first?.keys.contains("icon") == false)
        #expect(try decodedPlan(String(decoding: data, as: UTF8.self))
            .sessions.first?.icon == nil)
    }

    // MARK: - Read the way he writes it

    @Test("A plan written by hand carries its mark in")
    func handWrittenPlanIsRead() throws {
        let plan = try decodedPlan("""
        {
          "version": 6, "id": "9F1E6B1C-0000-4000-8000-000000000001",
          "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{
            "blockOrdinal": 1, "ordinal": 1, "focus": "Conditioning", "icon": "intervals",
            "entries": [{ "exerciseID": "barbell-bench-press",
                          "displayName": "Bench", "sets": [{"target": "5"}] }]
          }]
        }
        """)

        #expect(plan.sessions.first?.icon == .intervals)
    }

    @Test("A mark this build does not know still arrives, so it can be refused by name")
    func unknownMarkSurvivesDecoding() throws {
        // The refusal belongs to the importer, which can only name the offending
        // mark if decoding kept it. Reading it as `nil` here would turn a plan
        // the coach got wrong into a plan that silently drew nothing.
        let plan = try decodedPlan("""
        {
          "version": 6, "id": "9F1E6B1C-0000-4000-8000-000000000002",
          "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{
            "blockOrdinal": 1, "ordinal": 1, "icon": "deadlift",
            "entries": [{ "exerciseID": "barbell-bench-press",
                          "displayName": "Bench", "sets": [{"target": "5"}] }]
          }]
        }
        """)

        let icon = try #require(plan.sessions.first?.icon)
        #expect(icon.rawValue == "deadlift")
        #expect(icon.isKnown == false)
    }

    @Test("A plan written before marks existed still reads")
    func planWithoutTheKeyStillReads() throws {
        let plan = try decodedPlan("""
        {
          "version": 6, "id": "9F1E6B1C-0000-4000-8000-000000000003",
          "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{
            "blockOrdinal": 1, "ordinal": 1, "focus": "Push",
            "entries": [{ "exerciseID": "barbell-bench-press",
                          "displayName": "Bench", "sets": [{"target": "5"}] }]
          }]
        }
        """)

        #expect(plan.sessions.first?.icon == nil)
    }

    @Test("A key this format does not have is still refused, and named")
    func aMisspelledKeyIsRefused() throws {
        // Adding a key must not weaken the rule that guards every other one: a
        // near-miss fails the call rather than being dropped, or the coach is
        // told his choice landed when it did not.
        #expect(throws: DocumentRefusal.self) {
            try decodedPlan("""
            {
              "version": 6, "id": "9F1E6B1C-0000-4000-8000-000000000004",
              "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
              "weeks": [{ "days": [{
                "weekday": 2, "ikon": "strength",
                "exercises": [{ "exerciseID": "barbell-bench-press",
                                "displayName": "Bench", "sets": 3, "repRange": "5" }]
              }]}]
            }
            """)
        }
    }

    // MARK: - And back again

    @Test("The snapshot carries the mark back, in the document it was written in")
    func snapshotCarriesTheMark() throws {
        // The mark travels back inside the plan document rather than in a
        // restatement of it, which is the whole point of carrying the document:
        // there is one place a session's mark is written, and it is the place
        // the coach wrote it.
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push", icon: .strength)])
        let snapshot = TrainingSnapshot(
            catalogVersion: 5, generatedAt: Self.instant,
            routines: [SnapshotRoutine(document: document, startDate: Self.instant)])

        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let routines = try #require(object["routines"] as? [[String: Any]])
        let plan = try #require(routines.first?["document"] as? [String: Any])
        let days = try #require(plan["sessions"] as? [[String: Any]])
        #expect(days.first?["icon"] as? String == "strength")

        let read = try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
        #expect(read.routines.first?.document.sessions.first?.icon == .strength)
    }
}
