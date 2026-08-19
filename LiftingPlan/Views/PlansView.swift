import SwiftUI
import SwiftData
import LiftingKit

/// Every block the lifter has been given, the one he is on first.
///
/// **What it does.** Lists the blocks newest first and opens one when it is
/// tapped. It exists because the screen used to show one block — the newest —
/// and every block before it became unreachable the moment a new one arrived,
/// even though every set logged against it is still in the record and still goes
/// to Claude. The record was navigable in the export and nowhere on the phone.
///
/// **Nothing here labels a category.** The list was grouped under `Current` and
/// `Earlier` headings and each row carried a glyph — a dumbbell for the open
/// block, a calendar for a closed one. Neither said anything: the headings named
/// a standing the order already gives, and the two glyphs were not two values of
/// one thing but two different subjects, so the change from one to the other was
/// unreadable. What actually distinguishes the blocks is what the rows say —
/// the block he is training reports where he is in it, and a block behind him
/// reports when it ran.
///
/// **How it is used.** The root of the stack, with the block pushed on top of
/// it. It reads the store directly and hands each block to `BlockView`.
///
/// **What it depends on.** `TrainingPlan` from Store, `PlansListing` for every
/// string it prints, and `NoBlockView`. It writes nothing.
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
                        BlockCard(
                            plan: plan,
                            subtitle: PlansListing.subtitle(of: plan, calendar: calendar),
                            profile: profile
                        )
                        // Each block its own panel, as each session is on the
                        // block screen. One panel holding every block made the
                        // one he is training and the ones behind him a single
                        // object with several names in it.
                        .panelRow(.only)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle("Blocks")
        // Inline, as the block page is. A large title on the root and a small
        // centred one a tap deeper is the app changing what a header looks like
        // as you move through it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AccountToolbarItem(profile: profile) }
    }
}

/// One block: what it is called, and the one line that says where it stands.
///
/// The card states what the block is and stops. Nothing here is a badge or a
/// score: the app decides nothing about a block, including whether it went well,
/// and the record cannot tell a block he finished from one a new plan replaced.
private struct BlockCard: View {

    let plan: TrainingPlan
    /// The line under the name, already phrased. Passed in rather than computed
    /// here so the whole line comes from the one place that phrases it.
    let subtitle: String
    let profile: UserProfile

    private var title: String { PlansListing.title(of: plan) }

    var body: some View {
        NavigationLink {
            BlockView(plan: plan, profile: profile)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .font(.barbellTitle)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.barbellSupport)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.vertical, Spacing.tight)
            .accessibilityElement(children: .combine)
            // A screen reader hears one row at a time, with no order to read the
            // standing from, so the row says it in a word.
            .accessibilityLabel(
                "\(title), \(PlansListing.standing(of: plan).spoken), \(subtitle)")
        }
    }
}
