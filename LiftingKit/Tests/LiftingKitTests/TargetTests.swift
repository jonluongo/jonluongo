import Testing
import Foundation
@testable import LiftingKit

/// What one prescribed set asks for, read once and never re-guessed.
///
/// **The defect this closes.** A forty-metre sled push was stored as the text
/// `"40m"` in a field named `repRange`, and every reader rescanned it to find
/// out what it meant. The record side has carried `reps`, `durationSeconds` and
/// `distance` as separate fields for exactly this reason; the prescription side
/// had one string that meant whichever. These tests are about the prescription
/// side gaining the same guarantee.
///
/// **The rule under test is refusal.** A target this build cannot read is
/// refused with the text quoted, never stored as prose to be interpreted later.
/// That is the difference between a target and a note.
@Suite("What a prescribed set asks for")
struct TargetTests {

    // MARK: - Reading the three measures

    @Test("A rep range is counted, and keeps both of its bounds")
    func aRepRangeIsCounted() throws {
        let target = try #require(Target(shorthand: "8-12"))
        #expect(target == .repetitions(low: 8, high: 12))
        #expect(target.measure == .repetitions)
    }

    @Test("A single count is a single count, not a range of one")
    func aSingleCountKeepsNoUpperBound() throws {
        // `5` and `5-5` are the same instruction, and storing the second would
        // put a bound in the record that nobody stated.
        let target = try #require(Target(shorthand: "5"))
        #expect(target == .repetitions(low: 5, high: nil))
    }

    @Test("A hold is held, in seconds")
    func aHoldIsTimed() throws {
        let target = try #require(Target(shorthand: "45s"))
        #expect(target == .time(low: 45, high: nil))
        #expect(target.measure == .time)
    }

    @Test("A carry keeps the unit it was prescribed in")
    func aCarryKeepsItsUnit() throws {
        let target = try #require(Target(shorthand: "40m"))
        #expect(target == .distance(low: 40, high: nil, unit: .metres))
        #expect(target.measure == .distance(.metres))
    }

    @Test("Forty yards is not forty metres, and nothing converts one to the other")
    func aCarryIsNeverConverted() throws {
        let yards = try #require(Target(shorthand: "40yd"))
        let metres = try #require(Target(shorthand: "40m"))
        #expect(yards != metres)
        #expect(yards.measure != metres.measure)
    }

    @Test("As many as possible is a prescription, not an unreadable one")
    func toFailureIsItsOwnCase() throws {
        // Before this type, `"AMRAP"` read as `.repetitions` with an empty
        // range and was shown to the lifter verbatim. A strictly typed target
        // that refused it would take a prescription coaches actually write out
        // of the vocabulary, so it is stated rather than lost.
        for text in ["AMRAP", "amrap", "to failure", "max reps"] {
            #expect(Target(shorthand: text) == .repetitionsToFailure, "\(text)")
        }
        #expect(Target.repetitionsToFailure.measure == .repetitions,
                "it is still counted, and still logged in reps")
    }

    // MARK: - Refusal

    @Test("A target this build cannot read is refused, not stored as text")
    func anUnreadableTargetIsRefused() {
        for text in ["", "   ", "as prescribed", "heavy", "?"] {
            #expect(Target(shorthand: text) == nil, "\(text)")
        }
    }

    @Test("A refused target is refused at decode, so nothing downstream re-guesses it")
    func decodingRefusesUnreadableShorthand() {
        let json = Data(#""heavy""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Target.self, from: json)
        }
    }

    @Test("The refusal names what it could not read")
    func theRefusalQuotesTheText() {
        do {
            _ = try JSONDecoder().decode(Target.self, from: Data(#""heavy""#.utf8))
            Issue.record("expected a refusal")
        } catch {
            #expect("\(error)".contains("heavy"),
                    "a refusal that does not say what was refused cannot be acted on")
        }
    }

    // MARK: - The wire

    @Test("Every case round-trips through its typed form")
    func everyCaseRoundTrips() throws {
        let cases: [Target] = [
            .repetitions(low: 8, high: 12),
            .repetitions(low: 5, high: nil),
            .repetitionsToFailure,
            .time(low: 30, high: 45),
            .time(low: 45, high: nil),
            .distance(low: 40, high: nil, unit: .metres),
            .distance(low: 20, high: 30, unit: .yards),
        ]
        for target in cases {
            let data = try JSONEncoder().encode(target)
            #expect(try JSONDecoder().decode(Target.self, from: data) == target, "\(target)")
        }
    }

    @Test("Shorthand is accepted on the way in and never written on the way out")
    func shorthandDecodesButNeverEncodes() throws {
        // Parsing happens exactly once, at the boundary. A hand-written plan
        // still works; what the store holds is typed either way.
        let decoded = try JSONDecoder().decode(Target.self, from: Data(#""8-12""#.utf8))
        #expect(decoded == .repetitions(low: 8, high: 12))

        let written = try JSONEncoder().encode(decoded)
        let object = try #require(
            try JSONSerialization.jsonObject(with: written) as? [String: Any])
        #expect(object["measure"] as? String == "reps")
        #expect(object["low"] as? Int == 8)
        #expect(object["high"] as? Int == 12)
    }

    @Test("A unit this build has never heard of survives the round trip")
    func anUnknownUnitIsCarried() throws {
        // `DistanceUnit` is an extensible taxonomy: an unknown value round-trips
        // intact rather than being dropped or crashing.
        let target = Target.distance(low: 2, high: nil, unit: DistanceUnit(rawValue: "furlongs"))
        let data = try JSONEncoder().encode(target)
        #expect(try JSONDecoder().decode(Target.self, from: data) == target)
    }

    @Test("A typed object missing what its measure needs is refused")
    func anIncompleteTypedTargetIsRefused() {
        // `distance` without a unit is a number nobody can act on: forty of
        // what? Refusing beats defaulting to metres for a lifter who trains in
        // yards.
        let cases = [
            #"{"measure":"distance","low":40}"#,
            #"{"measure":"reps"}"#,
            #"{"measure":"furlongs","low":2}"#,
        ]
        for json in cases {
            #expect(throws: DecodingError.self, "\(json)") {
                try JSONDecoder().decode(Target.self, from: Data(json.utf8))
            }
        }
    }

    // MARK: - What it says on screen

    @Test("A target is written back the way a coach would write it")
    func shorthandReadsBack() {
        #expect(Target.repetitions(low: 8, high: 12).shorthand == "8-12")
        #expect(Target.repetitions(low: 5, high: nil).shorthand == "5")
        #expect(Target.repetitionsToFailure.shorthand == "AMRAP")
        #expect(Target.time(low: 45, high: nil).shorthand == "45s")
        #expect(Target.time(low: 30, high: 45).shorthand == "30-45s")
        #expect(Target.distance(low: 40, high: nil, unit: .metres).shorthand == "40m")
    }

    @Test("What a coach writes reads back as the same target")
    func shorthandSurvivesItsOwnRoundTrip() throws {
        for text in ["8-12", "5", "AMRAP", "45s", "30-45s", "40m", "20-30yd"] {
            let target = try #require(Target(shorthand: text), "\(text)")
            #expect(Target(shorthand: target.shorthand) == target, "\(text)")
        }
    }
}
