import Foundation

/// A string-backed identifier for a category that is defined by data rather
/// than by code — muscle groups, equipment, movement patterns.
///
/// Use it wherever values arrive from the bundled catalog. A closed `enum`
/// would make the day the catalog gains a value a decoding failure; a
/// conforming type instead preserves the unrecognized value intact.
///
/// Conformers declare `known` for the values this build understands, which is
/// what UI pickers and validation should enumerate. `rawValue` is canonicalized
/// on creation — trimmed and lowercased — so casing never fragments identity.
///
/// Depends on: Foundation only. Vended by the `LiftingKit` package, which both
/// the iOS app and the macOS MCP server link, so both agree on what a muscle
/// group or a piece of equipment is.
public protocol ExtensibleTaxonomy: RawRepresentable, Codable, Hashable, Sendable,
                                    CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
    /// The values this build recognizes. Not exhaustive of what may decode.
    static var known: [Self] { get }
}

extension ExtensibleTaxonomy {

    /// Trimmed and lowercased, so `"  Chest "` and `"chest"` are one value.
    ///
    /// Internal: canonicalization is how conformers in this module build
    /// themselves, not something a client does.
    static func canonicalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Whether this build recognizes the value, as opposed to merely carrying it.
    public var isKnown: Bool { Self.known.contains(self) }
}
