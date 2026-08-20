import Testing
@testable import LiftingKit

/// The one vocabulary the three readers share, and the rule that keeps them
/// from claiming the same target.
///
/// **Why this is worth a suite of its own.** A set is counted, held, or carried,
/// and no two of them are the same number. A hold once landed in the rep column,
/// which is a number nobody performed propagating into every report that
/// follows — and the thing standing between that and the log is `TargetUnits`
/// holding one vocabulary, plus the fixed order the readers claim text in.
/// Neither had a test naming it.
@Suite("The shared unit vocabulary")
struct TargetUnitsTests {

    /// Targets a coach could plausibly write, with what each one measures.
    private static let targets: [(text: String, measure: WorkMeasure)] = [
        ("5", .repetitions),
        ("8-12", .repetitions),
        ("AMRAP", .repetitions),
        ("30 seconds", .time),
        ("45 s", .time),
        ("1:30", .time),
        ("2 min", .time),
        ("40 metres", .distance(.metres)),
        ("40 m", .distance(.metres)),
        ("20 yd", .distance(.yards)),
        ("100 ft", .distance(.feet)),
    ]

    // MARK: - No target is ever read as two things

    @Test("Exactly one of the three readers claims any target", arguments: targets)
    func onlyOneReaderClaimsATarget(_ target: (text: String, measure: WorkMeasure)) {
        // The claims, asked directly rather than through `WorkMeasure`, so this
        // fails if two readers both say yes even where the fixed order happens
        // to hide it.
        let timed = WorkDuration(target.text).isTimed
        let carried = WorkDistance(target.text).isDistance
        let counted = !RepRange(target.text).isEmpty

        #expect([timed, carried, counted].filter { $0 }.count <= 1,
            "\(target.text) was claimed by more than one reader")
    }

    @Test("What each target measures is the one answer everything binds to",
        arguments: targets)
    func measureMatchesTheClaim(_ target: (text: String, measure: WorkMeasure)) {
        #expect(WorkMeasure(target.text) == target.measure)
    }

    // MARK: - The order the readers claim in

    @Test("A rep range with a hold mentioned beside it stays repetitions")
    func aMentionedHoldDoesNotStealARepRange() {
        // The timing words are read only when no rep count could be found, so
        // an instruction about how to perform the reps does not turn the set
        // into a hold. This is the exact shape of the bug that put seconds in
        // the rep column.
        #expect(WorkMeasure("8-12, hold at the top") == .repetitions)
        #expect(RepRange("8-12, hold at the top").isEmpty == false)
    }

    @Test("A hold with no number is still a hold")
    func anUnnumberedHoldIsTimed() {
        #expect(WorkMeasure("max hold") == .time)
        #expect(WorkMeasure("hold for time") == .time)
    }

    // MARK: - Whole words, and numbers that belong to a unit

    @Test("A unit word is read whole — 'min' inside another word is not a minute")
    func unitWordsAreReadWhole() {
        #expect(TargetUnits.names(["min"], in: "minimal rest") == false)
        #expect(TargetUnits.names(["min"], in: "2 min") == true)
    }

    @Test("Numbers stated in two different units are refused rather than guessed")
    func twoUnitsInOneTargetAreRefused() {
        // Guessing which number meant what is how a wrong number reaches a
        // training log, which is the failure this scan exists to prevent.
        #expect(TargetUnits.statedQuantities(in: "40 m then 20 yd") == nil)
        #expect(TargetUnits.statedQuantities(in: "1 min 30 s") == nil)
    }

    @Test("A number with no unit after it states no quantity")
    func aBareNumberStatesNoUnit() {
        #expect(TargetUnits.statedQuantities(in: "8-12") == nil)
    }

    @Test("The numbers and the unit come back as written")
    func quantitiesComeBackAsWritten() {
        let stated = TargetUnits.statedQuantities(in: "40 metres")
        #expect(stated?.unit == "metres")
        #expect(stated?.values == [40])

        let span = TargetUnits.statedQuantities(in: "30-45 seconds")
        #expect(span?.values == [30, 45])
    }

    // MARK: - Spellings, never conversions

    @Test("Several spellings name one unit, and no two units are ever related")
    func spellingIsCanonicalisedAndNothingIsConverted() {
        for word in ["m", "metre", "metres", "meter", "meters"] {
            #expect(TargetUnits.distanceUnitPerWord[word] == .metres, "\(word) is not metres")
        }
        // Yards and metres are both here and there is no factor between them
        // anywhere in this file — two units are reported side by side rather
        // than summed.
        #expect(TargetUnits.distanceUnitPerWord["yd"] == .yards)
        #expect(WorkDistance("20 yd").unit == .yards)
        #expect(WorkDistance("20 yd").lowerValue == 20)
    }

    @Test("A minute is sixty seconds, which is arithmetic rather than a prescription")
    func timeWordsAreUnitArithmetic() {
        #expect(TargetUnits.secondsPerTimeWord["min"] == 60)
        #expect(TargetUnits.secondsPerTimeWord["hour"] == 3600)
        #expect(WorkDuration("2 min").seconds == 120)
        #expect(WorkDuration("1:30").seconds == 90)
    }
}
