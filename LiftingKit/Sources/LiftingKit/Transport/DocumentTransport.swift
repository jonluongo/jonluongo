import Foundation

/// How the app hands a snapshot out and takes a plan or a profile update in.
///
/// Hold one of these wherever the loop is driven — the app writes a
/// `TrainingSnapshot` when it backgrounds and reads a `PlanDocument` or a
/// `ProfileUpdate` when one arrives — and hand a fake to it in tests. There are
/// two inbound documents because Claude does two things with what he learns:
/// he prescribes training, and he records standing facts about the lifter, who
/// is never asked for them by the app. Nothing above this protocol knows
/// about files, URLs, or iCloud, which is the point: when the loop stops being
/// two machines on one Apple ID and becomes a hosted relay, a second
/// conformance is the only thing that changes. Both document formats, the
/// exporter, the importer, and the MCP tools are already transport-agnostic.
///
/// **`nil` and "broken" are different answers.** `readPlan()` returns `nil`
/// when no plan has been written yet, which is the ordinary state of a lifter
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

    /// The profile update waiting to be applied, or `nil` when there is none.
    ///
    /// Same contract as `readPlan()`: absence is ordinary, corruption throws.
    func readProfileUpdate() throws -> ProfileUpdate?
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
/// snapshot would decode as a lifter with less history than he has. Reads
/// return `nil` only for a file that is not there; a file that is there and
/// malformed throws.
///
/// Depends on: `TrainingSnapshot`, `PlanDocument`, and `FileManager`.
public struct DocumentFolder: DocumentTransport {

    /// The name the app writes and the server reads.
    public static let snapshotFilename = "snapshot.json"
    /// The name the server writes and the app reads.
    public static let planFilename = "plan.json"
    /// The other name the server writes and the app reads: what Claude has
    /// learned about the lifter. A separate file rather than a section of the
    /// plan, because facts about a lifter outlive any one training block.
    public static let profileUpdateFilename = "profile-update.json"

    /// Every file the server writes and the app watches for. A caller that has
    /// to notice arrivals reads this rather than restating the names, so a
    /// document that is written but never watched for cannot happen.
    public static let inboundFilenames = [planFilename, profileUpdateFilename]

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

    public func readProfileUpdate() throws -> ProfileUpdate? {
        guard let data = try contents(of: Self.profileUpdateFilename) else { return nil }
        return try ProfileUpdate.makeDecoder().decode(ProfileUpdate.self, from: data)
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

    /// Puts a profile update where the app will pick it up, replacing any
    /// earlier one.
    ///
    /// Replacing is safe because each update carries its own identity and the
    /// app applies an identity once: an update that has already landed is not
    /// re-imposed when a newer one supersedes the file.
    public func writeProfileUpdate(_ update: ProfileUpdate) throws {
        let data = try ProfileUpdate.makeEncoder().encode(update)
        try data.write(
            to: directory.appending(path: Self.profileUpdateFilename), options: .atomic)
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
    /// a lifter who has not been sent one.
    private static func meansNotThere(_ error: CocoaError) -> Bool {
        error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }
}
