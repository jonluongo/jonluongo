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

    @State private var openSession: Session?
    @State private var showingProgram = false
    @State private var showingAccount = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                NoTrainingView()
            } else {
                list
            }
        }
        .background(Palette.surface)
        .navigationTitle("Training")
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
        }
        // **The stack is what gives the session a bar to hang its X on.**
        // A `fullScreenCover` presents no navigation of its own, so without this
        // the toolbar is defined and never drawn — and the user has no way out
        // of the session at all.
        .fullScreenCover(item: $openSession) { session in
            NavigationStack { ActiveWorkoutView(session: session) }
        }
        .sheet(isPresented: $showingProgram) { ProgramSheet() }
        .sheet(isPresented: $showingAccount) { AccountView() }
    }

    private var list: some View {
        List {
            ForEach(SessionListing.blocks(of: sessions), id: \.ordinal) { block in
                Section(SessionListing.blockTitle(block.ordinal)) {
                    ForEach(block.sessions, id: \.persistentModelID) { session in
                        let standing = SessionListing.standing(
                            of: session, current: current)
                        Button { openSession = session } label: {
                            SessionRow(session: session, standing: standing)
                        }
                        // **One session, one panel.** They shared a panel and
                        // were divided by a hairline; the gap between panels
                        // says the same thing without a line, and a finished
                        // session can then be coloured rather than only marked.
                        //
                        // `fillsPanel` because the panel *is* the row here. The
                        // default row inset is `contentInset` — the room content
                        // gets inside a panel — so applying it to the panel
                        // itself indented every one of them twice.
                        .panelRow(fillsPanel: true, isRecorded: standing == .finished)
                        .listRowSeparator(.hidden)
                    }
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
private struct SessionRow: View {

    let session: Session
    let standing: SessionListing.Standing
    var body: some View {
        HStack(spacing: Spacing.standard) {
            // A day he marked nothing carries nothing: a glyph the app chose
            // would be the app deciding what a session trains.
            if let icon = session.icon { SessionIconView(icon: icon) }
            Text(SessionListing.sessionTitle(session))
                .font(.supersetTitle)
                // **Emphasis by taking it away, not by adding it.** The session
                // he is on looked exactly like one three weeks out, so opening
                // the app to train meant counting down the list to find today.
                // The standing was computed and spent entirely on the
                // accessibility label — the screen reader knew and the screen
                // did not.
                //
                // Nothing is added to say it: what is behind him is already
                // coloured and marked, and what is ahead of him recedes. No new
                // glyph, no second use of the accent, which has one job in this
                // app and keeps it.
                .foregroundStyle(standing == .upcoming ? Palette.muted : Palette.ink)
            Spacer(minLength: Spacing.snug)
            // `showsEmpty: false` — a list marks only what is done. An outline
            // on every unfinished row puts a box beside every session, and a
            // mark that appears everywhere distinguishes nothing.
            RecordedMark(isRecorded: standing == .finished, showsEmpty: false)
            DisclosureChevron()
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
private struct NoTrainingView: View {
    var body: some View {
        ContentUnavailableView(
            "No training yet",
            systemImage: "figure.strengthtraining.traditional",
            description: Text("Your coach has not written a block yet."))
    }
}
