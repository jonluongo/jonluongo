import Testing
import LiftingKit
@testable import LiftingPlan

/// How a prescribed effort reaches the lifter's screen.
///
/// **This is a guard on a training instruction, not on formatting.** The coach
/// prescribes effort on whatever scale he works in, and the standard is that a
/// prescribed value is recorded and shown exactly as prescribed — never
/// converted, bounded or rounded. The one restatement the owner asked for is
/// RPE as a percentage of effort, which is the same figure written out of a
/// hundred instead of out of ten. Everything else that looks like a conversion
/// is a bug: `80% effort` and `80% 1RM` are different instructions, and a lifter
/// handed the second when the coach wrote the first is training to a number
/// nobody prescribed.
///
/// The type had no tests at all, which is what made this worth writing before
/// anything else in `Presentation/`.
@Suite("How a prescribed effort is written")
struct IntensityPrescriptionTests {

    private func label(_ scale: IntensityScale, _ value: String) -> String? {
        IntensityPrescription.label(for: IntensityTarget(scale: scale, value: value))
    }

    // MARK: - Nothing prescribed

    @Test("No target draws nothing, rather than a placeholder inviting one")
    func absentTargetDrawsNothing() {
        #expect(IntensityPrescription.label(for: nil) == nil)
        #expect(label(.rpe, "") == nil)
        #expect(label(.rpe, "   ") == nil, "whitespace is not a target")
    }

    // MARK: - RPE, restated out of a hundred

    @Test("A point on the ten-point scale is written out of a hundred")
    func rpeReadsAsAPercentageOfEffort() {
        #expect(label(.rpe, "8") == "80% effort")
        #expect(label(.rpe, "10") == "100% effort")
        #expect(label(.rpe, " 8 ") == "80% effort", "trimmed, not refused")
    }

    @Test("A half point survives — 7.5 is 75%, not 70 or 80")
    func halfPointsAreNotRounded() {
        #expect(label(.rpe, "7.5") == "75% effort")
    }

    @Test("A span stays a span at both ends")
    func rangesKeepBothEnds() {
        #expect(label(.rpe, "7-8") == "70-80% effort")
        #expect(label(.rpe, "7.5-8.5") == "75-85% effort")
    }

    @Test("A target that is not a number is shown as written, never mangled into one")
    func unreadableRPEIsShownAsWritten() {
        // The whole guard on the restatement: "top set" is not something to
        // multiply, and inventing a figure for it would put a number on screen
        // that the plan does not contain.
        #expect(label(.rpe, "top set") == "RPE top set")
        #expect(label(.rpe, "8+") == "RPE 8+")
        #expect(label(.rpe, "8-") == "RPE 8-", "half a span is not a span")
    }

    // MARK: - The scales that are not restated

    @Test("Reps in reserve is written as it was prescribed")
    func repsInReserveIsNotConverted() {
        #expect(label(.repsInReserve, "2") == "2 RIR")
        #expect(label(.repsInReserve, "1-2") == "1-2 RIR")
    }

    @Test("A percentage of a maximum keeps one per-cent sign, whichever way it arrives")
    func percentOfMaxKeepsOneSign() {
        #expect(label(.percentOfOneRepMax, "80") == "80% 1RM")
        #expect(label(.percentOfOneRepMax, "80%") == "80% 1RM", "not 80%% 1RM")
    }

    @Test("Effort and a percentage of a maximum are never the same sentence")
    func effortIsNotAPercentageOfAMaximum() {
        // Both say "%" and they are different instructions. The word after the
        // figure is what distinguishes them, and the second is never derived
        // from the first — RPE 8 is 80% effort and says nothing about 80% 1RM,
        // which depends on the rep count and is a training claim this app does
        // not make.
        #expect(label(.rpe, "8") == "80% effort")
        #expect(label(.percentOfOneRepMax, "80") == "80% 1RM")
        #expect(label(.rpe, "8") != label(.percentOfOneRepMax, "80"))
    }

    // MARK: - A scale this build has never heard of

    @Test("An unknown scale is named and shown in the words it arrived in")
    func unknownScaleSurvivesIntact() {
        // Dropping it would be discarding something the coach deliberately
        // prescribed, and guessing a phrasing for it would be inventing one.
        #expect(
            label(IntensityScale(rawValue: "velocity"), "0.8 m/s") == "velocity 0.8 m/s")
    }
}
