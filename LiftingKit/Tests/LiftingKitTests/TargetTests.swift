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
        // range and was shown to the user verbatim. A strictly typed target
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
        // what? Refusing beats defaulting to metres for a user who trains in
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


    @Test("A unit this build has never heard of is refused, never read as reps")
    func anUnknownUnitNeverBecomesReps() {
        // Found by probing, not by reading: `WorkDistance` reports no unit for a
        // word it does not know, so `"40furlongs"` fell through to `RepRange`,
        // which found the 40 and called it forty repetitions. That is a carry
        // landing in the rep column — the exact thing `WorkMeasure` exists to
        // prevent — and it then flows into every volume total the coach reads.
        for text in ["40furlongs", "40 furlongs", "3 laps", "5 blocks"] {
            #expect(Target(shorthand: text) == nil, "\(text)")
        }
    }

    @Test("A rep count may be written with the words that mean reps, and no others")
    func repWordsAreAWhitelist() throws {
        for text in ["8-12 reps", "8-12reps", "5 rep", "5x"] {
            let target = try #require(Target(shorthand: text), "\(text)")
            #expect(target.measure == .repetitions, "\(text)")
        }
    }

    @Test("Bare max is not a prescription this build claims to understand")
    func bareMaxIsRefused() {
        // "max" is as likely to mean the heaviest load as the most reps, and
        // guessing which would be the app deciding how hard to train. "max reps"
        // says it; "max" does not.
        #expect(Target(shorthand: "max") == nil)
        #expect(Target(shorthand: "max reps") == .repetitionsToFailure)
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

/// The two forms a target is written in, and which is for what.
///
/// **A placeholder is not a wire value.** `shorthand` writes the unit because
/// `plan.json` has nowhere else to put it. A field has a unit marker beside it,
/// so drawing the wire form there says it twice — `45s s` for a plank, `40m m`
/// for a carry. Reps hid it: they have no unit in either form.
@Suite("A target's figures, apart from its unit")
struct TargetFiguresTests {

    @Test("A hold's figures carry no unit")
    func aHoldDropsItsUnit() {
        #expect(Target.time(low: 45, high: nil).shorthand == "45s")
        #expect(Target.time(low: 45, high: nil).figures == "45")
        #expect(Target.time(low: 30, high: 60).figures == "30-60")
    }

    @Test("A carry's figures carry no unit, in either unit")
    func aCarryDropsItsUnit() {
        #expect(Target.distance(low: 40, high: nil, unit: .metres).shorthand == "40m")
        #expect(Target.distance(low: 40, high: nil, unit: .metres).figures == "40")
        #expect(Target.distance(low: 40, high: nil, unit: .yards).figures == "40",
                "the unit is the marker's, whichever it is")
    }

    @Test("A count reads the same either way, which is why this went unnoticed")
    func aCountIsUnchanged() {
        #expect(Target.repetitions(low: 8, high: 12).figures == "8-12")
        #expect(Target.repetitions(low: 8, high: 12).shorthand == "8-12")
        #expect(Target.repetitionsToFailure.figures == "AMRAP")
    }

    @Test("The wire form still carries its unit, because the file has nowhere else")
    func theWireIsUntouched() {
        // If this ever stops being true, a plan round-trips a hold as a count.
        #expect(Target(shorthand: Target.time(low: 45, high: nil).shorthand)
            == .time(low: 45, high: nil))
        #expect(Target(shorthand: Target.distance(low: 40, high: nil, unit: .metres).shorthand)
            == .distance(low: 40, high: nil, unit: .metres))
    }
}
