import Testing
import Foundation
@testable import LiftingKit

/// Reading a hold out of the text a plan wrote it in.
///
/// The pairing with `RepRangeTests` is the point: every string that names time
/// must be refused by one type and read by the other, and no string may be read
/// by both. The last suite here asserts exactly that.
@Suite("WorkDuration")
struct WorkDurationTests {

    // MARK: - What is a hold

    @Test(
        "A target measured in time is recognized as a hold",
        arguments: [
            "30 seconds", "30 sec", "30s", "45 secs", "1 minute", "2 min", "90 SECONDS",
            "1:30", "30 second hold", "3 mins per side", "max time hold",
        ]
    )
    func timedTargetsAreTimed(text: String) {
        #expect(WorkDuration(text).isTimed, "\(text) prescribes time")
    }

    @Test(
        "A rep target is not a hold",
        arguments: ["8-12", "5", "AMRAP", "", "8 to 12", "10 each side", "5RM"]
    )
    func repTargetsAreNotTimed(text: String) {
        #expect(!WorkDuration(text).isTimed, "\(text) prescribes repetitions")
    }

    @Test("A distance is neither a hold nor a rep count", arguments: ["40 m", "50 yards", "20 ft"])
    func distancesAreNotTimed(text: String) {
        #expect(!WorkDuration(text).isTimed)
        #expect(RepRange(text).isEmpty)
    }

    // MARK: - How long it says

    @Test("Seconds are read as seconds")
    func secondsAreRead() {
        #expect(WorkDuration("30 seconds").seconds == 30)
        #expect(WorkDuration("45s").seconds == 45)
        #expect(WorkDuration("30 SEC").seconds == 30)
    }

    @Test("Minutes and hours are converted to seconds")
    func largerUnitsConvert() {
        #expect(WorkDuration("2 min").seconds == 120)
        #expect(WorkDuration("1 minute").seconds == 60)
        #expect(WorkDuration("1 hour").seconds == 3600)
    }

    @Test("A clock is read as a clock, not as two numbers")
    func clockIsRead() {
        #expect(WorkDuration("1:30").seconds == 90)
        #expect(WorkDuration("0:45").seconds == 45)
        #expect(WorkDuration("1:00:00").seconds == 3600)
    }

    @Test("A range of durations states both bounds and seeds neither")
    func rangeStatesBothBounds() {
        let range = WorkDuration("30-45 seconds")
        #expect(range.lowerSeconds == 30)
        #expect(range.upperSeconds == 45)
        #expect(range.seconds == nil, "a range names no single duration to seed")
        #expect(range.isTimed)
    }

    @Test("A reversed range is normalized")
    func reversedRangeIsNormalized() {
        let range = WorkDuration("45-30 seconds")
        #expect(range.lowerSeconds == 30)
        #expect(range.upperSeconds == 45)
    }

    // MARK: - What it refuses to read

    @Test(
        "A hold whose duration cannot be read without guessing states none",
        arguments: ["1 min 30 s", "40 m in 30 seconds", "max time hold", "hold for time"]
    )
    func ambiguousDurationsAreRefused(text: String) {
        let duration = WorkDuration(text)
        #expect(duration.isEmpty, "\(text) does not resolve to one duration")
        #expect(duration.seconds == nil)
        #expect(duration.lowerSeconds == 0)
        #expect(duration.upperSeconds == 0)
    }

    @Test("A hold this build cannot put a number on is still a hold")
    func unreadableHoldIsStillTimed() {
        #expect(WorkDuration("1 min 30 s").isTimed)
        #expect(WorkDuration("max time hold").isTimed)
    }

    @Test("A rep target reads as no duration at all")
    func repTargetHasNoDuration() {
        let duration = WorkDuration("8-12")
        #expect(duration.isEmpty)
        #expect(duration.seconds == nil)
        #expect(duration.description == "")
    }

    @Test("description gives back a readable form")
    func descriptionIsReadable() {
        #expect(WorkDuration("30 seconds").description == "30s")
        #expect(WorkDuration("30-45 seconds").description == "30-45s")
        #expect(WorkDuration("2 min").description == "120s")
    }

    // MARK: - The two readers cannot both claim a target

    @Test(
        "No target is read as both reps and time",
        arguments: [
            "8-12", "5", "AMRAP", "", "30 seconds", "1:30", "2 min", "40 m",
            "8 to 12", "30-45 seconds", "10 each side",
        ]
    )
    func repsAndTimeNeverBothRead(text: String) {
        let reps = RepRange(text)
        let hold = WorkDuration(text)
        #expect(
            !(!reps.isEmpty && !hold.isEmpty),
            "\(text) was read as both \(reps) reps and \(hold)")
    }

    @Test(
        "Every target time reads is one RepRange refuses",
        arguments: ["30 seconds", "45s", "1:30", "2 min", "30-45 seconds", "3 mins per side"]
    )
    func timedTargetsAreRefusedAsReps(text: String) {
        #expect(RepRange(text).isEmpty)
        #expect(WorkDuration(text).isTimed)
    }
}
