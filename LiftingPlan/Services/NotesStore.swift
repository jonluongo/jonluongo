import Foundation
import LiftingKit

/// The two markdown files the coach writes and the app renders.
///
/// **What it does.** Keeps a local copy of `user.md` and `program.md` and hands
/// their text to whatever draws it. It parses nothing: the app renders these and
/// never reads a value out of them, because the moment a number has to come out
/// of prose, that number belongs in a table.
///
/// **Local copy, iCloud mirror.** The container is the sync channel, not the
/// source. Reading straight from it would leave the account screen blank
/// whenever iCloud is unreachable — which is a state this phone is actually in —
/// and a screen that describes the lifter should not depend on the network.
/// Same arrangement as the store itself.
///
/// **A file nobody has written yet reads as its template**, not as nothing. An
/// empty file gives an anchored edit nothing to anchor to, so the coach's first
/// write would have no `old_text` to match; the headings are what he edits
/// beneath.
///
/// **What it depends on.** `DocumentFolder` from LiftingKit for the names, and
/// `FileManager`. It writes only the local mirror, never the container: the
/// coach owns these files.
@MainActor
@Observable
final class NotesStore {

    /// Which of the two files.
    enum Note: String, CaseIterable {
        case user = "user.md"
        case program = "program.md"

        /// What an unwritten file says, and what the coach edits beneath.
        var template: String {
            switch self {
            case .user:
                """
                # The lifter

                ## Objective
                _Not yet stated._

                ## Background
                _Not yet stated._

                ## Injuries and limits
                _None on record._

                ## What he avoids, and why
                _Nothing on record._

                ## Equipment
                _Not yet stated._

                ## Bodyweight
                _No readings on record._
                """
            case .program:
                """
                # This programme

                ## The approach
                _Not yet stated._

                ## What is being progressed
                _Not yet stated._

                ## What to watch
                _Not yet stated._
                """
            }
        }
    }

    private let directory: URL

    /// Built with the app's local support directory. A test passes its own.
    init(directory: URL) {
        self.directory = directory
    }

    /// The text of one note, or its template when nothing has been written.
    func text(of note: Note) -> String {
        let url = directory.appending(path: note.rawValue)
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return note.template }
        return text
    }

    /// Takes a copy of what arrived in the shared folder.
    ///
    /// Throwing rather than silent: a note that failed to mirror leaves the
    /// screen showing an older one, and the lifter should be told rather than
    /// shown stale prose as though it were current.
    func mirror(_ text: String, as note: Note) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(
            to: directory.appending(path: note.rawValue), options: .atomic)
    }
}
