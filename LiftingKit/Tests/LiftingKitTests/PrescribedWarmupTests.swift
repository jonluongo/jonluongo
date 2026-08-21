import Testing
import Foundation
@testable import LiftingKit

/// A warm-up the coach prescribed, rather than one the lifter added.
///
/// **The gap this closes.** `isWarmup` appeared nowhere in the plan document.
/// `SetSeeding` hardcoded `false` for everything prescribed, and only a set the
/// lifter added himself was ever marked — so *"ramp three sets to your top
/// set"*, an ordinary thing for a coach to say, could not be written down. The
/// app's answer was that the lifter adds his own warm-ups, which is the app
/// quietly owning a piece of the prescription.
///
/// Found by Jon asking why the prescribed and performed sides did not carry the
/// same columns.
@Suite("A warm-up the coach asked for")
struct PrescribedWarmupTests {

    private func decode(_ json: String) throws -> SetPrescription {
        try JSONDecoder().decode(SetPrescription.self, from: Data(json.utf8))
    }

    @Test("A set can be prescribed as a warm-up")
    func aSetCanBeStatedAsAWarmup() throws {
        #expect(try decode(#"{"repRange":"5","isWarmup":true}"#).isWarmup)
    }

    @Test("A set that says nothing about it is a working set")
    func silenceIsAWorkingSet() throws {
        // The absence of a warm-up marker is not the absence of an answer: a set
        // nobody called a warm-up is work.
        #expect(try decode(#"{"repRange":"5"}"#).isWarmup == false)
        #expect(try decode("{}").isWarmup == false)
    }

    @Test("A working set does not carry the marker it does not need")
    func aWorkingSetWritesNothing() throws {
        // Most sets are working sets. A document stating `"isWarmup": false` on
        // every one of them is noise in a file a person reads.
        let written = try JSONEncoder().encode(SetPrescription(repRange: "5"))
        let object = try #require(
            try JSONSerialization.jsonObject(with: written) as? [String: Any])
        #expect(object["isWarmup"] == nil)

        let warmup = try JSONEncoder().encode(SetPrescription(repRange: "5", isWarmup: true))
        let marked = try #require(
            try JSONSerialization.jsonObject(with: warmup) as? [String: Any])
        #expect(marked["isWarmup"] as? Bool == true)
    }

    @Test("A warm-up survives the round trip it has to survive")
    func itRoundTrips() throws {
        for stated in [true, false] {
            let set = SetPrescription(repRange: "5", isWarmup: stated)
            let data = try JSONEncoder().encode(set)
            #expect(try JSONDecoder().decode(SetPrescription.self, from: data) == set)
        }
    }

    // MARK: - What a ramp is

    @Test("A ramp is sets that disagree about it, and the disagreement is kept")
    func aRampKeepsEachSetsOwnAnswer() {
        // Three warm-ups to a top set is the whole reason this exists. What
        // matters is that filling in what a set did not state never overwrites
        // what it did.
        let ramp = SetPrescription.everySet(
            stated: [
                SetPrescription(suggestedLoad: Mass(value: 135, unit: .pounds), isWarmup: true),
                SetPrescription(suggestedLoad: Mass(value: 155, unit: .pounds), isWarmup: true),
                SetPrescription(suggestedLoad: Mass(value: 185, unit: .pounds)),
            ],
            count: 3, repRange: "5", suggestedLoad: nil, intensity: nil)

        #expect(ramp.map(\.isWarmup) == [true, true, false])
        #expect(ramp.allSatisfy { $0.repRange == "5" }, "the shared rep target still reaches them")
    }

    @Test("An exercise is not a warm-up, so no set inherits one")
    func nothingIsInheritedFromTheExercise() {
        // There is no exercise-level warm-up to inherit, and there must not be:
        // an exercise is not a warm-up, some of its sets are.
        let sets = SetPrescription.everySet(
            stated: [], count: 3, repRange: "5", suggestedLoad: nil, intensity: nil)
        #expect(sets.allSatisfy { !$0.isWarmup })
    }

    // MARK: - The typed target, read from what is already there

    @Test("Every set reports what it asks for, typed")
    func aSetReportsItsTarget() {
        #expect(SetPrescription(repRange: "8-12").target == .repetitions(low: 8, high: 12))
        #expect(SetPrescription(repRange: "45s").target == .time(low: 45, high: nil))
        #expect(SetPrescription(repRange: "40m").target
            == .distance(low: 40, high: nil, unit: .metres))
        #expect(SetPrescription(repRange: "AMRAP").target == .repetitionsToFailure)
    }

    @Test("A set that stated no target has none")
    func anUnstatedTargetIsNone() {
        #expect(SetPrescription().target == nil)
        #expect(SetPrescription(suggestedLoad: Mass(value: 185, unit: .pounds)).target == nil)
    }

    @Test("A carry reports a carry rather than a rep count")
    func aCarryIsNotCounted() {
        // The defect the whole measure vocabulary exists to prevent: forty
        // metres reaching a rep total as forty.
        let carry = SetPrescription(repRange: "40m")
        #expect(carry.target?.measure == .distance(.metres))
        #expect(carry.target?.measure != .repetitions)
    }
}
