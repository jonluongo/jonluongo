import SwiftUI
import SwiftData
import LiftingKit

/// The training, block by block — the screen the app opens on.
///
/// **What it does.** Lists every block the coach has written, each as a
/// subheading over its sessions, with the session the lifter is on first among
/// the unfinished. Tapping one opens it.
///
/// **It is the root, and there is nothing above it.** There used to be a list of
/// routines underneath with one routine pushed onto it, and logic to decide when
/// the app might replace what was on the stack. There are no routines: blocks
/// run continuously and this shows all of them, so the list *is* the app.
///
/// **A block is a number.** What makes block 3 an accumulation block is a line
/// the coach wrote in `program.md`, which is a tap away rather than a label
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
                Button { showingProgram = true } label: {
                    Label("The programme", systemImage: "text.document")
                }
                Button { showingAccount = true } label: {
                    Label("The lifter", systemImage: "person.crop.circle")
                }
            }
        }
        // **The stack is what gives the session a bar to hang its X on.**
        // A `fullScreenCover` presents no navigation of its own, so without this
        // the toolbar is defined and never drawn — and the lifter has no way out
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
                        Button { openSession = session } label: {
                            SessionRow(
                                session: session,
                                standing: SessionListing.standing(
                                    of: session, current: current))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.snug)
            // `showsEmpty: false` — a list marks only what is done. Drawing an
            // outline on every unfinished row gives the column a box beside
            // every session, and a mark that appears everywhere distinguishes
            // nothing.
            RecordedMark(isRecorded: standing == .finished, showsEmpty: false)
            DisclosureChevron()
        }
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
