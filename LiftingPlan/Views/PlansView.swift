import SwiftUI
import SwiftData
import LiftingKit

/// Every block the lifter has been given, newest first — the Plans tab.
///
/// **What it does.** Draws one section per plan, headed by the dates that plan
/// covers, holding a single card: the plan itself. Tapping the card opens it in
/// full. It exists because the tab used to show one block — the newest — and
/// every block before it became unreachable the moment a new one arrived, even
/// though every set logged against it is still in the record and still goes to
/// Claude. The record was navigable in the export and nowhere on the phone.
///
/// **Newest first**, because the block a lifter looks up is nearly always the
/// one he is on or the one he just left; the rest are history and history reads
/// backwards.
///
/// **How it is used.** The second tab. It reads the store directly, as a tab
/// addressed by nothing must, and hands each plan to `BlockView` — the screen
/// that already drew a whole block, now reached by name instead of by being the
/// only one.
///
/// **What it depends on.** `TrainingPlan` from Store, `PlansListing` for every
/// string it prints, and the shared `IconCircleRow` and `NoBlockView`. It writes
/// nothing.
struct PlansView: View {

    let profile: UserProfile

    @Environment(\.calendar) private var calendar
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    var body: some View {
        Group {
            if plans.isEmpty {
                NoBlockView()
            } else {
                List {
                    ForEach(plans) { plan in
                        Section {
                            PlanCard(
                                plan: plan,
                                dateRange: PlansListing.header(for: plan, calendar: calendar),
                                profile: profile
                            )
                        } header: {
                            Text(PlansListing.header(for: plan, calendar: calendar))
                        }
                    }
                }
            }
        }
        .navigationTitle("Plans")
    }
}

/// One plan, as the single card in its own section.
///
/// **Which block is current is said in words**, in the line under the name,
/// exactly as a week inside a block says "This week". The tint moves with it
/// and never carries it alone, and nothing here is a badge or a score — the app
/// decides nothing about a block, including whether it went well.
///
/// The card states what the plan is and how much of it has been logged, and
/// stops. A plan that prescribes nothing yet says so rather than counting to
/// zero, and one nobody has trained yet omits the logged count entirely.
private struct PlanCard: View {

    let plan: TrainingPlan
    /// The dates the section is headed by, repeated into the row's VoiceOver
    /// label — a header is a separate element to a screen reader, so a row that
    /// did not say its own dates would be announced as a name with no when.
    let dateRange: String
    let profile: UserProfile

    private var isCurrent: Bool { PlansListing.isCurrent(plan) }
    private var title: String { PlansListing.title(of: plan) }
    private var summary: String { PlansListing.summary(of: plan) }

    var body: some View {
        NavigationLink {
            BlockView(plan: plan, profile: profile)
        } label: {
            IconCircleRow(
                systemImage: "calendar",
                tint: isCurrent ? .accentColor : .secondary,
                title: title,
                subtitle: summary
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(dateRange), \(summary)")
        }
    }
}
