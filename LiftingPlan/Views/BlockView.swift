import SwiftUI
import SwiftData
import LiftingKit

/// The training, block by block — the screen the app opens on.
///
/// **What it does.** Lists every block the coach has written, each as a
/// subheading over its sessions, with the session the user is on first among
/// the unfinished. Tapping one opens it.
///
/// **It is the root, and there is nothing above it.** There used to be a list of
/// routines underneath with one routine pushed onto it, and logic to decide when
/// the app might replace what was on the stack. There are no routines: blocks
/// run continuously and this shows all of them, so the list *is* the app.
///
/// **A block is a number.** What makes block 3 an accumulation block is a line
/// the coach wrote in `PROGRAM.md`, which is a tap away rather than a label
/// here.
///
/// **What it depends on.** `Session` from Store, `SessionListing` for what each
/// row says, and the two sheets its toolbar opens. It draws and never decides.
struct BlockView: View {

    @Query(sort: [SortDescriptor(\Session.blockOrdinal), SortDescriptor(\Session.ordinal)])
    private var sessions: [Session]

    /// The session he is on: the first unfinished one anywhere in the timeline.
    /// Worked out once here, because being current is a fact about the whole
    /// record rather than about a block.
    private var current: Session? { SessionListing.current(in: sessions) }

    /// Presented by `RootView`, so the bar that returns to a session and the
    /// session itself are siblings rather than one on top of the other.
    @Binding var openSession: Session?
    @State private var showingProgram = false
    @State private var showingAccount = false
    @State private var showingHistory = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                NoBlockView()
            } else {
                list
            }
        }
        .background(Palette.surface)
        // **No title.** *Training* named the app on the app's only screen —
        // a word that never varies, in the largest type on the page, above the
        // one thing that does. The block heading is the first line now, which
        // is the first thing that is actually information. The stack stays: the
        // toolbar and the session's cover both hang off it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // **Both marks are bare outlines, and that is the whole reason
                // they match.** `person.crop.circle` is an enclosed glyph: it
                // fills its optical box edge to edge, so beside a narrow upright
                // clipboard it read as a solid disc next to a hairline and the
                // pair looked mis-sized. SF Symbols balances within an enclosure
                // style, not across one, and there is no `clipboard.circle` to
                // match it with — so the circle goes instead.
                Button { showingProgram = true } label: {
                    Label("Program", systemImage: "clipboard")
                }
                Button { showingAccount = true } label: {
                    Label("Account", systemImage: "person")
                }
            }
            // **A capsule of its own, because it is a different kind of thing.**
            // The two before it open what the coach wrote about the training in
            // front of him; this one leaves the present entirely. Grouped with
            // them it read as a third document. `ToolbarSpacer` is what splits
            // one glass capsule into two.
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingHistory = true } label: {
                    Label("History", systemImage: "clock")
                }
            }
        }
        .sheet(isPresented: $showingProgram) { NoteSheet(note: .program) }
        .sheet(isPresented: $showingAccount) { NoteSheet(note: .account) }
        .sheet(isPresented: $showingHistory) { HistoryView() }
    }

    /// One block's sessions as rows. Shared by the block he is on and any ahead
    /// of it, so an early block is drawn exactly as the current one is — it is
    /// the same thing, further off.
    @ViewBuilder
    private func rows(_ sessions: [Session]) -> some View {
        ForEach(sessions, id: \.persistentModelID) { session in
            let standing = SessionListing.standing(of: session, current: current)
            Button { openSession = session } label: {
                SessionRow(session: session, standing: standing)
            }
            // **One session, one panel.** They shared a panel and were divided
            // by a hairline; the gap between panels says the same thing without
            // a line, and a finished session can then be coloured rather than
            // only marked.
            //
            // `fillsPanel` because the panel *is* the row here. The default row
            // inset is `contentInset` — the room content gets inside a panel —
            // so applying it to the panel itself indented every one twice.
            .panelRow(fillsPanel: true, isRecorded: standing == .finished)
            .listRowSeparator(.hidden)
        }
    }

    private var list: some View {
        List {
            // **The block he is on, and nothing else.** Every block ever
            // prescribed was listed here, so the answer to *what am I doing*
            // moved further down the screen every week and the top of the app
            // filled up with training that is over. What is finished is a
            // record, and a record is looked up rather than scrolled past —
            // `HistoryView` holds it.
            Section(SessionListing.blockTitle(BlockHistory.currentOrdinal(of: sessions) ?? 1)) {
                rows(BlockHistory.current(of: sessions))
            }
            // **A block he has not reached yet is still ahead of him.** The
            // coach writes one block at a time and the format refuses a document
            // stating two, so this is not the ordinary path — but a block that
            // exists and is drawn nowhere is worse than one that is early:
            // prescriptions on the phone that no screen admits to. The refusal
            // is where *do not do this* is said; the list only reports.
            ForEach(BlockHistory.upcoming(of: sessions), id: \.ordinal) { block in
                Section(SessionListing.blockTitle(block.ordinal)) {
                    rows(block.sessions)
                }
            }
        }
        // **Plain, because the panels are the grouping.** `.insetGrouped` adds
        // its own section margins on top of the row insets, so every panel was
        // indented twice — a gutter about double what it should be.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// One session in the list: what it is called, and whether it is in the record.
///
/// **The mark varies along one axis.** A finished session carries the app's one
/// recorded mark and an unfinished one carries nothing — the same distinction
/// everywhere it appears, rather than one glyph for the block being trained and
/// another for one behind him, which was two subjects in one slot.
struct SessionRow: View {

    let session: Session
    let standing: SessionListing.Standing
    /// Whether tapping this row opens the session.
    ///
    /// **The chevron is the claim, so it is drawn only where the claim is
    /// true.** `HistoryView` states in its own comment that a finished block is
    /// read-only and says so *by not being a button* — and then drew the mark
    /// that means *this opens*, on a row that opened nothing. A chevron that
    /// leads nowhere is the same failure as a label naming a control that is not
    /// there. Every row on the block being trained does open, which is why this
    /// defaults to true and why the contradiction survived being rendered.
    var opens: Bool = true

    var body: some View {
        HStack(spacing: Spacing.standard) {
            // A day he marked nothing carries nothing: a glyph the app chose
            // would be the app deciding what a session trains.
            if let icon = session.icon { SessionIconView(icon: icon) }
            Text(SessionListing.sessionTitle(session))
                .font(.supersetTitle)
                // **Every session in the block is a session, at full strength.**
                // A later one used to recede to `muted` so the one he was on
                // could be found — which was worth doing when this screen listed
                // every block ever prescribed and today was somewhere down it.
                // The front page is one block now: three or four rows, all of
                // them his to train this week, and greying two thirds of a short
                // list makes most of the screen look disabled to save a glance
                // that is no longer needed.
                //
                // What is *behind* him still reads differently, and needs no
                // help from the type: the panel is on the recorded wash and
                // carries the mark.
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.snug)
            // `showsEmpty: false` — a list marks only what is done. An outline
            // on every unfinished row puts a box beside every session, and a
            // mark that appears everywhere distinguishes nothing.
            RecordedMark(isRecorded: standing == .finished, showsEmpty: false)
            if opens { DisclosureChevron() }
        }
        .padding(.horizontal, PanelMetrics.edge)
        // **Tall enough not to read as a pill.** One row in a panel with the
        // app's corner radius on it is wider than it is high, and a rounded
        // rectangle that short stops looking like a panel and starts looking
        // like a capsule. The radius is right; the height was not.
        .padding(.vertical, Spacing.major)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(SessionListing.sessionTitle(session)), \(standing.spoken)")
    }
}

/// What the list shows before the coach has written anything.
///
/// **It states the situation and asks for nothing.** There is no button here: a
/// plan arrives from a conversation with the coach, and a control offering to
/// make one would be the app deciding what somebody should train.
/// What the app says before a plan exists.
///
/// **It names what is missing, and what is missing has to be a thing.**
/// *No training yet* put a mass noun where a count noun belongs: there is no
/// such object as *a training*, so the sentence never says what is absent.
///
/// **And it is the same thing the rest of the app calls it.** The heading said
/// *workout plan* while the line under it asked for a *block*, and the screen
/// behind them both is headed *Block 1* — two words for one object, in adjacent
/// sentences, which is how a third one gets invented. A plan is the document the
/// coach writes and states one block; a block is what the user is shown, what
/// `HistoryView` counts in *No finished blocks yet*, and so what is absent here.
/// The heading is the fact, the line under it is the one action, and the type is
/// named for the same thing the heading is.
///
/// **The mark is the missing object too, not a person.** It drew a figure
/// lifting, which is a picture of the activity rather than of what is absent —
/// the same mistake the words were making. `rectangle.stack` is a stack of
/// panels: the blocks that will be here, and the shape the list itself takes.
private struct NoBlockView: View {
    var body: some View {
        ContentUnavailableView(
            "No training block yet",
            systemImage: "rectangle.stack",
            description: Text("Ask your coach for one and it will show up here."))
    }
}
