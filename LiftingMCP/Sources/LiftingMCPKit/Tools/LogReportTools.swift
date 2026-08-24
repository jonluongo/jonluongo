import Foundation
import LiftingKit

/// The two tools that report what happened.
///
/// **`exercise_history` reports per performance now.** It used to return a flat
/// array of sets with the plan, block, weekday, focus and prescription restated
/// on every row — because nothing in the record sat at the grain the question is
/// asked at. *How has bench gone* is a series of sessions, each holding its
/// sets, and that is what this hands back.
///
/// **Neither passes a verdict.** Whether a lift is progressing, stalling or
/// worth changing is the coach's to decide; these say what was asked for and
/// what was done, and stop.
///
/// **What it depends on.** `TrainingLog` for the join, the catalog for names,
/// and `TrainingSnapshot`. Nothing here writes.
extension ToolRunner {

    /// How many sessions `recent_sessions` returns when the coach does not say.
    static let defaultSessionLimit = 10

    /// How many performances of one movement `exercise_history` returns when he
    /// does not say. Larger than the session default because a performance is
    /// one movement rather than a whole workout, and progress on a single lift
    /// is read across many of them.
    static let defaultHistoryLimit = 20

    // MARK: - exercise_history

    func exerciseHistory(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        guard let raw = arguments["id"]?.stringValue else {
            return .failure(
                "exercise_history needs an 'id' argument — the exercise ID as "
                    + "\(ToolCatalog.listExercises) reported it, e.g. 'barbell-bench-press'.")
        }
        let id = ExerciseID(rawValue: raw)
        guard let exercise = catalog.exercise(id: id) else {
            return .failure(
                "'\(raw)' is not an exercise ID in the catalog (version \(catalog.version)). "
                    + "Use \(ToolCatalog.listExercises) to find the real ID; do not guess one, "
                    + "because history is keyed on exercise identity.")
        }

        let prescribed = Self.prescriptionsByCoordinates(in: snapshot, for: id)
        // **`.last`, and this is the one that would have been got wrong.**
        // `history(of:in:)` is oldest first, so keeping the head would hand back
        // the twenty sessions furthest from what he is doing now and hide the
        // ones he is planning against. This had no limit at all before, which a
        // lift trained weekly for two years turns into a flood.
        let bounded = BoundedList(
            TrainingLog.history(of: id, in: snapshot),
            limit: arguments["limit"]?.intValue ?? Self.defaultHistoryLimit,
            keeping: .last)

        var keys = bounded.report(
            total: "performanceCount", items: "performances",
            narrowing: "These are the most recent; raise 'limit' for earlier ones.",
            entry: { Self.performance($0, prescribed: prescribed) })
        keys["exerciseID"] = .string(id.rawValue)
        keys["displayName"] = .string(exercise.displayName)
        keys["exportedAt"] = .date(snapshot.exportedAt)
        return .report(.object(keys))
    }

    /// One session's worth of a movement: when, what was asked, what was done.
    private static func performance(
        _ performed: SnapshotPerformedExercise,
        prescribed: [SessionCoordinates: PlanDocumentExercise]
    ) -> JSONValue {
        let coordinates = SessionCoordinates(
            block: performed.blockOrdinal, ordinal: performed.sessionOrdinal)
        return .object([
            "occurredAt": .date(performed.occurredAt),
            "source": .string(performed.source.rawValue),
            "blockOrdinal": performed.blockOrdinal.map { .integer($0) } ?? .null,
            "sessionOrdinal": performed.sessionOrdinal.map { .integer($0) } ?? .null,
            "userNote": .text(performed.userNote),
            // Beside what he did rather than restated on every set: one
            // prescription, one performance, read together.
            "prescribed": prescribed[coordinates].map(prescription) ?? .null,
            "sets": .array(performed.sets.map(Self.performedSet)),
        ])
    }

    /// What was prescribed for a movement, wherever it was prescribed.
    ///
    /// A stated baseline has no session behind it and therefore no prescription,
    /// which is reported as `null` rather than as an empty one — nobody asked
    /// him for it.
    private static func prescriptionsByCoordinates(
        in snapshot: TrainingSnapshot, for id: ExerciseID
    ) -> [SessionCoordinates: PlanDocumentExercise] {
        var found: [SessionCoordinates: PlanDocumentExercise] = [:]
        for session in snapshot.sessions {
            guard let exercise = session.prescription.exercises.first(where: {
                $0.exerciseID == id
            }) else { continue }
            found[SessionCoordinates(
                block: session.blockOrdinal, ordinal: session.ordinal)] = exercise
        }
        return found
    }

    static func prescription(_ exercise: PlanDocumentExercise) -> JSONValue {
        .object([
            "restSeconds": .integer(exercise.restSeconds),
            "coachNote": .text(exercise.coachNote),
            "sets": .array(exercise.sets.map(setPrescription)),
        ])
    }

    static func setPrescription(_ set: PlanDocumentSet) -> JSONValue {
        .object([
            "target": set.target.map { .string($0.shorthand) } ?? .null,
            "load": .mass(set.load),
            "intensity": .intensity(set.intensity),
            "isWarmup": set.isWarmup ? .bool(true) : .null,
        ])
    }

    /// One set as it was performed. Each measure is reported only when it was
    /// stated: a hold has no reps and a set ticked without a count has none
    /// either, which is not the same as having done none.
    private static func performedSet(_ set: SnapshotPerformedSet) -> JSONValue {
        .object([
            "setIndex": .integer(set.setIndex),
            "isWarmup": set.isWarmup ? .bool(true) : .null,
            "load": .mass(set.load),
            // Read off the one measure, so the report cannot state two.
            "reps": set.work?.reps.map { .integer($0) } ?? .null,
            "durationSeconds": set.work?.durationSeconds.map { .integer($0) } ?? .null,
            "distance": .distance(set.work?.carried),
            "completedAt": .date(set.completedAt),
        ])
    }

    // MARK: - recent_sessions

    func recentSessions(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        // **`sessionCount` used to be the truncated count**, so ten-of-ten and
        // ten-of-two-hundred read the same and the coach could not tell he was
        // holding a slice. `.first` because `trained(in:)` is newest-first.
        let bounded = BoundedList(
            TrainingLog.trained(in: snapshot),
            limit: arguments["limit"]?.intValue ?? Self.defaultSessionLimit,
            keeping: .first)

        var keys = bounded.report(
            total: "sessionCount", items: "sessions",
            narrowing: "Raise 'limit' for more, or \(ToolCatalog.exerciseHistory) "
                + "for one movement across all of them.",
            entry: Self.session)
        keys["exportedAt"] = .date(snapshot.exportedAt)
        return .report(.object(keys))
    }

    private static func session(_ record: SessionRecord) -> JSONValue {
        .object([
            "blockOrdinal": .integer(record.blockOrdinal),
            "ordinal": .integer(record.ordinal),
            "focus": .string(record.focus),
            "occurredAt": record.occurredAt.map { .date($0) } ?? .null,
            "finishedAt": record.session.finishedAt.map { .date($0) } ?? .null,
            "performances": .array(record.performances.map { performed in
                .object([
                    "exerciseID": .string(performed.exerciseID.rawValue),
                    "userNote": .text(performed.userNote),
                    "sets": .array(performed.sets.map(Self.performedSet)),
                ])
            }),
        ])
    }
}

/// Where a session sits, for joining a performance to what was prescribed.
///
/// A stated baseline has neither, and `nil` joins to `nil` rather than to block
/// one — which would file a lift he mentioned in conversation under a session he
/// trained.
struct SessionCoordinates: Hashable, Sendable {
    let block: Int?
    let ordinal: Int?
}
