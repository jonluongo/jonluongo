import SwiftUI
import SwiftData
import LiftingKit

/// Every block the lifter has been given, the one he is on first — the Blocks
/// tab.
///
/// **What it does.** Groups the blocks under two headings, `Current` and
/// `Earlier`, and draws one card each: the name, the dates, and how much of it
/// has been logged. Tapping a card opens it in full. It exists because the tab
/// used to show one block — the newest — and every block before it became
/// unreachable the moment a new one arrived, even though every set logged
/// against it is still in the record and still goes to Claude. The record was
/// navigable in the export and nowhere on the phone.
///
/// **The grouping is the point.** Every block was its own section, headed by its
/// dates, which made four blocks read as four equal things with one word of
/// difference buried in a subtitle. One block is being trained and the rest are
/// history; that is a difference in standing, not in quality, and a heading says
/// it in a word without ranking anything. The glyph and the tint follow the
/// heading — neither carries it alone, and a block behind him is drawn quietly
/// rather than struck out, because the record cannot tell a block he finished
/// from one a new plan replaced and must not imply it can.
///
/// **How it is used.** The second tab. It reads the store directly, as a tab
/// addressed by nothing must, and hands each block to `BlockView` — the screen
/// that already drew a whole block, now reached by name instead of by being the
/// only one.
///
/// **What it depends on.** `TrainingPlan` from Store, `PlansListing` for every
/// string it prints and for the standing it groups by, and the shared
/// `IconCircleRow` and `NoBlockView`. It writes nothing.
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
                    section(.current)
                    section(.earlier)
                }
            }
        }
        .navigationTitle("Blocks")
    }

    /// One group, or nothing at all when it holds no blocks — an empty
    /// `Current` heading would announce a block that does not exist, which is
    /// exactly the day after the last one ended.
    @ViewBuilder
    private func section(_ standing: PlansListing.Standing) -> some View {
        let blocks = plans.filter { PlansListing.standing(of: $0) == standing }
        if !blocks.isEmpty {
            Section(standing.heading) {
                ForEach(blocks) { plan in
                    BlockCard(
                        plan: plan,
                        standing: standing,
                        subtitle: PlansListing.subtitle(of: plan, calendar: calendar),
                        profile: profile
                    )
                }
            }
        }
    }
}

/// One block, as a card in its group.
///
/// **The standing is said three ways and coloured fourth.** The heading above
/// the card says it in a word, the glyph changes shape with it — the dumbbell
/// the app draws training with, against a calendar for a block that is now a
/// date — the row's own VoiceOver label repeats the word, since a heading is a
/// separate element to a screen reader, and only then does the tint follow.
/// Nothing here is a badge or a score: the app decides nothing about a block,
/// including whether it went well.
///
/// The card states what the block is, when it ran, and how much of it has been
/// logged, and stops. A block that prescribes nothing yet says so rather than
/// counting to zero, and one nobody has trained yet omits the logged count
/// entirely.
private struct BlockCard: View {

    let plan: TrainingPlan
    let standing: PlansListing.Standing
    /// The dates and counts, already phrased. Passed in rather than computed
    /// here so the whole line comes from the one place that phrases it.
    let subtitle: String
    let profile: UserProfile

    private var title: String { PlansListing.title(of: plan) }

    var body: some View {
        NavigationLink {
            BlockView(plan: plan, profile: profile)
        } label: {
            IconCircleRow(
                systemImage: standing == .current ? "dumbbell.fill" : "calendar",
                tint: standing == .current ? .accentColor : .secondary,
                title: title,
                subtitle: subtitle
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(standing.spoken), \(subtitle)")
        }
    }
}
