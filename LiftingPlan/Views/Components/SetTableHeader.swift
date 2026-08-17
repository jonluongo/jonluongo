import SwiftUI
import LiftingKit

/// The column names above a table of set rows.
///
/// **What it does.** Names the five columns a set row draws, and names the
/// last-but-one after the unit its rows are actually recorded in — seconds for a
/// hold, the prescribed distance unit for a carry, repetitions otherwise — so
/// the number the lifter types is the number the log keeps.
///
/// **How it is used.** `ExerciseLogSection` draws one above an exercise's rows
/// and `SupersetLogSection` one above a group's. It is one view rather than two
/// because a header that stops sitting over its column is a table that lies
/// about what it contains, and two copies of these widths is how that happens.
/// `firstColumn` differs only because the column beneath it does: a set number
/// on its own exercise, the movement's A1 / A2 inside a group.
///
/// **What it depends on.** `SetTableMetrics` for the widths — the same numbers
/// `SetRowView` reads — and `WorkMeasure` from LiftingKit for what the work is
/// measured in.
struct SetTableHeader: View {

    /// What the badge column holds: `SET` for an exercise on its own.
    let firstColumn: String
    /// What this exercise's work is measured in.
    let measure: WorkMeasure
    /// The lifter's display unit, which names the load column.
    let unit: MassUnit

    var body: some View {
        HStack(spacing: SetTableMetrics.columnGutter) {
            Text(firstColumn).frame(width: SetTableMetrics.setColumnWidth)
            Text("PREVIOUS").frame(maxWidth: .infinity)
            Text(unit.rawValue.uppercased())
                .frame(width: SetTableMetrics.entryColumnWidth)
            Text(workColumnName).frame(width: SetTableMetrics.entryColumnWidth)
            Image(systemName: "checkmark").frame(width: SetTableMetrics.checkColumnWidth)
        }
        .font(.barbellLabel)
        .tracking(Font.labelTracking)
        .foregroundStyle(Palette.muted)
        .padding(.bottom, Spacing.snug)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.rule)
                .frame(height: Palette.hairline)
        }
    }

    /// What the second field is called: the unit its rows are recorded in.
    private var workColumnName: String {
        switch measure {
        case .repetitions: "REPS"
        case .time: "SECS"
        case .distance(let unit): unit.rawValue.uppercased()
        }
    }
}
