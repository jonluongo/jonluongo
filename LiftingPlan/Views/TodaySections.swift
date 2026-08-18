import SwiftUI
import LiftingKit

/// A block with no workout left in it: what the record holds, and the one thing
/// left to do about it.
///
/// The count is a count and not a score — nothing here decides whether it was
/// enough. The app cannot reach the coach, so it says who can.
struct TodayFinishedSection: View {

    let plan: TrainingPlan

    var body: some View {
        let days = plan.orderedWeeks.flatMap { $0.orderedDays }
        Section {
            // The heading is the page's title now, so this states only what the
            // title cannot: what the record holds, and who writes the next one.
            if let record = TodayPhrasing.recordLine(
                finished: days.filter { $0.completedAt != nil }.count,
                prescribed: days.count
            ) {
                Text(record)
                    .font(.barbellSupport)
                    .foregroundStyle(Palette.muted)
                    .panelRow(.first)
                    .listRowSeparator(.hidden)
            }
            Text("Ask Claude for the next one.")
                .font(.barbellBody)
                .foregroundStyle(Palette.ink)
                .panelRow(.last)
                .listRowSeparator(.hidden)
        }
    }
}
