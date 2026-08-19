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
/// it. It reads the store directly and reports a tap to `onOpen`, which is what
/// pushes — rather than holding a `NavigationLink`, which would draw a
/// disclosure chevron on every row.
///
/// **What it depends on.** `TrainingPlan` from Store, `PlansListing` for every
/// string it prints, and `NoBlockView`. It writes nothing.
struct PlansView: View {

    let profile: UserProfile
    /// What to do when a block is chosen. The stack's path lives above this
    /// screen, so opening one is reported rather than performed here.
    let onOpen: (TrainingPlan) -> Void

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
                            fraction: PlansListing.loggedFraction(of: plan),
                            onOpen: { onOpen(plan) }
                        )
                        // Each block its own panel, as each session is on the
                        // block screen. One panel holding every block made the
                        // one he is training and the ones behind him a single
                        // object with several names in it.
                        .panelRow(.only, fillsPanel: true)
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
///
/// **A `Button`, not a `NavigationLink`.** The link drew the system's own
/// disclosure chevron, which a button presenting a sheet does not get — so the
/// blocks list had one and the day rows had none, and the same act read two ways
/// one screen apart. Both draw `DisclosureChevron` now, so the mark is the app's
/// rather than the presentation's, and neither row can drift from the other
/// again.
private struct BlockCard: View {

    let plan: TrainingPlan
    /// The line under the name, already phrased. Passed in rather than computed
    /// here so the whole line comes from the one place that phrases it.
    let subtitle: String
    /// How much of the block is logged, or `nil` when it prescribes nothing yet.
    let fraction: Double?
    let onOpen: () -> Void

    private var title: String { PlansListing.title(of: plan) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.standard) {
                VStack(alignment: .leading, spacing: Spacing.snug) {
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        Text(title)
                            .font(.supersetTitle)
                            .foregroundStyle(Palette.ink)
                        Text(subtitle)
                            .font(.supersetSupport)
                            .foregroundStyle(Palette.muted)
                    }
                    // Under the line it restates, and only where there is
                    // something to be a fraction of.
                    if let fraction {
                        ProgressRule(fraction: fraction)
                    }
                }
                Spacer(minLength: Spacing.standard)
                DisclosureChevron()
            }
            .padding(PanelMetrics.buttonInsets)
            // The panel's whole area, not the text's: a tap near the edge of a
            // row that looks like a button has to behave like one.
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            // A screen reader hears one row at a time, with no order to read the
            // standing from, so the row says it in a word.
            .accessibilityLabel(
                "\(title), \(PlansListing.standing(of: plan).spoken), \(subtitle)")
        }
        .buttonStyle(.plain)
    }
}
