import Foundation

/// How the app hands a snapshot out and takes a plan or a profile update in.
///
/// Hold one of these wherever the loop is driven — the app writes a
/// `TrainingSnapshot` when it backgrounds and reads a `PlanDocument` or a
/// `ProfileUpdate` when one arrives — and hand a fake to it in tests. There are
/// two inbound documents because Claude does two things with what he learns:
/// he prescribes training, and he records standing facts about the user, who
/// is never asked for them by the app. Nothing above this protocol knows
/// about files, URLs, or iCloud, which is the point: when the loop stops being
/// two machines on one Apple ID and becomes a hosted relay, a second
/// conformance is the only thing that changes. Both document formats, the
/// exporter, the importer, and the MCP tools are already transport-agnostic.
///
/// **`nil` and "broken" are different answers.** `readPlan()` returns `nil`
/// when no plan has been written yet, which is the ordinary state of a user
/// who has not been given one, and throws when a plan is there but cannot be
/// read. A conformance that swallowed a decoding failure into `nil` would make
/// a corrupt file look exactly like an empty transport.
///
/// The Mac's side of the loop is the mirror of this one — it reads the snapshot
/// and writes the plan — and lives on the concrete type rather than here, so
/// this protocol states only what the app depends on.
///
/// Depends on: `TrainingSnapshot` and `PlanDocument`.
public protocol DocumentTransport: Sendable {

    /// Puts the snapshot where the coach can read it, replacing any earlier
    /// one.
    ///
    /// Throws rather than failing quietly: a snapshot that did not land leaves
    /// a reader with stale data, which is worse than none because stale data
    /// does not look absent.
    func writeSnapshot(_ snapshot: TrainingSnapshot) throws

    /// The plan waiting to be imported, or `nil` when there is none yet.
    ///
    /// Throws when a plan is present but unreadable. Absence is not a failure;
    /// corruption is.
    func readPlan() throws -> PlanDocument?

    /// One of the coach's markdown notes, or `nil` when he has written none.
    ///
    /// **Text, not a document.** Nothing is parsed out of these: the app renders
    /// them. The moment a value has to come out of prose, that value belongs in
    /// a table instead.
    func readNote(_ note: NoteFile) throws -> String?

    /// Replaces one of the coach's notes with the user's correction, keeping
    /// what it replaced.
    ///
    /// **The coach writes these and the user may still fix one.** A fact about
    /// his own body that is wrong is wrong whoever typed it, and waiting for the
    /// next conversation to correct a name or a date is the app making him ask
    /// permission to be accurate. The file stays the unit — he edits the
    /// markdown the coach edits, not a form the app invents — so there is one
    /// shape of edit and nothing to reconcile.
    ///
    /// **It writes to the shared folder, not the local mirror.** A correction
    /// the coach never sees is worse than none: he would go on prescribing
    /// against the thing that was wrong, and the next mirror down would erase
    /// the fix. The prior version is kept beside it first, by the same rule that
    /// keeps one before every anchored edit.
    func writeNote(_ text: String, as note: NoteFile) throws

    /// Keeps a plan that was taken in, under its own ID, so the prescription
    /// survives the block being rewritten.
    ///
    /// **`Session.sourceDocumentID` is a pointer, and this is what it points
    /// at.** Every session records the ID of the document that prescribed it,
    /// and `plan.json` is replaced by the next plan the coach writes — so
    /// without this the ID names a document that no longer exists anywhere. A
    /// plan is an archive: he wrote it, it is the only copy, and the
    /// prescribed-versus-performed comparison is the coaching signal.
    ///
    /// **Writing the same plan twice is not an error and does not rewrite it.**
    /// The folder is announced whenever anything in it changes, including the
    /// snapshot this app writes, so a plan is re-read many times. The first copy
    /// is the one kept — never mutated, by the same reasoning that makes a
    /// trained prescription permanent.
    func archivePlan(_ plan: PlanDocument) throws
}

/// The documents of the loop, living side by side in one directory.
///
/// Build one with the directory both machines can see — on the phone that is
/// the app's iCloud Documents folder, on the Mac the same container under
/// `~/Library/Mobile Documents` — and the file names take care of themselves.
/// The app uses `writeSnapshot(_:)` and `readPlan()`; the macOS MCP server uses
/// the mirror pair, `readSnapshot()` and `writePlan(_:)`. Neither side is told
/// a file name, so neither can disagree about one.
///
/// Writes are atomic, so a reader never sees half a document — a truncated
/// snapshot would decode as a user with less history than he has. Reads
/// return `nil` only for a file that is not there; a file that is there and
/// malformed throws.
///
/// Depends on: `TrainingSnapshot`, `PlanDocument`, and `FileManager`.
public struct DocumentFolder: DocumentTransport {

    /// The name the app writes and the server reads.
    public static let snapshotFilename = "snapshot.json"
    /// The name the server writes and the app reads.
    public static let planFilename = "plan.json"
    /// Where plans already taken in are kept, one file per document, named by
    /// its ID. A folder rather than a suffix on the name, so the two documents
    /// of the live loop stay the only things at the top level.
    public static let planArchiveFolder = "plans"
    /// Where the version kept before each note edit goes.
    public static let noteVersionFolder = "notes"
    /// Every file the server writes and the app watches for. A caller that has
    /// to notice arrivals reads this rather than restating the names, so a
    /// document that is written but never watched for cannot happen.
    public static let inboundFilenames = [planFilename] + NoteFile.allCases.map(\.filename)

    private let directory: URL

    /// - Parameter directory: the folder holding both documents. It is not
    ///   created here — a transport pointed at a folder that does not exist
    ///   throws on write rather than quietly making one somewhere unshared.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The folder this transport reads and writes, for a caller that has to
    /// watch it for changes.
    public var url: URL { directory }

    // MARK: - The app's direction

    public func writeSnapshot(_ snapshot: TrainingSnapshot) throws {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        try data.write(to: directory.appending(path: Self.snapshotFilename), options: .atomic)
    }

    public func readPlan() throws -> PlanDocument? {
        guard let data = try contents(of: Self.planFilename) else { return nil }
        return try PlanDocument.makeDecoder().decode(PlanDocument.self, from: data)
    }

    public func readNote(_ note: NoteFile) throws -> String? {
        guard let data = try contents(of: note.filename) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes `plans/<id>.json`, and leaves it alone ever after.
    ///
    /// **The document, not the bytes.** This re-encodes rather than copying
    /// `plan.json` across, so what is kept is the prescription and not the
    /// coach's whitespace. The round-trip suite is what says those are the same
    /// thing; byte-fidelity would only serve forensics about his formatting,
    /// which nothing needs.
    ///
    /// The folder is created on write only, for the same reason the container's
    /// is: a transport pointed somewhere that does not exist holds no archive,
    /// and reading must not conjure one.
    public func archivePlan(_ plan: PlanDocument) throws {
        let folder = directory.appending(path: Self.planArchiveFolder)
        let file = folder.appending(path: "\(plan.id.uuidString).json")
        guard !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PlanDocument.makeEncoder().encode(plan).write(to: file, options: .atomic)
    }

    /// Every plan kept, newest last, for a reader asking what was prescribed
    /// before. Empty when none has been archived yet — which is absence, not
    /// failure, exactly as an unwritten plan is.
    public func archivedPlans() throws -> [PlanDocument] {
        let folder = directory.appending(path: Self.planArchiveFolder)
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where Self.meansNotThere(error) {
            return []
        }
        return try files
            .filter { $0.pathExtension == "json" }
            .map { try PlanDocument.makeDecoder().decode(
                PlanDocument.self, from: try Data(contentsOf: $0)) }
            .sorted { $0.generatedAt < $1.generatedAt }
    }

    // MARK: - The server's direction

    /// The snapshot the app last wrote, or `nil` when it has not written one.
    ///
    /// Throws when a snapshot is present but malformed, for the same reason
    /// `readPlan()` does: a coach reading nothing knows he is reading nothing.
    public func readSnapshot() throws -> TrainingSnapshot? {
        guard let data = try contents(of: Self.snapshotFilename) else { return nil }
        return try TrainingSnapshot.makeDecoder().decode(TrainingSnapshot.self, from: data)
    }

    /// Puts a plan where the app will pick it up, replacing any earlier one.
    public func writePlan(_ plan: PlanDocument) throws {
        let data = try PlanDocument.makeEncoder().encode(plan)
        try data.write(to: directory.appending(path: Self.planFilename), options: .atomic)
    }

    /// Puts one of the coach's notes where the app will pick it up.
    ///
    /// **Whole-file, and that is why the tool that calls it is an anchored
    /// edit.** Prose has no refusal machinery of its own, so the guard is at the
    /// other end: `update_notes` states the text it expects to replace and is
    /// refused if that text is not there.
    /// Keeps the version about to be replaced, in the versions folder.
    ///
    /// **A few kilobytes against losing what the coach wrote.** An anchored edit
    /// is the guard — it refuses when the text it expects is not there — and
    /// this is the backstop for anything it still gets wrong. Named by the
    /// moment it was kept, so the folder reads as a history rather than as one
    /// backup that keeps being overwritten.
    ///
    /// **It goes in `notes/`, not beside the live file.** One copy per edit
    /// accumulates without bound, and the container root is where the loop's
    /// live documents are — the four names both machines look for. Dated copies
    /// piling up among them make the one folder a person has to read to see
    /// what the loop is doing unreadable, for files nothing reads back. The
    /// plan archive is in `plans/` for the same reason.
    /// **Stamped to the millisecond, because two edits land in one second.**
    /// A coach fixing two sections of a note makes two tool calls back to back,
    /// and at second precision the second copy overwrote the first — leaving one
    /// backup that keeps being overwritten, which is the thing this is named to
    /// avoid.
    public func keepCopy(of text: String, as note: NoteFile) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let folder = directory.appending(path: Self.noteVersionFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(
            to: folder.appending(path: "\(note.basename).\(stamp).md"), options: .atomic)
    }

    public func writeNote(_ text: String, as note: NoteFile) throws {
        try Data(text.utf8).write(
            to: directory.appending(path: note.filename), options: .atomic)
    }

    // MARK: - Absence, told apart from failure

    /// Reads a file, answering `nil` for one that is not there and rethrowing
    /// everything else.
    ///
    /// Only "no such file" becomes `nil`. A permissions failure, an unreadable
    /// volume, or a folder that is not there are all real errors and are
    /// propagated — the caller must be able to tell "no plan yet" from "the
    /// transport is not working".
    private func contents(of filename: String) throws -> Data? {
        do {
            return try Data(contentsOf: directory.appending(path: filename))
        } catch let error as CocoaError where Self.meansNotThere(error) {
            return nil
        }
    }

    /// Whether a read failure means the file simply is not there yet.
    ///
    /// A missing containing folder counts: a transport pointed at a folder
    /// iCloud has not created yet holds no plan, which is exactly the state of
    /// a user who has not been sent one.
    private static func meansNotThere(_ error: CocoaError) -> Bool {
        error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }
}
