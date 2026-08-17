import SwiftUI
import LiftingKit

/// One calendar week across the top of the front door, and the day it is showing.
///
/// **What it does.** Draws seven columns — a weekday initial, the date, and a
/// mark under the days the block prescribes work on — plus the full date of the
/// day the screen is currently about. It replaced a large navigation title that
/// held one word and about a hundred points of empty bar; the strip puts the
/// same space to work saying which week this is and what its shape is.
///
/// **How it is used.** Pinned above the front door's list by a
/// `safeAreaInset(edge: .top)`, so it stays while the day's session scrolls
/// under it. It decides nothing: the caller works out which days these are and
/// what each one is, and hears back only which day was tapped.
///
/// **What it depends on.** `WeekStripDay` for what a column is, and the shared
/// spacing, type and tap-target vocabulary. No store, no calendar arithmetic —
/// that is `WeekStrip`'s, in `Domain/`.
///
/// ## Today, and the day being shown
///
/// These are different questions once the lifter has swiped, and the strip
/// answers both by shape rather than by colour alone: **the selected day is a
/// filled circle, today is a ring.** A day that is both is filled — the ring
/// would be invisible under it — and the fact that no *Today* button is offered
/// is what says so. Colour agrees with the shapes but never carries them.
struct WeekStripView: View {

    /// The seven days to draw, earliest first.
    let days: [WeekStripDay]

    /// The full date of the day the screen is about, already worded.
    let dayLine: String

    /// Called with the day a column was tapped for.
    let select: (Date) -> Void

    /// The way back to today, or `nil` while today is what is being shown.
    let returnToToday: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            HStack(spacing: 0) {
                ForEach(days) { day in
                    WeekStripColumn(day: day, select: select)
                }
            }
            // Seven columns cannot survive an accessibility text size without
            // either overlapping or dropping below the 44pt target, so the
            // strip stops growing where the row would break. Everything below
            // it — the session, the prescription, the buttons — keeps scaling.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            HStack {
                Text(dayLine)
                    .font(.barbellTitle)
                Spacer(minLength: Spacing.standard)
                if let returnToToday {
                    Button("Today", action: returnToToday)
                        .font(.barbellBody)
                        .accessibilityHint("Shows today again")
                }
            }
            // The row keeps its height whether or not the button is in it. In
            // the navigation bar the button was correct and unusable: it made a
            // bar appear, which pushed the whole strip down the moment the
            // lifter swiped, so the columns moved under the thumb that had just
            // moved them.
            .frame(minHeight: TapTarget.minimum)
        }
        // One gutter for the whole header, the same the list below it uses. It
        // is as wide as it can be: seven columns inside it are 49pt on the
        // narrowest phone the app runs on, which still clears the 44pt target.
        .padding(.horizontal, Spacing.section)
        .padding(.vertical, Spacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

/// One day of the week strip: which day it is, and everything the strip says
/// about it.
///
/// A value rather than a set of closures so the screen resolves each day once,
/// where it has the plan in hand, and the strip only draws.
struct WeekStripDay: Identifiable, Hashable {

    /// The start of this calendar day.
    let date: Date

    /// Whether this is the day the lifter is actually standing in.
    let isToday: Bool

    /// Whether this is the day the screen is currently showing.
    let isSelected: Bool

    /// Whether the block prescribes a session on it.
    let trains: Bool

    /// Whether it is a day of this block — days outside it are drawn, so the
    /// block's start and end are visible, but cannot be chosen.
    let isReachable: Bool

    var id: Date { date }
}

/// One column: the weekday's initial, the date, and the training mark.
private struct WeekStripColumn: View {

    let day: WeekStripDay
    let select: (Date) -> Void

    var body: some View {
        Button {
            select(day.date)
        } label: {
            VStack(spacing: Spacing.tight) {
                // Taken from the date rather than from a list of letters, so a
                // column's heading cannot drift out of step with the column.
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .font(.barbellLabel)
                    .foregroundStyle(.secondary)

                ZStack {
                    if day.isSelected {
                        Circle().fill(Color.accentColor)
                    } else if day.isToday {
                        Circle().strokeBorder(Color.accentColor)
                    }
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.barbellSupport)
                        .foregroundStyle(numeral)
                }
                // The circle is the tap target, drawn. Fixed rather than
                // scaled: a circle that grew with the text would be seven
                // circles wider than the phone, and it is already the largest
                // a touch needs.
                .frame(width: TapTarget.minimum, height: TapTarget.minimum)

                // Calendar's dot, for the same reason: it is what lets the
                // week's shape be read without opening any of it. A rest day is
                // marked by having no mark, which is absence shown as absence.
                Circle()
                    .fill(mark)
                    .frame(width: Spacing.tight, height: Spacing.tight)
            }
            // The whole column is the target, so seven of them across the
            // narrowest phone still clear 44pt.
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!day.isReachable)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var numeral: Color {
        if day.isSelected { return Color(.systemBackground) }
        if !day.isReachable { return .secondary }
        return .primary
    }

    private var mark: Color {
        day.trains ? .accentColor : .clear
    }

    /// The date spoken in full, then what the strip says about it. A single
    /// letter and a bare numeral are what the column *looks* like; neither is
    /// what it means.
    private var label: String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if day.isToday { parts.append("Today") }
        // A day outside the block prescribes nothing, but saying "rest day"
        // would claim the block placed it there. It did not.
        parts.append(
            day.isReachable
                ? (day.trains ? "Session" : "Rest day")
                : "Outside this block")
        return parts.joined(separator: ", ")
    }
}
