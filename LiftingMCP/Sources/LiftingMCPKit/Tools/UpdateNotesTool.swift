import Foundation
import LiftingKit

/// Editing one of the coach's two markdown notes.
///
/// **An anchored edit, because prose has no refusal machinery of its own.**
/// Every other inbound format here is versioned and refuses a key it does not
/// have; markdown has no shape to violate. So the guard is that the writer
/// states the text he expects to replace — if it is not there, or appears more
/// than once, nothing is written and he is told which.
///
/// **A whole-file write would lose whatever he had not read**, silently, which
/// is the one failure this project does not accept: it reports success.
///
/// **A copy is kept before every edit.** The notes are a few kilobytes and the
/// coach is the only writer; keeping the previous version costs nothing and is
/// the backstop for anything an anchored edit still gets wrong.
///
/// **What it depends on.** `NoteFile` and `DocumentTransport` from LiftingKit.
/// It parses nothing out of what it writes.
extension ToolRunner {

    func updateNotes(_ arguments: JSONValue) -> ToolOutcome {
        guard let rawFile = arguments["file"]?.stringValue,
            let file = NoteFile(rawValue: rawFile)
        else {
            return .failure(
                "update_notes needs a 'file' argument: "
                    + NoteFile.allCases.map(\.rawValue).joined(separator: " or ") + ".")
        }
        guard let oldText = arguments["oldText"]?.stringValue,
            let newText = arguments["newText"]?.stringValue
        else {
            return .failure(
                "update_notes needs 'oldText' — the text to replace, exactly as it appears — "
                    + "and 'newText' to put in its place. Read the note first rather than "
                    + "guessing at what is in it.")
        }

        let current: String
        do {
            current = try documents.readNote(file) ?? file.template
        } catch {
            return .failure("Could not read \(file.filename): \(error.localizedDescription)")
        }

        let occurrences = current.components(separatedBy: oldText).count - 1
        guard occurrences > 0 else {
            return .failure(
                "That text is not in \(file.filename), so nothing was written. Read the note "
                    + "and quote it exactly — including the heading above the line, if you are "
                    + "replacing a section.")
        }
        guard occurrences == 1 else {
            return .failure(
                "That text appears \(occurrences) times in \(file.filename), so there is no "
                    + "telling which was meant and nothing was written. Include enough "
                    + "surrounding text to name one of them.")
        }

        do {
            try documents.keepCopy(of: current, as: file)
            try documents.writeNote(
                current.replacingOccurrences(of: oldText, with: newText), as: file)
        } catch {
            return .failure("Could not write \(file.filename): \(error.localizedDescription)")
        }

        return .report([
            "file": .string(file.filename),
            "replaced": .integer(oldText.count),
            "note": .string(
                "Written. The app renders this file; nothing is parsed out of it, so what you "
                    + "wrote is what the lifter reads."),
        ])
    }
}
