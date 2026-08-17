import Testing
import SwiftUI
@testable import LiftingPlan

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

    @Test("There are two radii: one small, one large")
    func twoRadii() {
        #expect(Radius.all == [Radius.small, Radius.large])
        #expect(Radius.small < Radius.large)
    }

    // MARK: - Tap targets

    @Test("The minimum tap target is Apple's 44pt")
    func minimumTapTarget() {
        #expect(TapTarget.minimum == 44)
    }

    // MARK: - Type

    @Test("The type ramp is five roles, each built on a semantic text style")
    func typeRamp() {
        // Stated as equalities rather than described in a comment: a future
        // edit that swaps a semantic style for a fixed point size — which is
        // exactly what TimerRing did — stops being a silent change. Metric is
        // built on `.title3` and drawn in the monospaced face: the numbers are
        // the app's one typographic signature, and a column of figures that has
        // to be scanned is set in mono. The size is still semantic, so Dynamic
        // Type carries it.
        #expect(
            Font.barbellMetric == Font.system(.title3, design: .monospaced).weight(.semibold))
        #expect(Font.barbellTitle == Font.headline)
        #expect(Font.barbellBody == Font.body)
        #expect(Font.barbellSupport == Font.subheadline.monospacedDigit())
        #expect(Font.barbellLabel == Font.caption2.weight(.semibold))
    }

    @Test("The five roles are five distinct treatments")
    func rolesAreDistinct() {
        let roles: [Font] = [.barbellMetric, .barbellTitle, .barbellBody, .barbellSupport, .barbellLabel]
        #expect(Set(roles).count == 5)
    }

    // MARK: - Set table

    @Test("The set table's columns are declared once")
    func setTableColumns() {
        // These were three literals in two files — ExerciseLogSection's header
        // and SetRowView's rows — that had to agree or the header stopped
        // sitting over its column, with nothing enforcing it.
        #expect(SetTableMetrics.setColumnWidth == SetTableMetrics.checkColumnWidth)
        #expect(SetTableMetrics.entryColumnWidth > SetTableMetrics.setColumnWidth)
        #expect(SetTableMetrics.columnGutter == Spacing.snug)
    }
}
