import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What a logged session says it was.
///
/// The exercise screen printed `× \(reps)` for everything, because reps was the
/// only measure the trend carried: a carry read `70 lb × 0` and a plank read
/// `0 reps`. Zeroes nobody performed, under a heading that says what he did.
@Suite("A logged set, said in its own measure")
struct LoggedWorkSummaryTests {

    /// **Every measure defaults to unstated.** It used to default `reps` to
    /// zero, because the model could not express *he did not say* — so a carry
    /// fixture passed `reps: 0` and the row it produced said `× 0`, which is the
    /// defect this suite exists to guard against.
    private func line(
        load: Mass? = nil, reps: Int? = nil, seconds: Int? = nil,
        distance: Distance? = nil
    ) -> String? {
        LoggedWorkSummary.text(
            SnapshotPerformedSet(
                setIndex: 0, load: load, reps: reps, durationSeconds: seconds,
                distance: distance, completedAt: .distantPast))
    }

    @Test("A counted set is a load and a count")
    func countedSet() {
        #expect(line(load: Mass(value: 185, unit: .pounds), reps: 8) == "185 lb × 8")
    }

    @Test("A carry is a load and a distance, in the unit it was logged in")
    func carriedSet() {
        let line = line(
            load: Mass(value: 70, unit: .pounds), reps: nil,
            distance: Distance(value: 40, unit: .metres))

        #expect(line == "70 lb × 40 m", "not 70 lb × 0")
    }

    @Test("A hold with no load is seconds, not zero repetitions")
    func heldSet() {
        #expect(line(reps: nil, seconds: 45) == "45 s")
    }

    @Test("A counted set with no load is a count")
    func bodyweightSet() {
        #expect(line(reps: 12) == "12")
    }

    @Test("Nothing converts: a load and a distance are both read as recorded")
    func nothingIsConverted() {
        // **The load used to convert into a display unit.** That unit was a fact
        // about how the user thinks, and it lives in `user.md` with the rest
        // of him — so a hundred kilos is a hundred kilos here, and fifty yards
        // was never anything else. `Mass` compares exactly on representation,
        // and a record that canonicalized would misreport what was lifted.
        let line = line(
            load: Mass(value: 100, unit: .kilograms),
            distance: Distance(value: 50, unit: .yards))

        #expect(line == "100 kg × 50 yd")
    }

    @Test("A set the record holds nothing for says nothing")
    func emptySet() {
        #expect(line() == nil)
    }
}
