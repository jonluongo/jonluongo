import Foundation
import Testing
@testable import LiftingKit

@Suite("Plan document")
struct PlanDocumentTests {

    // MARK: - Fixtures

    /// A fixed instant on a second boundary. ISO 8601 encodes whole seconds, so
    /// a date built this way survives a round trip exactly and whole-value
    /// equality is a fair assertion.
    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private let documentID = UUID()

    private func exercise(
        exerciseID: ExerciseID = ExerciseID(rawValue: "barbell-bench-press"),
        sets: Int = 3,
        repRange: String = "5",
        restSeconds: Int? = 180,
        suggestedLoad: Mass? = Mass(value: 100, unit: .kilograms)
    ) -> PlanDocumentExercise {
        PlanDocumentExercise(
            exerciseID: exerciseID, displayName: "Barbell Bench Press",
            sets: sets, repRange: repRange, restSeconds: restSeconds,
            suggestedLoad: suggestedLoad, tempo: "3-0-1-0", notes: "Pause the last rep"
        )
    }

    private func document(
        days: [PlanDocumentDay]? = nil,
        exercises: [PlanDocumentExercise]? = nil
    ) -> PlanDocument {
        PlanDocument(
            id: documentID,
            catalogVersion: 5,
            generatedAt: Self.instant,
            title: "Strength block",
            goal: "Bigger bench",
            durationMinutes: 60,
            notes: "Shoulder is still touchy; keep pressing volume moderate.",
            days: days ?? [
                PlanDocumentDay(
                    weekday: .monday, focus: "Push", durationMinutes: 60,
                    exercises: exercises ?? [exercise()]
                ),
                PlanDocumentDay(
                    weekday: .thursday, focus: "Pull", durationMinutes: 60,
                    exercises: [exercise(
                        exerciseID: ExerciseID(rawValue: "barbell-row"),
                        sets: 4, repRange: "8-12", restSeconds: 90, suggestedLoad: nil
                    )]
                ),
            ]
        )
    }

    private func roundTrip(_ document: PlanDocument) throws -> PlanDocument {
        let data = try PlanDocument.makeEncoder().encode(document)
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    private func decoded(_ json: String) throws -> PlanDocument {
        try PlanDocument.makeDecoder().decode(PlanDocument.self, from: Data(json.utf8))
    }

    private func days(of document: PlanDocument) throws -> [PlanDocumentDay] {
        try #require(document.blocks.first).days
    }

    private func firstExercise(in document: PlanDocument) throws -> PlanDocumentExercise {
        let day = try #require(try days(of: document).first)
        return try #require(day.exercises.first)
    }

    // MARK: - Round trip

    @Test("A version 4 plan says 'weeks' and still imports whole")
    func theOlderSpellingStillReads() throws {
        // Everything written before version 5 calls the routine's blocks
        // `weeks`. Refusing them would strand every plan the coach wrote up to
        // today, and reading around the key would drop the training silently —
        // so it is read, and `blocks` is what gets written back.
        let decoded = try PlanDocument.makeDecoder().decode(
            PlanDocument.self,
            from: Data("""
                {"version": 4, "id": "8B39C4E2-3B22-4E7E-9C7F-9C8E0E2B0A11",
                 "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
                 "weeks": [{"label": "Accumulation", "days": [{"weekday": 2, "exercises": [
                   {"exerciseID": "barbell-bench-press", "displayName": "Barbell Bench Press",
                    "sets": 3, "repRange": "5"}]}]}]}
                """.utf8))

        #expect(decoded.blocks.count == 1)
        #expect(decoded.blocks.first?.label == "Accumulation")
        #expect(decoded.blocks.first?.days.first?.entries.count == 1)

        let rewritten = try JSONSerialization.jsonObject(
            with: PlanDocument.makeEncoder().encode(decoded)) as? [String: Any]
        #expect(rewritten?["blocks"] != nil, "what is written back is this format's word")
        #expect(rewritten?["weeks"] == nil)
    }

    @Test("A plan stating both spellings is refused rather than half read")
    func bothSpellingsAreRefused() {
        #expect(throws: DocumentRefusal.self) {
            try PlanDocument.makeDecoder().decode(
                PlanDocument.self,
                from: Data("""
                    {"version": 5, "id": "8B39C4E2-3B22-4E7E-9C7F-9C8E0E2B0A11",
                     "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z",
                     "blocks": [], "weeks": [{"days": []}]}
                    """.utf8))
        }
    }

    @Test("A full plan document survives encoding and decoding unchanged")
    func fullDocumentRoundTrips() throws {
        let original = document()
        #expect(try roundTrip(original) == original)
    }

    @Test("A document carries its own version, the catalog version, and its identity")
    func carriesVersionsAndIdentity() throws {
        let decoded = try roundTrip(document())
        #expect(decoded.version == PlanDocument.currentVersion)
        #expect(decoded.catalogVersion == 5)
        #expect(decoded.id == documentID)
        #expect(decoded.generatedAt == Self.instant)
    }

    @Test("Block-level facts survive the round trip as written")
    func blockFactsSurvive() throws {
        let decoded = try roundTrip(document())
        #expect(decoded.title == "Strength block")
        #expect(decoded.goal == "Bigger bench")
        #expect(decoded.durationMinutes == 60)
        #expect(decoded.notes == "Shoulder is still touchy; keep pressing volume moderate.")
        #expect(try days(of: decoded).map(\.weekday) == [.monday, .thursday])
        #expect(try days(of: decoded).map(\.focus) == ["Push", "Pull"])
    }

    // MARK: - A block is more than one week

    /// One week at a stated load, so eight of them are eight different weeks
    /// rather than the same week eight times.
    private func week(_ label: String?, load: Double, isDeload: Bool = false)
        -> PlanDocumentBlock {
        PlanDocumentBlock(
            label: label, isDeload: isDeload,
            days: [PlanDocumentDay(
                weekday: .monday, focus: "Lower",
                exercises: [exercise(suggestedLoad: Mass(value: load, unit: .pounds))]
            )]
        )
    }

    private func block(_ blocks: [PlanDocumentBlock]) -> PlanDocument {
        PlanDocument(
            id: documentID, catalogVersion: 5, generatedAt: Self.instant,
            title: "Eight-week block", blocks: blocks
        )
    }

    @Test("An eight-week block round-trips as eight weeks, each with its own days")
    func eightWeeksSurvive() throws {
        let weeks = (0..<8).map { week("Week \($0 + 1)", load: 275 + Double($0) * 10) }
        let decoded = try roundTrip(block(weeks))

        #expect(decoded.blocks.count == 8, "seven weeks must not vanish")
        #expect(decoded.blocks == weeks)

        let loads: [Double?] = decoded.blocks.map {
            $0.days.first?.exercises.first?.suggestedLoad?.value
        }
        let expected: [Double?] = (0..<8).map { 275 + Double($0) * 10 }
        #expect(loads == expected)
    }

    @Test("weekCount is the weeks the block states, never a number that can disagree")
    func weekCountIsDerived() throws {
        #expect(try roundTrip(block((0..<8).map { week("W\($0)", load: 275) })).blockCount == 8)
        #expect(try roundTrip(block([])).blockCount == 0)
        #expect(try roundTrip(document()).blockCount == 1)
    }

    @Test("A deload week arrives with its flag intact")
    func deloadSurvives() throws {
        let decoded = try roundTrip(block([
            week("Accumulation", load: 315), week("Back off", load: 225, isDeload: true),
        ]))

        #expect(decoded.blocks.map(\.isDeload) == [false, true])
        #expect(decoded.blocks.map(\.label) == ["Accumulation", "Back off"])
    }

    @Test("A week the plan did not name has no label rather than an invented one")
    func unnamedWeekHasNoLabel() throws {
        let decoded = try roundTrip(block([week(nil, load: 275)]))

        #expect(decoded.blocks.first?.label == nil)
        #expect(decoded.blocks.first?.isDeload == false)
    }

    // MARK: - Older documents still read

    @Test("A single-week document in the older shape still decodes, as one week")
    func versionOneDocumentStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "title": "Strength block",
          "weekCount": 1,
          "days": [{
            "weekday": 2,
            "focus": "Push",
            "exercises": [{
              "exerciseID": "barbell-bench-press",
              "displayName": "Barbell Bench Press",
              "sets": 5
            }]
          }]
        }
        """
        let decoded = try decoded(json)

        #expect(decoded.version == 1)
        #expect(decoded.blocks.count == 1)
        #expect(decoded.blocks.first?.label == nil)
        #expect(decoded.blocks.first?.isDeload == false)
        #expect(try days(of: decoded).map(\.focus) == ["Push"])
        #expect(try firstExercise(in: decoded).sets == 5)
    }

    @Test("A weekCount that disagrees with the weeks stated is refused, not ignored")
    func statedWeekCountIsChecked() throws {
        // The exact document the audit found: eight weeks declared, one week
        // written, seven silently lost.
        let json = """
        {
          "version": 1, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weekCount": 8,
          "days": [{"weekday": 2}]
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(error?.errorDescription)
        #expect(message.contains("8"))
        #expect(message.contains("1"))
    }

    @Test("A document from a later format is refused as such, naming both versions")
    func laterVersionIsRefused() throws {
        let json = """
        {
          "version": 99, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [], "somethingNewerClaudeSends": true
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }

        // Named as a version, not as an unknown key: the unknown key is what a
        // later format is made of, and complaining about it would misdirect.
        #expect(error == .laterVersion(99, understood: PlanDocument.currentVersion))
        #expect(try #require(error?.errorDescription).contains("99"))
    }

    // MARK: - Refused rather than discarded

    @Test("A key the format does not have is refused, naming the key")
    func unknownKeyIsRefusedByName() throws {
        let json = """
        {
          "version": 2, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "periodizationModel": "block",
          "weeks": []
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }

        #expect(error == .unknownKey("periodizationModel", location: ""))
        #expect(try #require(error?.errorDescription).contains("periodizationModel"))
    }

    @Test("An unknown key deep in the document is refused, and says where it sat")
    func unknownKeyInsideAnExerciseIsRefused() throws {
        let json = """
        {
          "version": 2, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-bench-press", "displayName": "Bench", "sets": 3,
              "dropSets": 2
            }]
          }]}]
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(error?.errorDescription)

        #expect(message.contains("dropSets"))
        #expect(message.contains("weeks → 0 → days → 0 → exercises → 0"))
    }

    @Test("An unknown key in a week is refused too")
    func unknownKeyInsideAWeekIsRefused() throws {
        let json = """
        {
          "version": 2, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"intensityWave": "ascending", "days": []}]
        }
        """
        #expect(throws: DocumentRefusal.unknownKey("intensityWave", location: "weeks → 0")) {
            try decoded(json)
        }
    }

    @Test("Stating both weeks and days is refused rather than one being dropped")
    func weeksAndDaysTogetherAreRefused() throws {
        let json = """
        {
          "version": 2, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "weeks": [{"days": []}],
          "days": [{"weekday": 2}]
        }
        """
        let error = #expect(throws: DocumentRefusal.self) { try decoded(json) }
        let message = try #require(error?.errorDescription)

        #expect(message.contains("weeks"))
        #expect(message.contains("days"))
    }

    // MARK: - Nothing is rewritten

    @Test("An extreme prescription survives the round trip untouched")
    func extremePrescriptionSurvives() throws {
        // 12 sets at 900 seconds' rest is a real prescription — heavy singles
        // with long rests. A document format that quietly normalized it would
        // hand the lifter a plan nobody wrote.
        let decoded = try roundTrip(document(exercises: [
            exercise(sets: 12, restSeconds: 900)
        ]))
        let exercise = try firstExercise(in: decoded)

        #expect(exercise.sets == 12)
        #expect(exercise.restSeconds == 900)
    }

    @Test("An empty rep range stays empty rather than being filled in")
    func emptyRepRangeStaysEmpty() throws {
        let decoded = try roundTrip(document(exercises: [exercise(repRange: "")]))
        #expect(try firstExercise(in: decoded).repRange == "")
        #expect(RepRange(try firstExercise(in: decoded).repRange).isEmpty)
    }

    @Test("An unprescribed rest stays absent rather than becoming a number")
    func absentRestStaysAbsent() throws {
        let decoded = try roundTrip(document(exercises: [exercise(restSeconds: nil)]))
        #expect(try firstExercise(in: decoded).restSeconds == nil)
    }

    @Test("A suggested load keeps the unit it was written in")
    func suggestedLoadKeepsItsUnit() throws {
        let decoded = try roundTrip(document(exercises: [
            exercise(suggestedLoad: Mass(value: 225, unit: .pounds))
        ]))
        let load = try #require(try firstExercise(in: decoded).suggestedLoad)

        #expect(load == Mass(value: 225, unit: .pounds))
        // `Mass` compares exactly on representation, so this fails the moment
        // anything in the pipeline canonicalizes pounds into kilograms.
        #expect(load != Mass(value: 225, unit: .pounds).converted(to: .kilograms))
    }

    @Test("A movement with no suggested load carries none rather than a zero")
    func absentLoadStaysAbsent() throws {
        let decoded = try roundTrip(document(exercises: [exercise(suggestedLoad: nil)]))
        #expect(try firstExercise(in: decoded).suggestedLoad == nil)
    }

    // MARK: - Identities the document does not judge

    @Test("An exercise ID this build's catalog does not know round-trips intact")
    func unknownExerciseIDRoundTrips() throws {
        // The document layer records; only the importer validates against the
        // catalog. An ID that fails validation must still arrive verbatim, or
        // the error could not name it.
        let unknown = ExerciseID(rawValue: "zercher-good-morning")
        let decoded = try roundTrip(document(exercises: [exercise(exerciseID: unknown)]))
        #expect(try firstExercise(in: decoded).exerciseID == unknown)
    }

    @Test("Exercise IDs are canonicalized on decode so casing never fragments identity")
    func exerciseIDIsCanonicalizedOnDecode() throws {
        let json = """
        {
          "version": 1,
          "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "  Barbell-Bench-Press ",
              "displayName": "Barbell Bench Press",
              "sets": 3
            }]
          }]
        }
        """
        let decoded = try PlanDocument.makeDecoder()
            .decode(PlanDocument.self, from: Data(json.utf8))
        #expect(try firstExercise(in: decoded).exerciseID
            == ExerciseID(rawValue: "barbell-bench-press"))
    }

    // MARK: - Absence is normal

    @Test("A rest day — a day with no exercises — is a valid document, not an error")
    func restDayIsValid() throws {
        let restDay = PlanDocumentDay(
            weekday: .sunday, focus: "Rest", durationMinutes: nil, exercises: []
        )
        let decoded = try roundTrip(document(days: [restDay]))
        #expect(try days(of: decoded).count == 1)
        #expect(try days(of: decoded).first?.exercises.isEmpty == true)
    }

    @Test("A document that says nothing about length or focus decodes rather than failing")
    func absentFieldsDecodeAsAbsent() throws {
        let json = """
        {
          "version": 1,
          "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z",
          "days": [{
            "weekday": 2,
            "exercises": [{
              "exerciseID": "barbell-bench-press",
              "displayName": "Barbell Bench Press",
              "sets": 5
            }]
          }]
        }
        """
        let decoded = try PlanDocument.makeDecoder()
            .decode(PlanDocument.self, from: Data(json.utf8))

        #expect(decoded.title == "")
        #expect(decoded.goal == "")
        #expect(decoded.durationMinutes == nil)
        #expect(decoded.notes == nil)
        #expect(try days(of: decoded).first?.focus == "")
        #expect(try days(of: decoded).first?.durationMinutes == nil)

        let exercise = try firstExercise(in: decoded)
        #expect(exercise.sets == 5)
        #expect(exercise.repRange == "")
        #expect(exercise.restSeconds == nil)
        #expect(exercise.suggestedLoad == nil)
        #expect(exercise.tempo == nil)
        #expect(exercise.notes == nil)
    }

    @Test("A document with no weeks at all decodes as empty rather than failing")
    func absentWeeksDecodeAsEmpty() throws {
        let json = """
        {
          "version": 1, "catalogVersion": 5,
          "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z"
        }
        """
        let decoded = try decoded(json)
        #expect(decoded.blocks.isEmpty)
        #expect(decoded.blockCount == 0)
        #expect(decoded.generatedAt == Self.instant)
    }

    @Test("A document missing its identity or version does not decode at all")
    func requiredFieldsAreRequired() {
        let withoutID = """
        {"version": 1, "catalogVersion": 5, "generatedAt": "2023-11-14T22:13:20Z"}
        """
        #expect(throws: (any Error).self) {
            try PlanDocument.makeDecoder()
                .decode(PlanDocument.self, from: Data(withoutID.utf8))
        }

        let withoutCatalogVersion = """
        {
          "version": 1, "id": "0FD1FF67-1C2F-4E45-9BD8-9F1E6A5F0A21",
          "generatedAt": "2023-11-14T22:13:20Z"
        }
        """
        #expect(throws: (any Error).self) {
            try PlanDocument.makeDecoder()
                .decode(PlanDocument.self, from: Data(withoutCatalogVersion.utf8))
        }
    }

    // MARK: - The encoder both clients share

    @Test("The document encoder writes ISO 8601 dates, as the snapshot encoder does")
    func encoderWritesISO8601Dates() throws {
        let data = try PlanDocument.makeEncoder().encode(document())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("2023-11-14T22:13:20Z"))
    }
}
