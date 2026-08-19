import Testing
import Foundation
@testable import LiftingPlan
import LiftingKit

/// What an empty work field offers as a hint.
///
/// The row draws the unit after the field — `s` for a hold, `m` for a carry —
/// so a hint carrying the unit as well says it twice, and in a field sized for
/// three figures says it as `45 sec…`. These are the rules that take the unit
/// off without taking the prescription with it.
@Suite("Work field hints")
struct WorkPrescriptionHintTests {

    @Test("A counted target is hinted exactly as the plan wrote it")
    func countedFigureIsUntouched() {
        // The `×` beside the field is all the unit a counted row has, so
        // nothing is taken off.
        #expect(WorkPrescription.targetFigure(for: "8-12", measure: .repetitions) == "8-12")
        #expect(WorkPrescription.targetFigure(for: "AMRAP", measure: .repetitions) == "AMRAP")
    }

    @Test("A hold is hinted as its figure, because the row draws the seconds")
    func heldFigureDropsTheUnit() {
        // `45 seconds` in a field sized for three figures reads `45 sec…`, and
        // says seconds twice over — the suffix beside it already does.
        #expect(WorkPrescription.targetFigure(for: "45 seconds", measure: .time) == "45")
        #expect(WorkPrescription.targetFigure(for: "30-45 seconds", measure: .time) == "30-45")
    }

    @Test("A clock is hinted as the seconds it means")
    func clockBecomesSeconds() {
        // Read through `WorkDuration` rather than by trimming words, so this
        // cannot disagree with the reader that decided the row is a hold.
        #expect(WorkPrescription.targetFigure(for: "1:30", measure: .time) == "90")
    }

    @Test("A carry is hinted as its figure, in the unit it keeps")
    func carriedFigureDropsTheUnit() {
        #expect(WorkPrescription.targetFigure(for: "40 metres", measure: .distance(.metres)) == "40")
        #expect(WorkPrescription.targetFigure(for: "20 yd", measure: .distance(.yards)) == "20")
        #expect(WorkPrescription.targetFigure(
            for: "50-100 metres", measure: .distance(.metres)) == "50-100")
    }

    @Test("A prescription the readers cannot parse is hinted as written")
    func unparsedFallsBackToTheWording() {
        // Better the plan's own words than an empty hint.
        #expect(WorkPrescription.targetFigure(for: "as long as you can", measure: .time)
            == "as long as you can")
    }
}
