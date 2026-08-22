import Foundation
import Testing
@testable import LiftingKit

/// What a day says when its exercises are grouped, and what it refuses to say.
///
/// The group is the unit of work — two or more movements performed as rounds,
/// resting after the round. These pin the two properties the shape was chosen
/// for: a half-formed grouping cannot be written, and a day of ungrouped
/// exercises is byte for byte the day this format has always written.
@Suite("A day whose exercises are grouped")
struct PlanDocumentGroupTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)

    private func exercise(
        _ id: String, sets: Int = 3, repRange: String = "12-15", restSeconds: Int? = nil
    ) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: ExerciseID(rawValue: id), displayName: id,
            restSeconds: restSeconds,
            sets: Array(
                repeating: PlanDocumentSet(target: Target(shorthand: repRange)),
                count: sets)
        )
    }

    private func document(entries: [PlanDocumentEntry]) -> PlanDocument {
        PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            sessions: [PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, focus: "Push", entries: entries)]
        )
    }

    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument {
        let data = try PlanDocument.makeEncoder().encode(document)
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    private func decoded(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    /// A day stating one ungrouped exercise, then a superset of two.
    private func mixedDayJSON(groupRest: String = "\"restSeconds\": 90,") -> String {
        """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{
            "blockOrdinal": 1, "ordinal": 1,
            "entries": [
              {"exerciseID": "barbell-bench-press", "displayName": "Bench",
               "restSeconds": 180, "sets": [{"target": "6-8"}]},
              {\(groupRest)
               "group": [
                 {"exerciseID": "dumbbell-fly", "displayName": "Fly",
                  "sets": [{"target": "12-15"}]},
                 {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown",
                  "sets": [{"target": "12-15"}]}
               ]}
            ]
          }]
        }
        """
    }

    private func day(of document: PlanDocument) throws -> PlanDocumentSession {
        try #require(document.sessions.first)
    }

    // MARK: - The shape

    @Test("A day reads a group as one entry holding its exercises in order")
    func groupDecodesAsOneEntry() throws {
        let day = try day(of: try decoded(mixedDayJSON()))

        #expect(day.entries.count == 2)
        #expect(day.entries.first?.group == nil, "the first entry is one exercise")
        let group = try #require(day.entries.last?.group)
        #expect(group.exercises.map(\.exerciseID.rawValue) == ["dumbbell-fly", "cable-rope-pushdown"])
        #expect(group.restSeconds == 90)
    }

    @Test("A day's exercises read flat, in order, whatever they were grouped into")
    func exercisesFlattenInOrder() throws {
        let day = try day(of: try decoded(mixedDayJSON()))

        #expect(day.exercises.map(\.exerciseID.rawValue)
            == ["barbell-bench-press", "dumbbell-fly", "cable-rope-pushdown"])
    }

    @Test("A group of three is a group of three; nothing here is special-cased to pairs")
    func triSetIsJustAGroup() throws {
        let group = PlanDocumentGroup(
            exercises: [exercise("a"), exercise("b"), exercise("c")], restSeconds: 120)
        let day = try day(of: try roundTrip(document(entries: [.group(group)])))

        #expect(day.entries.last?.group?.exercises.count == 3)
        #expect(day.exercises.count == 3)
    }

    @Test("A group that prescribes no rest states none rather than zero")
    func absentGroupRestStaysAbsent() throws {
        let day = try day(of: try decoded(mixedDayJSON(groupRest: "")))
        #expect(day.entries.last?.group?.restSeconds == nil)
    }

    // MARK: - Round trip

    @Test("A grouped day survives encoding and decoding unchanged")
    func groupedDayRoundTrips() throws {
        let original = document(entries: [
            .exercise(exercise("barbell-bench-press", sets: 4, repRange: "6-8", restSeconds: 180)),
            .group(PlanDocumentGroup(
                exercises: [exercise("dumbbell-fly"), exercise("cable-rope-pushdown")],
                restSeconds: 90)),
        ])
        #expect(try roundTrip(original) == original)
    }

    @Test("A group is written under 'group' with its rest beside it")
    func groupIsWrittenAsAGroup() throws {
        let data = try PlanDocument.makeEncoder().encode(
            document(entries: [.group(PlanDocumentGroup(
                exercises: [exercise("dumbbell-fly"), exercise("cable-rope-pushdown")],
                restSeconds: 90))]))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"group\""))
        #expect(text.contains("\"restSeconds\" : 90"))
    }

    // MARK: - The common case does not pay for the rare one

    @Test("A day of ungrouped exercises writes exactly what it always wrote")
    func ungroupedDayIsUnchanged() throws {
        let data = try PlanDocument.makeEncoder().encode(
            document(entries: [.exercise(exercise("barbell-bench-press", restSeconds: 180))]))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(!text.contains("\"group\""), "nothing about grouping appears on an ungrouped day")
        #expect(text.contains("\"entries\""), "a session states entries, grouped or not")
    }

    @Test("The format states version 6, and a later one is still refused whole")
    func versionIsSixAndSkewIsRefused() {
        #expect(PlanDocument.currentVersion == 6)
        #expect(throws: DocumentRefusal.versionMismatch(7, understood: 6)) {
            try decoded("""
            {"version": 7, "catalogVersion": 5,
             "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
             "generatedAt": "2023-11-14T22:13:20Z"}
            """)
        }
    }

    // MARK: - What cannot be written at all

    @Test("An exercise inside a group cannot carry its own rest, and is refused by name")
    func restInsideAGroupIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"restSeconds": 90, "group": [
              {"exerciseID": "dumbbell-fly", "displayName": "Fly", "sets": [{}],
               "restSeconds": 45},
              {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown", "sets": [{}]}
            ]}
          ]}]
        }
        """
        let refusal = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(refusal?.message)
        #expect(message.contains("'restSeconds'"))
        #expect(message.contains("Fly"), "the refusal names the exercise that stated it")
        #expect(message.contains("after the round"))
        #expect(message.contains("Nothing was taken in"))
    }

    @Test("An exercise with no display name is named by its ID, not by nothing")
    func aRefusalNamesTheExerciseEvenWithoutADisplayName() throws {
        // **The ordinary case.** `displayName` is optional — the catalog fills
        // it in at both ends — so the coach usually sends only an ID. Reading
        // the name straight produced *a rest on '' alone*: a refusal that named
        // nothing, about a group he would then have to find by hand. Its
        // sibling above always sent a name, which is how this survived.
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"restSeconds": 90, "group": [
              {"exerciseID": "dumbbell-fly", "sets": [{}], "restSeconds": 45},
              {"exerciseID": "cable-rope-pushdown", "sets": [{}]}
            ]}
          ]}]
        }
        """
        let refusal = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(refusal?.message)
        #expect(message.contains("dumbbell-fly"), "named by its ID: \(message)")
        #expect(!message.contains("''"), "and never by nothing: \(message)")
    }

    @Test("A group of one is not a group, and is refused as such")
    func groupOfOneIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"restSeconds": 90, "group": [
              {"exerciseID": "dumbbell-fly", "displayName": "Fly", "sets": [{}]}
            ]}
          ]}]
        }
        """
        let refusal = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(refusal?.message)
        #expect(message.contains("two or more"))
        #expect(message.contains("states 1"))
        #expect(message.contains("Nothing was taken in"))
    }

    @Test("An empty group is refused the same way")
    func emptyGroupIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [{"group": []}]}]
        }
        """
        #expect(throws: DocumentRefusal.self) { try decoded(json) }
    }

    @Test("A key a group does not have is refused with the key named")
    func unknownKeyOnAGroupIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"group": [
              {"exerciseID": "dumbbell-fly", "displayName": "Fly", "sets": [{}]},
              {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown", "sets": [{}]}
            ], "rounds": 3}
          ]}]
        }
        """
        let refusal = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(refusal?.message)
        #expect(message.contains("'rounds'"))
    }

    @Test("A key an exercise inside a group does not have is refused with the key named")
    func unknownKeyInsideAMemberIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"group": [
              {"exerciseID": "dumbbell-fly", "displayName": "Fly", "sets": [{}], "superset": true},
              {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown", "sets": [{}]}
            ]}
          ]}]
        }
        """
        let refusal = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(refusal?.message)
        #expect(message.contains("'superset'"))
    }

    @Test("A group inside a group is refused rather than nested")
    func nestedGroupIsRefused() throws {
        let json = """
        {
          "version": 6, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
            {"group": [
              {"group": [
                {"exerciseID": "dumbbell-fly", "displayName": "Fly", "sets": [{}]},
                {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown", "sets": [{}]}
              ]},
              {"exerciseID": "cable-rope-pushdown", "displayName": "Pushdown", "sets": [{}]}
            ]}
          ]}]
        }
        """
        #expect(throws: DocumentRefusal.self) { try decoded(json) }
    }
}
