import Foundation

/// Where this run of the server looks for the two documents.
///
/// Build one with `resolve(arguments:environment:home:)` at launch and hand its
/// `documentsDirectory` to a `DocumentFolder`. The path is deliberately
/// overridable — the shared iCloud folder only exists on a Mac signed into the
/// user's Apple ID with the app installed on a device, so a fixture folder
/// has to be reachable for testing and for a dry run before the phone has ever
/// backgrounded.
///
/// Precedence is most explicit first: a `--documents` argument beats the
/// `LIFTINGPLAN_DOCUMENTS_DIR` environment variable, which beats the app's real
/// iCloud Documents folder. Nothing is created here; a folder that is not there
/// is reported by the tools as "the app has not written a snapshot yet", which
/// is the true state.
///
/// Depends on: Foundation only.
public struct ServerConfiguration: Sendable, Hashable {

    /// The ubiquity container in `LiftingPlan.entitlements`. iCloud spells it
    /// on disk with `~` where the identifier has `.`, which is the system's
    /// convention and not a choice this server makes.
    public static let containerIdentifier = "iCloud.com.jonluongo.LiftingPlan"

    /// The environment variable that repoints the server at another folder.
    public static let directoryEnvironmentKey = "LIFTINGPLAN_DOCUMENTS_DIR"

    /// The command-line flag that repoints the server at another folder.
    public static let directoryArgument = "--documents"

    /// The folder holding `snapshot.json` and `plan.json`.
    public let documentsDirectory: URL

    /// Whether the folder came from the default iCloud location rather than
    /// from an argument or the environment. Reported at startup so the owner
    /// can see which folder a run is actually using.
    public let isDefaultLocation: Bool

    public init(documentsDirectory: URL, isDefaultLocation: Bool) {
        self.documentsDirectory = documentsDirectory
        self.isDefaultLocation = isDefaultLocation
    }

    /// The app's iCloud Documents folder for a given home directory.
    ///
    /// Derived rather than written out, so the container identifier appears
    /// once and the app's entitlement and this path cannot drift apart.
    public static func defaultDocumentsDirectory(home: URL) -> URL {
        let onDiskContainer = containerIdentifier.replacingOccurrences(of: ".", with: "~")
        return home
            .appending(path: "Library/Mobile Documents")
            .appending(path: onDiskContainer)
            .appending(path: "Documents")
    }

    /// Reads the folder out of the launch context.
    ///
    /// - Parameters:
    ///   - arguments: the process arguments *including* argv[0], as
    ///     `CommandLine.arguments` gives them.
    ///   - environment: the process environment.
    ///   - home: the user's home directory.
    ///
    /// Throws `ConfigurationError.missingArgumentValue` when `--documents` is
    /// given with nothing after it — a run that silently fell back to iCloud
    /// there would look like it honoured the flag.
    public static func resolve(
        arguments: [String],
        environment: [String: String],
        home: URL
    ) throws -> ServerConfiguration {
        if let flag = arguments.firstIndex(of: directoryArgument) {
            let valueIndex = arguments.index(after: flag)
            guard valueIndex < arguments.endIndex else {
                throw ConfigurationError.missingArgumentValue(directoryArgument)
            }
            return ServerConfiguration(
                documentsDirectory: URL(filePath: arguments[valueIndex]),
                isDefaultLocation: false
            )
        }
        if let path = environment[directoryEnvironmentKey], !path.isEmpty {
            return ServerConfiguration(
                documentsDirectory: URL(filePath: path), isDefaultLocation: false
            )
        }
        return ServerConfiguration(
            documentsDirectory: defaultDocumentsDirectory(home: home), isDefaultLocation: true
        )
    }
}

/// Why the server could not work out how it was meant to run.
///
/// Thrown by `ServerConfiguration.resolve` and shown on standard error before
/// the process exits, since a server that cannot find its folder has nothing
/// useful to answer. Depends on: Foundation only.
public enum ConfigurationError: Error, LocalizedError, Equatable {

    /// A flag that takes a path was given without one.
    case missingArgumentValue(String)

    public var errorDescription: String? {
        switch self {
        case .missingArgumentValue(let flag):
            "\(flag) needs a folder path after it, for example "
                + "`\(flag) ~/Library/Mobile\\ Documents/iCloud~com~jonluongo~LiftingPlan/Documents`."
        }
    }
}
