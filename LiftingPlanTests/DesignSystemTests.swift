import Testing
import SwiftUI
@testable import LiftingPlan
import LiftingKit

/// The vocabulary itself, guarded.
///
/// A design system is only a system while it stays small: the audit found 12
/// spacing values across 37 sites and 18 type treatments for six screens, and
/// every one of them arrived one reasonable-looking literal at a time. These
/// tests are the thing that says no to the thirteenth value. They assert the
/// *size* of the vocabulary as much as its contents — adding a sixth spacing
/// step or a sixth type role fails here, which is the point.
@Suite("Design system")
struct DesignSystemTests {

    // MARK: - Spacing

    @Test("The spacing scale is exactly five values")
    func scaleIsFiveValues() {
        #expect(Spacing.all == [4, 8, 12, 16, 24])
    }

    @Test("Every spacing value sits on the 4pt grid")
    func scaleIsOnTheGrid() {
        // 18 of 37 gap sites were off the grid — 1, 2, 6, 10, 14 and 26. The
        // grid is the whole reason the scale exists.
        for value in Spacing.all {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test("The scale is strictly increasing, so each step is a real step")
    func scaleIsOrdered() {
        #expect(Spacing.all == Spacing.all.sorted())
        #expect(Set(Spacing.all).count == Spacing.all.count)
    }

    @Test("The named steps are the scale")
    func namesAreTheScale() {
        #expect([Spacing.tight, Spacing.snug, Spacing.standard, Spacing.section, Spacing.major]
            == Spacing.all)
    }

    // MARK: - Radius

    @Test("There are two radii, and the bigger the surface the rounder it is")
    func twoRadii() {
        // The mark that a thing is recorded is the smaller shape drawn; a panel
        // is a surface and takes the larger. The panel was briefly the tighter
        // of them, which is what made the panels read as hard rather than as
        // quiet.
        //
        // There were four. One was the rest bar's, on the reasoning that a
        // surface floating over content is rounder than one lying on it — and
        // when the panel gained a shadow the two figures met, so the bar takes
        // the panel's. One was an eight for entry fields and badges, which
        // nothing ever drew. Two names for one number is what this suite exists
        // to catch, and so is a name for no number at all.
        #expect(Radius.all == [Radius.mark, Radius.panel])
        #expect(Radius.mark < Radius.panel)
    }

    // MARK: - Tap targets

    @Test("The minimum tap target is Apple's 44pt")
    func minimumTapTarget() {
        #expect(TapTarget.minimum == 44)
    }

    // MARK: - Type

    @Test("The type ramp is six roles, each built on a semantic text style")
    func typeRamp() {
        // Stated as equalities rather than described in a comment: a future
        // edit that swaps a semantic style for a fixed point size — which is
        // exactly what TimerRing did — stops being a silent change. Metric is
        // built on `.title3` and drawn in the monospaced face: the numbers are
        // the app's one typographic signature, and a column of figures that has
        // to be scanned is set in mono. The size is still semantic, so Dynamic
        // Type carries it.
        #expect(
            Font.supersetMetric == Font.system(.title3, design: .monospaced).weight(.semibold))
        // A heading has to win against the rows inside the panel it introduces.
        // Both were `.headline`, so position was the only thing saying which
        // was which.
        #expect(Font.supersetHeading == Font.title3.weight(.bold))
        #expect(Font.supersetTitle == Font.headline)
        #expect(Font.supersetBody == Font.body)
        #expect(Font.supersetSupport == Font.subheadline.monospacedDigit())
        #expect(Font.supersetLabel == Font.caption2.weight(.semibold))
    }

    @Test("The six roles are six distinct treatments")
    func rolesAreDistinct() {
        let roles: [Font] = [
            .supersetMetric, .supersetHeading, .supersetTitle,
            .supersetBody, .supersetSupport, .supersetLabel,
        ]
        #expect(Set(roles).count == 6)
    }

    // MARK: - Set table

    @Test("The row spends its width on the two things a user has to hit")
    func setTableColumns() {
        // These were literals in two files that had to agree or the header
        // stopped sitting over its column, with nothing enforcing it.
        //
        // **The two ends no longer match, and that is the point.** The check is
        // a control and stays at the tap minimum; the badge stopped being one —
        // it opened a menu that changed whether a set counted as working volume,
        // which is the coach's to say now — so it is a label, and the width it
        // gave up went into the fields.
        #expect(SetTableMetrics.checkColumnWidth == TapTarget.minimum)
        #expect(SetTableMetrics.setColumnWidth < TapTarget.minimum, "a label, not a target")
        #expect(SetTableMetrics.entryColumnWidth > SetTableMetrics.checkColumnWidth,
                "the fields are the widest thing on the row")
    }

    @Test("An entry field is bigger than the smallest thing a finger can hit")
    func entryFieldsAreGenerous() {
        // 44 points is what Apple calls the minimum sitting still. This is
        // tapped standing, between sets, with a bar waiting. Height costs the
        // row nothing — width is what is contested — so there is no reason to
        // spend it meanly.
        #expect(SetTableMetrics.entryHeight > TapTarget.minimum)
    }

    @Test("The whole row fits the narrowest screen this ships to")
    func theRowFitsAnSE() {
        // An iPhone SE is 375 points wide, and the panel it sits in leaves about
        // 319. Every point the fields gained came from the badge and the
        // gutters, so this is the arithmetic that says the gain was real rather
        // than borrowed from the edge of the screen.
        let markers: CGFloat = 20 + 12 + 16   // lb, ×, and the work unit
        let columns = SetTableMetrics.setColumnWidth
            + SetTableMetrics.entryColumnWidth * 2
            + SetTableMetrics.checkColumnWidth
        let gutters = SetTableMetrics.columnGutter * 6

        #expect(columns + markers + gutters < 319)
    }
}

/// The marks the coach may choose from, and what each one draws as.
///
/// **`SessionIcon.all` is a vocabulary the app publishes and refuses anything
/// outside**, so it is only as good as the drawing behind it: a name the schema
/// offers that resolves to the same glyph as another is a choice that changes
/// nothing, and a name that falls through to the default is the app quietly
/// drawing a barbell for a swim.
@Suite("The session marks")
struct SessionIconDrawingTests {

    @Test("Every mark the coach is offered draws as itself")
    func everyMarkHasItsOwnGlyph() {
        var drawn: [String: SessionIcon] = [:]
        for icon in SessionIcon.all {
            let symbol = SessionIconView.symbol(for: icon)
            if let taken = drawn[symbol] {
                Issue.record(Comment(rawValue:
                    "\(icon.rawValue) and \(taken.rawValue) both draw \(symbol)"))
            }
            drawn[symbol] = icon
        }
        #expect(drawn.count == SessionIcon.all.count)
    }

    @Test("No mark falls through to the barbell it is not")
    func nothingFallsThrough() {
        // The default exists for a stored mark that outlives a build, which
        // cannot arrive through the front door. Anything in `all` reaching it
        // means a case was added to the vocabulary and not to the drawing.
        let barbell = "figure.strengthtraining.traditional"
        for icon in SessionIcon.all where icon != .strength {
            #expect(SessionIconView.symbol(for: icon) != barbell, Comment(rawValue: icon.rawValue))
        }
    }

    @Test("Every mark is known, so the importer accepts what the schema offers")
    func theVocabularyAgreesWithItself() {
        // `write_plan`'s schema is built from `all` and `PlanImporter` refuses
        // anything `isKnown` rejects. If those two ever disagree the coach is
        // offered a mark and then refused for choosing it.
        #expect(SessionIcon.all.filter(\.isKnown).count == SessionIcon.all.count)
        #expect(Set(SessionIcon.all.map(\.rawValue)).count == SessionIcon.all.count)
    }
}
