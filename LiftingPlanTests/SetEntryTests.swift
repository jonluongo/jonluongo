import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What a lifter's typing means.
///
/// These rules were the least covered in the app until this suite: they lived
/// inside `SetRowView`'s bindings, and a `Binding` is not a thing a test can
/// type into. They are also the rules the record depends on most — a hold that
/// was not timed must not become a hold of zero, and nothing typed into a work
/// field may reach a rep total unless the row counts reps.
@Suite("Typing into a set")
struct SetEntryTests {

    // MARK: - The weight field

    @Test("A load is shown in the lifter's own unit")
    func loadIsShownConverted() {
        let hundredKilos = Mass(value: 100, unit: .kilograms)
        #expect(SetEntry.text(for: hundredKilos, in: .kilograms) == "100")
        #expect(SetEntry.text(for: hundredKilos, in: .pounds).hasPrefix("220"))
    }

    @Test("A set logged without a load shows an empty field, not a zero")
    func absentLoadShowsNothing() {
        // A zero would be a claim he lifted nothing, which is a different thing
        // from a bodyweight set nobody put a number on.
        #expect(SetEntry.text(for: nil, in: .pounds).isEmpty)
    }

    @Test("A comma is a decimal point, because the keyboard offers one")
    func commaIsADecimalPoint() {
        #expect(SetEntry.load(from: "2,5", in: .kilograms) == Mass(value: 2.5, unit: .kilograms))
        #expect(SetEntry.load(from: "2.5", in: .kilograms) == Mass(value: 2.5, unit: .kilograms))
    }

    @Test("Typing something that is not a number clears the load")
    func nonsenseClearsTheLoad() {
        // Rather than keeping the last good value, so the field and the record
        // never disagree about what was lifted.
        #expect(SetEntry.load(from: "", in: .pounds) == nil)
        #expect(SetEntry.load(from: "abc", in: .pounds) == nil)
        #expect(SetEntry.load(from: "185", in: .pounds) == Mass(value: 185, unit: .pounds))
    }

    @Test("The unit written is the unit shown, and nothing converts on the way in")
    func loadKeepsTheUnitItWasTypedIn() {
        #expect(SetEntry.load(from: "100", in: .kilograms)?.unit == .kilograms)
        #expect(SetEntry.load(from: "100", in: .pounds)?.unit == .pounds)
    }

    // MARK: - Reps

    @Test("No reps shows an empty field rather than a nought")
    func zeroRepsShowsNothing() {
        #expect(SetEntry.text(forReps: 0).isEmpty)
        #expect(SetEntry.text(forReps: 8) == "8")
    }

    @Test("An emptied rep field is zero, because a counted set has a count")
    func emptyRepsIsZero() {
        // `reps` is not optional on the model: a counted set with nothing typed
        // has no reps, rather than an unknown number of them.
        #expect(SetEntry.reps(from: "") == 0)
        #expect(SetEntry.reps(from: "12") == 12)
    }

    @Test("A stray character does not swallow the number around it")
    func repsIgnoreNonDigits() {
        #expect(SetEntry.reps(from: "1o2") == 12)
        #expect(SetEntry.reps(from: "8 reps") == 8)
    }

    // MARK: - A hold, which is not a rep count

    @Test("A hold nobody timed is nothing, not zero seconds")
    func untimedHoldIsNil() {
        // The distinction the whole `WorkMeasure` design exists to keep: a set
        // he did not time did not last no time.
        #expect(SetEntry.seconds(from: "") == nil)
        #expect(SetEntry.seconds(from: "abc") == nil)
        #expect(SetEntry.seconds(from: "45") == 45)
    }

    @Test("A hold shows its seconds, and an untimed one shows nothing")
    func holdText() {
        #expect(SetEntry.text(forSeconds: nil).isEmpty)
        #expect(SetEntry.text(forSeconds: 45) == "45")
        // Zero is a hold of no seconds, which somebody did record — so unlike
        // reps it is shown rather than blanked.
        #expect(SetEntry.text(forSeconds: 0) == "0")
    }

    // MARK: - A carry, which is neither

    @Test("A carry that did not happen is nothing, not a distance of zero")
    func absentCarryIsNil() {
        #expect(SetEntry.distance(from: "", in: .metres) == nil)
        #expect(SetEntry.distance(from: "abc", in: .metres) == nil)
        #expect(SetEntry.text(for: nil).isEmpty)
    }

    @Test("A carry keeps the unit it was prescribed in")
    func carryKeepsItsUnit() {
        // Nothing converts a distance, so a carry prescribed in yards is
        // recorded and shown in yards.
        #expect(SetEntry.distance(from: "40", in: .yards)
            == Distance(value: 40, unit: .yards))
        #expect(SetEntry.distance(from: "40", in: .metres)
            == Distance(value: 40, unit: .metres))
        #expect(SetEntry.text(for: Distance(value: 40.5, unit: .yards)) == "40.5")
    }

    @Test("A carry takes a comma for a decimal point too")
    func carryTakesAComma() {
        #expect(SetEntry.distance(from: "12,5", in: .metres)
            == Distance(value: 12.5, unit: .metres))
    }
}
