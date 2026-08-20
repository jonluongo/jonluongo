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

    private func line(
        load: Mass? = nil, reps: Int = 0, seconds: Int? = nil, distance: Distance? = nil,
        unit: MassUnit = .pounds
    ) -> String? {
        LoggedWorkSummary.text(
            load: load, reps: reps, durationSeconds: seconds, distance: distance, unit: unit)
    }

    @Test("A counted set is a load and a count")
    func countedSet() {
        #expect(line(load: Mass(value: 185, unit: .pounds), reps: 8) == "185 lb × 8")
    }

    @Test("A carry is a load and a distance, in the unit it was logged in")
    func carriedSet() {
        let line = line(
            load: Mass(value: 70, unit: .pounds), reps: 0,
            distance: Distance(value: 40, unit: .metres))

        #expect(line == "70 lb × 40 m", "not 70 lb × 0")
    }

    @Test("A hold with no load is seconds, not zero repetitions")
    func heldSet() {
        #expect(line(reps: 0, seconds: 45) == "45 s")
    }

    @Test("A counted set with no load is a count")
    func bodyweightSet() {
        #expect(line(reps: 12) == "12")
    }

    @Test("A load converts into the unit he reads in; a distance never converts")
    func unitsAreHisOwnOnlyForLoad() {
        let line = line(
            load: Mass(value: 100, unit: .kilograms), reps: 0,
            distance: Distance(value: 50, unit: .yards), unit: .pounds)

        #expect(line == "220.5 lb × 50 yd")
    }

    @Test("A set the record holds nothing for says nothing")
    func emptySet() {
        #expect(line() == nil)
    }
}
