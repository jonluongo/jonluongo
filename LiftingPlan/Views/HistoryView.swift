import SwiftUI
import SwiftData

/// Every block behind him, newest first.
///
/// **What it does.** Draws the blocks the user has finished with, each headed by
/// the days it was trained over, with its sessions beneath in the order they
/// were done.
///
/// **Why it is not on the training screen.** That screen answers *what am I
/// doing*, and a list that grows without bound pushes the answer further down
/// every week. The block he is on is the whole of the front page; everything
/// finished is one tap away and reads backwards, the way anything looked up is.
///
/// **The headings are dates, not block numbers.** A block ordinal is a fact
/// about the plan's structure and means nothing to somebody looking back —
/// *Aug 12 – Sep 2* is how a training log is searched. Blocks run continuously
/// and never restart, so the ordinal is not lost; it is simply not what the
/// heading is for.
///
/// **What it depends on.** `Session` from Store, `BlockHistory` for the split
/// and the dates, and `SessionRow`. It reads and writes nothing.
struct HistoryView: View {

    @Query(sort: [SortDescriptor(\Session.blockOrdinal), SortDescriptor(\Session.ordinal)])
    private var sessions: [Session]

    @Environment(\.dismiss) private var dismiss

    private var blocks: [(ordinal: Int, sessions: [Session])] {
        BlockHistory.past(of: sessions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    // The ordinary state of somebody on their first block, which
                    // must not read as a failure to load.
                    ContentUnavailableView(
                        "Nothing finished yet",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Blocks you have trained through show up here."))
                } else {
                    list
                }
            }
            .background(Palette.surface)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem("Close history") { dismiss() }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(blocks, id: \.ordinal) { block in
                Section(BlockHistory.dateRange(of: block.sessions)
                    ?? SessionListing.blockTitle(block.ordinal)) {
                    ForEach(block.sessions, id: \.persistentModelID) { session in
                        // **Read-only, and the row says so by not being a
                        // button.** A finished block is the record; opening a
                        // session from here would offer to log against work
                        // already done.
                        SessionRow(session: session, standing: .finished)
                            .panelRow(fillsPanel: true, isRecorded: true)
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
