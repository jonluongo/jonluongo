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

    /// A fractional number — a load of 2.5 kg is a number, not an integer.
    static func number(_ description: String) -> JSONValue {
        .object(["type": "number", "description": .string(description)])
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
    static func stringOrList(_ description: String, oneOf values: [String] = []) -> JSONValue {
        // **The vocabulary is published, not described.** Left to prose, the
        // coach filtered by `"quads"` and got `count: 0` — which reads as *no
        // exercise trains quadriceps* rather than *that is not a word here*.
        // The values come from the loaded catalog, so a catalog that grows one
        // publishes it the same day.
        let leaf: JSONValue = values.isEmpty
            ? ["type": "string"]
            : ["type": "string", "enum": .array(values.map { .string($0) })]
        return [
            "description": .string(description),
            "anyOf": [leaf, ["type": "array", "items": leaf]],
        ]
    }

    /// A weight, which always carries the unit it was entered in — nothing here
    /// converts one, and a bare number could only be read by guessing.
    static var massSchema: JSONValue {
        [
            "type": "object",
            "properties": [
                "value": ["type": "number"],
                "unit": ["type": "string", "enum": .array(
                    MassUnit.allCases.map { .string($0.rawValue) })],
                "date": ["type": "string", "description": "ISO 8601, UTC. Optional."],
            ],
            "required": ["value", "unit"],
        ]
    }

    /// One stated starting point on one lift.
    static var baselineSchema: JSONValue {
        [
            "type": "object",
            "properties": [
                "exerciseID": ["type": "string"],
                "load": massSchema,
                "reps": ["type": "integer"],
                "recordedAt": ["type": "string", "description": "ISO 8601, UTC. Optional."],
            ],
            "required": ["exerciseID", "reps"],
        ]
    }

}
