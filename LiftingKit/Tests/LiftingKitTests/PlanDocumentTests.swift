import Testing
import Foundation
@testable import LiftingKit

/// The plan document: what it carries, and what it refuses.
///
/// **Half of the suite this replaced tested a shape that no longer exists.** A
/// plan used to be a routine of named blocks of days keyed by weekday, and the
/// tests that went with it guarded `weekCount` against the weeks actually
/// stated, the three spellings of the same list — `blocks`, `weeks`, a bare
/// `days` — the deload flag, and the label a week might not have. Version 6 is
/// a flat list of sessions, each saying which block it belongs to and where it
/// sits, so none of those questions can be asked. There is no count to
/// disagree with the content, which is what once let seven weeks of a declared
/// eight-week block vanish.
///
/// What survives is what the format is for: a prescription reaches the store
/// exactly as it was written, and anything this build cannot read is refused
/// whole with the reason named.
@Suite("The plan document")
struct PlanDocumentTests {

    private let squat = ExerciseID(rawValue: "barbell-back-squat")
    private let generated = Date(timeIntervalSince1970: 1_700_000_000)

    private func exercise(
        _ id: ExerciseID? = nil, rest: Int? = 180, note: String? = nil,
        sets: [PlanDocumentSet] = [PlanDocumentSet(target: .repetitions(low: 5, high: nil))]
    ) -> PlanDocumentEntry {
        .exercise(PlanDocumentExercise(
            exerciseID: id ?? squat, displayName: "Squat",
            restSeconds: rest, coachNote: note, sets: sets))
    }

    private func document(
        sessions: [PlanDocumentSession], id: UUID = UUID()
    ) -> PlanDocument {
        PlanDocument(
            id: id, catalogVersion: 5, generatedAt: generated, sessions: sessions)
    }

    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument {
        let data = try PlanDocument.makeEncoder().encode(document)
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    private func decoded(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    // MARK: - What it carries

    @Test("A document carries its own version, the catalog version, and its identity")
    func identityIsCarried() throws {
        let id = UUID()
        let decoded = try roundTrip(document(
            sessions: [PlanDocumentSession(blockOrdinal: 1, ordinal: 1)], id: id))

        #expect(decoded.version == PlanDocument.currentVersion)
        #expect(decoded.version == 6)
        #expect(decoded.id == id)
        #expect(decoded.catalogVersion == 5)
        #expect(decoded.generatedAt == generated)
    }

    @Test("Every session of the block survives")
    func everySessionSurvives() throws {
        // Six sessions in one block. The count is never stated, so nothing can
        // claim a length the document does not deliver.
        let sessions = (1...6).map { ordinal in
            PlanDocumentSession(
                blockOrdinal: 3, ordinal: ordinal, focus: "Day \(ordinal)",
                entries: [exercise()])
        }
        let decoded = try roundTrip(document(sessions: sessions))

        #expect(decoded.sessions.count == 6)
        #expect(decoded.blockOrdinals == [3], "blocks run continuously; they do not restart")
        #expect(decoded.sessions(inBlock: 3).map(\.ordinal) == [1, 2, 3, 4, 5, 6])
    }

    @Test("A session says where it sits, so the order it arrives in carries no meaning")
    func sessionsAreOrderedByWhatTheyState() throws {
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(blockOrdinal: 2, ordinal: 3),
            PlanDocumentSession(blockOrdinal: 2, ordinal: 1),
            PlanDocumentSession(blockOrdinal: 2, ordinal: 2),
        ]))
        #expect(decoded.sessions(inBlock: 2).map(\.ordinal) == [1, 2, 3])
        #expect(decoded.blockOrdinals == [2])
    }

    @Test("A plan stating more than one block is refused, naming them")
    func severalBlocksAreRefused() throws {
        // **The coach writes a block at a time, and the routine grows.** A
        // document carrying three blocks is a month written in advance of the
        // evidence: he is meant to read what happened in the block just
        // finished before prescribing the next, and that reading is the whole
        // of what he is for. Refused rather than trimmed to the first block —
        // taking part of a document in tells the writer it landed when most of
        // it did not.
        let error = #expect(throws: DocumentRefusal.self) {
            try roundTrip(document(sessions: [
                PlanDocumentSession(blockOrdinal: 1, ordinal: 1),
                PlanDocumentSession(blockOrdinal: 2, ordinal: 1),
            ]))
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("one block"))
        #expect(message.contains("1, 2"), "it names what it found")
        #expect(message.contains("Nothing was taken in"))
    }

    @Test("A plan with no sessions at all is not a several-blocks refusal")
    func anEmptyPlanIsAllowedThrough() throws {
        // Zero blocks is not two. What an empty plan means is the importer's
        // question, not the format's.
        #expect(try roundTrip(document(sessions: [])).sessions.isEmpty)
    }

    @Test("A session's own facts survive as written")
    func aSessionsFactsSurvive() throws {
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(
                blockOrdinal: 3, ordinal: 2, focus: "Push", icon: .strength, entries: [exercise()])
        ]))
        let session = try #require(decoded.sessions.first)

        #expect(session.blockOrdinal == 3)
        #expect(session.ordinal == 2)
        #expect(session.focus == "Push")
        #expect(session.icon == .strength)
    }

    @Test("A session the coach named nothing has no name rather than an invented one")
    func anUnnamedSessionStaysUnnamed() throws {
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(blockOrdinal: 1, ordinal: 1)
        ]))
        let session = try #require(decoded.sessions.first)
        #expect(session.focus.isEmpty)
        #expect(session.icon == nil, "a mark the app chose would be the app deciding")
    }

    @Test("An unprescribed rest stays absent rather than becoming a number")
    func anAbsentRestStaysAbsent() throws {
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(blockOrdinal: 1, ordinal: 1, entries: [exercise(rest: nil)])
        ]))
        let exercise = try #require(decoded.sessions.first?.entries.first?.exercises.first)
        #expect(exercise.restSeconds == nil)
    }

    @Test("A rest day is a session with no entries, not an error")
    func aRestDayIsValid() throws {
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(blockOrdinal: 1, ordinal: 1, focus: "Rest")
        ]))
        #expect(try #require(decoded.sessions.first).entries.isEmpty)
    }

    @Test("A document stating no sessions decodes as empty rather than failing")
    func anEmptyDocumentDecodes() throws {
        #expect(try roundTrip(document(sessions: [])).sessions.isEmpty)
        #expect(try decoded("""
            {"version": 6, "catalogVersion": 5,
             "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
             "generatedAt": "2023-11-14T22:13:20Z"}
            """).sessions.isEmpty)
    }

    // MARK: - Identity is never guessed at

    @Test("An exercise ID this build's catalog does not know round-trips intact")
    func anUnknownExerciseIDSurvives() throws {
        // Refusing an unknown ID is the importer's job, and doing it here as
        // well would report the wrong failure. The document carries what it was
        // given.
        let stranger = ExerciseID(rawValue: "zercher-good-morning")
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(blockOrdinal: 1, ordinal: 1, entries: [exercise(stranger)])
        ]))
        #expect(decoded.sessions.first?.entries.first?.exercises.first?.exerciseID == stranger)
    }

    @Test("Exercise IDs are canonicalized on decode so casing never fragments identity")
    func exerciseIDsAreCanonicalized() throws {
        let decoded = try decoded("""
            {"version": 6, "catalogVersion": 5,
             "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
             "generatedAt": "2023-11-14T22:13:20Z",
             "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
               {"exerciseID": "Barbell-Back-Squat", "sets": []}]}]}
            """)
        #expect(decoded.sessions.first?.entries.first?.exercises.first?.exerciseID == squat,
                "one lift with two spellings is two histories")
    }

    // MARK: - Refusal

    @Test("A document from a later format is refused, naming both versions")
    func aLaterFormatIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 99, "catalogVersion": 5,
                 "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                 "generatedAt": "2023-11-14T22:13:20Z", "somethingNew": true}
                """)
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("99"))
        #expect(message.contains("6"))
        #expect(!message.contains("somethingNew"),
                "the version is judged before any key is held against the document")
    }

    @Test("A document from an earlier format is refused too, and says why")
    func anEarlierFormatIsRefused() throws {
        // Version 6 breaks the archive rule once, at the reset: versions 1–5
        // stated routines of named blocks keyed by weekday, and reading one
        // would mean inventing block ordinals and discarding weekdays.
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 5, "catalogVersion": 5,
                 "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                 "generatedAt": "2023-11-14T22:13:20Z", "blocks": []}
                """)
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("5"))
        #expect(message.contains("6"))
        #expect(!message.contains("blocks"), "the version is judged first, as with a later one")
    }

    @Test("A key the format does not have is refused, naming the key")
    func anUnknownTopLevelKeyIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 6, "catalogVersion": 5,
                 "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                 "generatedAt": "2023-11-14T22:13:20Z", "goal": "Get strong"}
                """)
        }
        #expect(try #require(error?.errorDescription).contains("goal"))
    }

    @Test("An unknown key deep in the document is refused, and says where it sat")
    func anUnknownKeyDeepInsideIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 6, "catalogVersion": 5,
                 "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                 "generatedAt": "2023-11-14T22:13:20Z",
                 "sessions": [{"blockOrdinal": 1, "ordinal": 1, "entries": [
                   {"exerciseID": "barbell-back-squat", "tempo": "3010", "sets": []}]}]}
                """)
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("tempo"), "tempo folded into the coach's note")
        #expect(message.contains("sessions → 0 → entries → 0"))
    }

    @Test("An unknown key in a session is refused too")
    func anUnknownKeyInASessionIsRefused() throws {
        let error = #expect(throws: DocumentRefusal.self) {
            try decoded("""
                {"version": 6, "catalogVersion": 5,
                 "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                 "generatedAt": "2023-11-14T22:13:20Z",
                 "sessions": [{"blockOrdinal": 1, "ordinal": 1, "weekday": 2}]}
                """)
        }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("weekday"), "when he trains is not something a plan states")
        #expect(message.contains("sessions → 0"))
    }

    @Test("A session that does not say where it sits does not decode at all")
    func aSessionMustSayWhereItSits() {
        for missing in [#"{"ordinal": 1}"#, #"{"blockOrdinal": 1}"#] {
            #expect(throws: (any Error).self, "\(missing)") {
                try decoded("""
                    {"version": 6, "catalogVersion": 5,
                     "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
                     "generatedAt": "2023-11-14T22:13:20Z", "sessions": [\(missing)]}
                    """)
            }
        }
    }

    @Test("A document missing its identity or version does not decode at all")
    func theRequiredKeysAreRequired() {
        let cases = [
            #"{"catalogVersion": 5, "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21", "generatedAt": "2023-11-14T22:13:20Z"}"#,
            #"{"version": 6, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z"}"#,
            #"{"version": 6, "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21", "generatedAt": "2023-11-14T22:13:20Z"}"#,
        ]
        for json in cases {
            #expect(throws: (any Error).self, "\(json)") { try decoded(json) }
        }
    }

    // MARK: - The wire itself

    @Test("The document encoder writes ISO 8601 dates, as the snapshot encoder does")
    func datesAreWrittenAsISO8601() throws {
        let data = try PlanDocument.makeEncoder().encode(
            document(sessions: [PlanDocumentSession(blockOrdinal: 1, ordinal: 1)]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("2023-11-14T22:13:20Z"),
                "a Mac and a phone must not disagree about an instant")
    }

    @Test("An extreme prescription survives the round trip untouched")
    func nothingIsClampedOnTheWay() throws {
        // Nothing in this format is a suggestion to be adjusted. Twenty sets of
        // one rep with an hour's rest is a prescription somebody may mean.
        let sets = Array(
            repeating: PlanDocumentSet(
                target: .repetitions(low: 1, high: nil),
                load: Mass(value: 405, unit: .pounds)),
            count: 20)
        let decoded = try roundTrip(document(sessions: [
            PlanDocumentSession(
                blockOrdinal: 1, ordinal: 1, entries: [exercise(rest: 3600, sets: sets)])
        ]))
        let exercise = try #require(decoded.sessions.first?.entries.first?.exercises.first)

        #expect(exercise.sets.count == 20)
        #expect(exercise.restSeconds == 3600)
        #expect(exercise.sets.allSatisfy { $0.load?.value == 405 })
    }
}
