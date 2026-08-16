import Foundation
import LiftingKit

// The shorthand every tool's `inputSchema` is written in.
//
// Kept apart from the definitions themselves so that a schema reads as the
// shape it describes rather than as JSON Schema boilerplate. Nothing here
// decides anything — it only spells `{"type": "string", "description": …}`
// once.

extension ToolCatalog {

    static func object(
        _ properties: [String: JSONValue], required: [JSONValue] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required) }
        return .object(schema)
    }

    /// An array of `items`, described.
    static func array(of items: JSONValue, _ description: String) -> JSONValue {
        ["type": "array", "description": .string(description), "items": items]
    }

    static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    static func boolean(_ description: String) -> JSONValue {
        ["type": "boolean", "description": .string(description)]
    }

    /// A closed set of exact strings, or `null` to take the fact back. The
    /// values come from the taxonomy itself rather than being retyped, so a
    /// tier added later cannot be advertised wrongly.
    static func enumerated(_ values: [String], _ description: String) -> JSONValue {
        [
            "type": ["string", "null"],
            "description": .string(description),
            "enum": .array(values.map { .string($0) } + [.null]),
        ]
    }

    /// One value or several — Claude writes `"muscle": "chest"` as readily as
    /// `"muscle": ["chest"]`, and both plainly mean the same thing.
    static func stringOrList(_ description: String) -> JSONValue {
        [
            "description": .string(description),
            "anyOf": [["type": "string"], ["type": "array", "items": ["type": "string"]]],
        ]
    }

    /// A day, as either of the two ways a weekday is legibly written.
    static func weekday(_ description: String) -> JSONValue {
        [
            "description": .string(description),
            "anyOf": [["type": "string"], ["type": "integer"]],
        ]
    }
}
