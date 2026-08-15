import Foundation
import LiftingKit

/// Where an exported `TrainingSnapshot` goes.
///
/// The one seam between producing a snapshot and putting it somewhere Claude
/// can read it. Conform a fake to it in tests; the app uses
/// `SnapshotFileWriter`. When the loop moves off the local machine, a second
/// implementation is the only thing that changes.
///
/// Depends on: `TrainingSnapshot` from `LiftingKit`.
protocol SnapshotWriting: Sendable {
    /// Writes the snapshot, replacing any earlier one. Throws rather than
    /// failing quietly: a snapshot that did not land leaves a reader with
    /// stale data, which is worse than none because it does not look absent.
    func write(_ snapshot: TrainingSnapshot) throws
}

/// Writes the snapshot as JSON into a directory on disk.
///
/// Build one with the directory the file belongs in and call `write(_:)` when
/// the app backgrounds. The write is atomic, so a reader never sees a
/// half-written document — a truncated snapshot would decode as a lifter with
/// less history than he has. Encoding goes through
/// `TrainingSnapshot.makeEncoder()` so the file matches what the server
/// expects to decode.
///
/// Depends on: `TrainingSnapshot` from `LiftingKit`, `FileManager`.
struct SnapshotFileWriter: SnapshotWriting {

    /// The document's name, fixed so a reader can find it without being told.
    static let filename = "snapshot.json"

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Writes into the app's own Documents directory.
    ///
    /// Throws if the directory cannot be resolved, rather than substituting a
    /// path that would look like a successful export into nowhere.
    init() throws {
        directory = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
    }

    func write(_ snapshot: TrainingSnapshot) throws {
        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        try data.write(to: directory.appending(path: Self.filename), options: .atomic)
    }
}
