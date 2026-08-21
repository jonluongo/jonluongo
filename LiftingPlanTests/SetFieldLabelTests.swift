import Testing
@testable import LiftingPlan
import LiftingKit

/// What each field of a set row says aloud.
///
/// **A field that names a figure but not itself is the defect here.** A
/// `TextField` takes its accessibility label from its placeholder, and in this
/// row the placeholder is the prescription — so the weight field of a set
/// prescribed at 185 announced itself as "185", next to a work field announcing
/// "8-12". Neither said which of the two it was, on the one screen where a
/// user enters numbers he may not be able to see.
///
/// Every label here names the field *and* the set, because a row is one of
/// several and "repetitions" alone does not say which.
@Suite("What a set row's fields say aloud")
struct SetFieldLabelTests {

    private let third = SetIdentity.working(3)

    @Test("The weight field says it is a weight, in the unit he reads")
    func theLoadFieldNamesItself() {
        #expect(SetFieldLabel.load(unit: .pounds, identity: third)
            == "Weight in pounds, working set 3")
        #expect(SetFieldLabel.load(unit: .kilograms, identity: third)
            == "Weight in kilograms, working set 3")
    }

    @Test("The work field is named for what this exercise measures")
    func theWorkFieldNamesItsMeasure() {
        // A set is counted, held, or carried, and no two of them are the same
        // number. The field recording one says which it is.
        #expect(SetFieldLabel.work(measure: .repetitions, identity: third)
            == "Repetitions, working set 3")
        #expect(SetFieldLabel.work(measure: .time, identity: third)
            == "Seconds held, working set 3")
        #expect(SetFieldLabel.work(measure: .distance(.metres), identity: third)
            == "Metres carried, working set 3")
    }

    @Test("A carry is named in the unit it was prescribed in, never converted")
    func aCarryKeepsItsUnitAloud() {
        #expect(SetFieldLabel.work(measure: .distance(.yards), identity: third)
            == "Yards carried, working set 3")
        #expect(SetFieldLabel.work(measure: .distance(.feet), identity: third)
            == "Feet carried, working set 3")
    }

    @Test("A unit this build has never heard of is read as written")
    func anUnknownUnitSurvives() {
        // `DistanceUnit` is an extensible taxonomy, and the rest of the app
        // reports an unknown value rather than dropping it. So does this.
        #expect(
            SetFieldLabel.work(measure: .distance(DistanceUnit(rawValue: "furlongs")),
                identity: third) == "Furlongs carried, working set 3")
    }

    @Test("A warm-up says it is a warm-up rather than a number")
    func aWarmupIsNamedAsOne() {
        #expect(SetFieldLabel.load(unit: .pounds, identity: .warmup)
            == "Weight in pounds, warm-up set")
        #expect(SetFieldLabel.work(measure: .repetitions, identity: .warmup)
            == "Repetitions, warm-up set")
    }

    @Test("Two fields of one row never say the same thing")
    func theTwoFieldsAreDistinguishable() {
        // The whole point: whatever the prescription is, the two fields of a
        // row are told apart by what they say.
        for measure in [WorkMeasure.repetitions, .time, .distance(.metres)] {
            #expect(
                SetFieldLabel.load(unit: .pounds, identity: third)
                    != SetFieldLabel.work(measure: measure, identity: third))
        }
    }
}
