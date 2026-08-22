import Foundation
import LiftingKit

// What `write_plan` says came back, and what it says when a plan could not be
// read at all.
//
// Split from the tool itself because it is a different job: writing a plan is
// one decision, and describing what landed is a rendering of the document that
// grows with the format. The caller reads this rather than what it sent, which
// is how it learns that a uniform prescription became the sets the user will
// actually see.

extension ToolRunner {


    /// The plan as it was written, so the caller sees what landed rather than
    /// what it sent — including the blocks, which is the whole point of writing
    /// a routine rather than a single session.
    static func reported(_ document: PlanDocument) -> JSONValue {
        [
            "id": .string(document.id.uuidString),
            "version": .integer(document.version),
            "catalogVersion": .integer(document.catalogVersion),
            "generatedAt": .date(document.generatedAt),
            "blockOrdinals": .array(document.blockOrdinals.map { .integer($0) }),
            "sessionCount": .integer(document.sessions.count),
            "sessions": .array(document.sessions.map(reported(session:))),
        ]
    }

    /// One session as it landed. **No weekday**: when he trains is not
    /// something a plan states, and a session says where it sits instead.
    private static func reported(session: PlanDocumentSession) -> JSONValue {
        [
            "blockOrdinal": .integer(session.blockOrdinal),
            "ordinal": .integer(session.ordinal),
            "focus": .text(session.focus),
            "icon": session.icon.map { .string($0.rawValue) } ?? .null,
            "entries": .array(session.entries.map(reported(entry:))),
        ]
    }

    /// One entry as it landed: an exercise, or the group it was written in.
    ///
    /// A group comes back as a group rather than as the exercises inside it,
    /// because the grouping is the part of the prescription that a flat list
    /// cannot state — and the caller is reading this to see that what he wrote
    /// is what arrived.
    private static func reported(entry: PlanDocumentEntry) -> JSONValue {
        switch entry {
        case .exercise(let exercise):
            return reported(exercise: exercise)
        case .group(let group):
            return [
                "group": .array(group.exercises.map(reported(exercise:))),
                "restSeconds": .integer(group.restSeconds),
            ]
        }
    }

    /// One prescription as it landed, set by set.
    ///
    /// **Every set is listed because every set is a row.** This used to report
    /// the exercise's own reps, load and intensity beside a separate list of the
    /// sets that differed, so a reader had to reconcile the two to know what a
    /// ramp actually became. There is nothing to reconcile: what is here is what
    /// the user will see.
    private static func reported(exercise: PlanDocumentExercise) -> JSONValue {
        [
            "exerciseID": .string(exercise.exerciseID.rawValue),
            "displayName": .string(exercise.displayName),
            "setCount": .integer(exercise.sets.count),
            "restSeconds": .integer(exercise.restSeconds),
            "coachNote": .text(exercise.coachNote),
            "sets": .array(exercise.sets.map(ToolRunner.setPrescription)),
        ]
    }

    /// A decoding failure said in terms of the argument that caused it.
    ///
    /// `DecodingError`'s own description names coding paths and Swift types,
    /// which is not something a caller can act on. A `DocumentRefusal` never
    /// reaches here — it already says what to do about it.
    static func describe(decodingFailure error: any Error) -> String {
        let detail: String
        switch error as? DecodingError {
        case .keyNotFound(let key, let context):
            detail = "'\(key.stringValue)' is missing\(Self.location(context))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            detail = "a value has the wrong type\(Self.location(context))."
        case .dataCorrupted(let context):
            detail = "a value could not be read\(Self.location(context))."
        default:
            detail = "\(error)"
        }
        // **It names what happened and stops.** This used to append a list of
        // what the format requires — *every day needs 'weekday'; every week
        // needs 'days'* — keys that went when the format flattened into
        // sessions. It was advice that would itself have been refused as
        // unknown. The path above already names the field and where it sits,
        // and the schema is published with the tool; a blanket requirements
        // list restated on every failure earns nothing back.
        return "That plan could not be read, so nothing was written: \(detail)"
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
        return path.isEmpty ? "" : " at \(path.joined(separator: " → "))"
    }
}
