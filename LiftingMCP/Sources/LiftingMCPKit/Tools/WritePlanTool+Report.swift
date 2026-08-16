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

    /// The plan as it was written, so the caller sees what landed rather than
    /// what it sent — including the weeks, which is the whole point of writing
    /// a block rather than a week.
    static func reported(_ document: PlanDocument) -> JSONValue {
        [
            "id": .string(document.id.uuidString),
            "version": .integer(document.version),
            "catalogVersion": .integer(document.catalogVersion),
            "generatedAt": .date(document.generatedAt),
            "title": .string(document.title),
            "goal": .string(document.goal),
            "weekCount": .integer(document.weekCount),
            "durationMinutes": .integer(document.durationMinutes),
            "notes": .string(document.notes),
            "weeks": .array(
                document.weeks.enumerated().map { ordinal, week in
                    [
                        "ordinal": .integer(ordinal + 1),
                        "label": .string(week.label),
                        "isDeload": .bool(week.isDeload),
                        "days": .array(week.days.map(reported(day:))),
                    ]
                }),
        ]
    }

    private static func reported(day: PlanDocumentDay) -> JSONValue {
        [
            "weekday": .string(day.weekday.fullName),
            "focus": .string(day.focus),
            "durationMinutes": .integer(day.durationMinutes),
            "exercises": .array(day.exercises.map(reported(exercise:))),
        ]
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
            + "needs 'exerciseID', 'displayName' and 'sets'; every day needs 'weekday'; every "
            + "week needs 'days'."
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
        return path.isEmpty ? "" : " at \(path.joined(separator: " → "))"
    }
}
