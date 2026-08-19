import Foundation

/// How every document this app and its server exchange is written and read.
///
/// **What it does.** Builds the one `JSONEncoder` and the one `JSONDecoder` that
/// `plan.json`, `snapshot.json` and `profile-update.json` all use. Dates are
/// ISO 8601 in both directions, keys are sorted and the output is pretty-printed
/// — a document a person can read in a text editor, and a diff a person can
/// follow.
///
/// **Why it is one place.** It was three: each format carried its own pair of
/// factories with identical bodies. Identical is not the same as *guaranteed
/// identical* — a date strategy changed on one of them and not the others would
/// be invisible until the phone wrote a snapshot the server could not read, and
/// the failure would look like a missing file rather than a mismatched one. The
/// three formats crossing one boundary have to agree about that boundary, so
/// they share the thing that defines it.
///
/// **How it is used.** Each format keeps its own `makeEncoder()` and
/// `makeDecoder()` as the name callers already use; both now return these.
///
/// **What it depends on.** Foundation.
public enum DocumentCoding {

    /// The encoder every document is written with.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The matching decoder. A bare `JSONDecoder` would reject every date the
    /// encoder writes, so nothing may build its own.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
