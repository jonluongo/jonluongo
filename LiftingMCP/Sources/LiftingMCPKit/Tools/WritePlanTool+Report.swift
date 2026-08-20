import Foundation
import LiftingKit

// What `write_plan` says came back, and what it says when a plan could not be
// read at all.
//
// Split from the tool itself because it is a different job: writing a plan is
// one decision, and describing what landed is a rendering of the document that
// grows with the format. The caller reads this rather than what it sent, which
// is how it learns that a uniform prescription became the sets the lifter will
// actually see.

extension ToolRunner {

    /// Which facts about the lifter had no value on record at the moment this
    /// plan was written.
    ///
    /// Reported on success because this is where it is worth knowing: the plan
    /// has landed, and learning now that nobody ever stated his equipment is
    /// something that can still be acted on. It says what was empty and nothing
    /// else — it does not withhold the plan, warn, or suggest that a fact should
    /// have been gathered first. A plan written for a lifter nothing is known
    /// about is a plan this server writes without comment.
    ///
    /// **A snapshot that cannot be read answers `null`, never an empty list.**
    /// `write_plan` deliberately does not need a snapshot, so a first plan for a
    /// lifter whose phone has never backgrounded still writes; reporting `[]`
    /// there would say every fact was stated, which is the one wrong answer.
    /// `null` says the same thing the rest of this server's nulls say — nobody
    /// knows.
    func unstatedWhenWritten() -> JSONValue {
        do {
            guard let snapshot = try documents.readSnapshot() else {
                return Self.factsUnknown("the app has not written a snapshot yet")
            }
            let unstated = LifterFacts.unstated(in: snapshot).map(\.name)
            guard !unstated.isEmpty else {
                return [
                    "facts": .array([]),
                    "note": .string(
                        "Every fact this record can hold about the lifter was stated when this "
                            + "plan was written."),
                ]
            }
            return [
                "facts": .array(unstated.map { .string($0) }),
                "note": .string(
                    "This plan was written while those facts had no value on record — nobody has "
                        + "stated them, which is not an answer of 'none'. "
                        + "\(ToolCatalog.unstatedFacts) says what each of them holds and "
                        + "\(ToolCatalog.updateProfile) records one."),
            ]
        } catch {
            return Self.factsUnknown(error.localizedDescription)
        }
    }

    private static func factsUnknown(_ reason: String) -> JSONValue {
        [
            "facts": .null,
            "note": .string(
                "The plan was written, but the lifter's record could not be read (\(reason)), so "
                    + "this cannot say which facts about him were unstated at the time. That is "
                    + "unknown rather than none."),
        ]
    }

    /// The plan as it was written, so the caller sees what landed rather than
    /// what it sent — including the blocks, which is the whole point of writing
    /// a routine rather than a single session.
    static func reported(_ document: PlanDocument) -> JSONValue {
        [
            "id": .string(document.id.uuidString),
            "version": .integer(document.version),
            "catalogVersion": .integer(document.catalogVersion),
            "generatedAt": .date(document.generatedAt),
            "title": .string(document.title),
            "goal": .string(document.goal),
            "blockCount": .integer(document.blockCount),
            "durationMinutes": .integer(document.durationMinutes),
            "notes": .string(document.notes),
            "blocks": .array(
                document.blocks.enumerated().map { ordinal, block in
                    [
                        "ordinal": .integer(ordinal + 1),
                        "label": .text(block.label),
                        "isDeload": .bool(block.isDeload),
                        "days": .array(block.days.map(reported(day:))),
                    ]
                }),
        ]
    }

    private static func reported(day: PlanDocumentDay) -> JSONValue {
        [
            "weekday": .string(day.weekday.fullName),
            "focus": .text(day.focus),
            "durationMinutes": .integer(day.durationMinutes),
            "exercises": .array(day.entries.map(reported(entry:))),
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

    /// One prescription as it landed, including every set it prescribes.
    ///
    /// `prescribedSets` is always listed, even for a uniform prescription: the
    /// caller wrote `sets: 3` and gets back the three sets that produces, which
    /// is what the lifter will actually see. A set that was listed with nothing
    /// of its own comes back carrying the exercise's reps, load and intensity,
    /// so nothing has to be reconstructed to check that a ramp or a drop set
    /// landed the way it was written.
    private static func reported(exercise: PlanDocumentExercise) -> JSONValue {
        [
            "exerciseID": .string(exercise.exerciseID.rawValue),
            "displayName": .string(exercise.displayName),
            "sets": .integer(exercise.sets),
            "repRange": .string(exercise.repRange),
            "restSeconds": .integer(exercise.restSeconds),
            "suggestedLoad": .mass(exercise.suggestedLoad),
            "intensity": .intensity(exercise.intensity),
            "tempo": .string(exercise.tempo),
            "notes": .string(exercise.notes),
            "prescribedSets": .array(
                exercise.prescribedSets.map(ToolRunner.setPrescription)),
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
        return "That plan could not be read, so nothing was written: \(detail) Every exercise "
            + "needs 'exerciseID' and 'sets'; every day needs 'weekday'; every "
            + "week needs 'days'."
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
        return path.isEmpty ? "" : " at \(path.joined(separator: " → "))"
    }
}
