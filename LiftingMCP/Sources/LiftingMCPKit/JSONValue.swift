import Foundation
import LiftingKit

/// Any JSON value, as a Swift value type.
///
/// Build one with the literal syntax (`["sets": 3, "id": "barbell-squat"]`) to
/// assemble a tool's report, or decode one to read the arguments Claude sent.
/// Every report this server produces is a `JSONValue`, so the shape of an
/// answer is written once and rendered once — nothing here builds JSON by
/// string concatenation, which is how quoting bugs get into a protocol.
///
/// `integer` is a separate case from `number` on purpose: a set count rendered
/// as `3.0` reads as a measurement rather than a count, and JSON Schema
/// validators distinguish the two.
///
/// Depends on: Foundation only.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Reading

extension JSONValue {

    /// The string inside, or `nil` when this is not a string.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The whole number inside. A JSON `3` and a JSON `3.0` both answer `3`;
    /// `3.5` answers `nil` rather than silently truncating.
    public var intValue: Int? {
        switch self {
        case .integer(let value): value
        case .number(let value): value == value.rounded() ? Int(value) : nil
        default: nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// A member of this object, or `nil` when this is not an object or has no
    /// such member. `null` members answer `nil` too, so an argument explicitly
    /// sent as `null` reads the same as one that was omitted.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self, let value = members[key], value != .null else {
            return nil
        }
        return value
    }

    /// The element at `index`, or `nil` when this is not an array or is shorter
    /// than that. The companion to the member subscript above, so a path through
    /// a document that passes through a list — a week, a day, a group's second
    /// exercise — reads as one chain rather than breaking into `arrayValue`.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let values) = self, values.indices.contains(index) else { return nil }
        let value = values[index]
        return value == .null ? nil : value
    }

    /// The strings in an array member, tolerating a bare string in place of a
    /// one-element array — Claude writes `"muscle": "chest"` at least as often
    /// as `"muscle": ["chest"]`, and both plainly mean the same thing.
    /// A member that is neither answers `nil`.
    public func strings(at key: String) -> [String]? {
        switch self[key] {
        case .string(let single): [single]
        case .array(let values): values.compactMap(\.stringValue)
        default: nil
        }
    }
}

// MARK: - Writing

extension JSONValue: Codable {

    /// JSON is untyped on the wire, so decoding means trying each shape in
    /// turn. The `try?`s below discard nothing: a failure means only "not this
    /// type, try the next", and exhausting every one throws a real
    /// `DecodingError` rather than yielding a silent `null`. `Int` is tried
    /// before `Double` so a whole number stays whole.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a JSON value."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {

    /// Parses one JSON document. Throws on anything that is not JSON, so a
    /// malformed line becomes a protocol error rather than a silent `null`.
    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// One line of JSON, which is the framing stdio MCP uses. Never pretty —
    /// an embedded newline would end the message early.
    public func lineEncoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Indented, key-sorted JSON, for a report a human or a model will read.
    /// Only ever goes inside a JSON string, so its newlines are escaped by the
    /// time they reach the wire.
    public func prettyEncoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Re-encodes this value so a `Codable` type can be decoded from it —
    /// how `write_plan` turns Claude's arguments into a `PlanDocument` without
    /// a second, hand-written parser that could disagree with the real one.
    public func decoded<T: Decodable>(as type: T.Type, using decoder: JSONDecoder) throws -> T {
        try decoder.decode(type, from: JSONEncoder().encode(self))
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .integer(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - The values this server reports

extension JSONValue {

    /// An instant, written the way both documents write instants, so a date in
    /// a report and the same date in `snapshot.json` are the same characters.
    public static func date(_ date: Date) -> JSONValue {
        .string(date.formatted(isoStyle))
    }

    /// A weight as the lifter entered it, never converted. `nil` stays `null`,
    /// which is how a bodyweight movement is told apart from an empty bar.
    public static func mass(_ mass: Mass?) -> JSONValue {
        guard let mass else { return .null }
        return ["value": .number(mass.value), "unit": .string(mass.unit.rawValue)]
    }

    /// A distance as it was carried, in the unit it was carried in, never
    /// converted. `nil` stays `null`, which is how a set that was counted or
    /// held is told apart from one carried no distance at all.
    public static func distance(_ distance: Distance?) -> JSONValue {
        guard let distance else { return .null }
        return ["value": .number(distance.value), "unit": .string(distance.unit.rawValue)]
    }

    /// An optional string, absent rather than empty when there is none.
    public static func string(_ value: String?) -> JSONValue {
        value.map { JSONValue.string($0) } ?? .null
    }

    /// An optional whole number.
    public static func integer(_ value: Int?) -> JSONValue {
        value.map { JSONValue.integer($0) } ?? .null
    }

    /// A list of taxonomy values as their raw strings.
    public static func taxonomy(_ values: [some ExtensibleTaxonomy]) -> JSONValue {
        .array(values.map { .string($0.rawValue) })
    }

    /// A prescribed effort as the scale and value it was written on, never
    /// converted into another scale and never bounded. `nil` stays `null`,
    /// which is how "no target was set" is told apart from an easy one.
    public static func intensity(_ target: IntensityTarget?) -> JSONValue {
        guard let target else { return .null }
        return ["scale": .string(target.scale.rawValue), "value": .string(target.value)]
    }
}

/// ISO 8601 in UTC without fractional seconds — the same shape
/// `JSONEncoder.DateEncodingStrategy.iso8601` writes, which is what both
/// documents use, so a date in a report and the same date in `snapshot.json`
/// are byte-identical. A format style rather than an `ISO8601DateFormatter`
/// because it is a `Sendable` value and needs no lock.
private let isoStyle = Date.ISO8601FormatStyle(timeZone: .gmt)
