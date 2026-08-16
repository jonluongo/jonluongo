import Foundation
import LiftingKit

extension ToolRunner {

    /// Every set ever logged for one movement, oldest first.
    ///
    /// Warmups and rows that were never finished come back flagged rather than
    /// filtered out — a caller deciding what counts as work needs to see what
    /// was there. Each set carries what was prescribed alongside it, so "he was
    /// told 5 and got 4" is answerable without a second call.
    ///
    /// An ID the catalog does not have is reported as a failure naming it,
    /// because that is almost always a typo and an empty history would read as
    /// a movement he has never trained.
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

        let sets = TrainingLog.records(in: snapshot)
            .filter { $0.exercise.exerciseID == id }
        return .report([
            "exerciseID": .string(id.rawValue),
            "displayName": .string(exercise.displayName),
            "inCatalog": true,
            "setCount": .integer(sets.count),
            "baselines": .array(
                snapshot.baselines.filter { $0.exerciseID == id }.map {
                    ["recordedAt": .date($0.recordedAt), "load": .mass($0.load),
                     "reps": .integer($0.reps)]
                }),
            "sets": .array(sets.map(Self.historyEntry)),
        ])
    }

    /// One logged set beside what was prescribed for it.
    ///
    /// `reps` and `durationSeconds` answer different questions and are never
    /// the same number: a set counted in repetitions reports `reps` and a null
    /// duration, and a hold reports the seconds it was held and no reps. Adding
    /// one into the other is the mistake this pair exists to make impossible.
    private static func historyEntry(_ record: LoggedSetRecord) -> JSONValue {
        [
            "date": .date(record.loggedSet.completedAt),
            "load": .mass(record.loggedSet.load),
            "reps": .integer(record.loggedSet.reps),
            "durationSeconds": .integer(record.loggedSet.durationSeconds),
            "rpe": record.loggedSet.rpe.map { .number($0) } ?? .null,
            "isCompleted": .bool(record.loggedSet.isCompleted),
            "isWarmup": .bool(record.loggedSet.isWarmup),
            "plan": .string(record.planTitle),
            "week": .integer(record.weekOrdinal),
            "weekLabel": .string(record.weekLabel),
            "isDeload": .bool(record.isDeload),
            "weekday": .string(record.weekday.fullName),
            "focus": .string(record.focus),
            "prescribed": prescription(record.exercise),
        ]
    }

    /// What the plan asked for, carried beside what happened. Absences stay
    /// absent: no rest prescribed is `null`, not zero, and no effort target is
    /// `null` rather than an RPE nobody wrote.
    ///
    /// `prescribedSets` lists every set in order and in full, so a ramp or a
    /// drop set reads as the sets it actually is — compare it index for index
    /// with the logged sets beside it. `intensity` is the effort that was asked
    /// for; the logged `rpe` is the effort that was given. Nothing here draws
    /// the comparison or converts one scale into another.
    static func prescription(_ exercise: SnapshotPlannedExercise) -> JSONValue {
        [
            "sets": .integer(exercise.targetSets),
            "repRange": .string(exercise.repRange),
            "suggestedLoad": .mass(exercise.suggestedLoad),
            "restSeconds": .integer(exercise.restSeconds),
            "intensity": .intensity(exercise.intensity),
            "tempo": .string(exercise.tempo),
            "notes": .string(exercise.notes),
            "prescribedSets": .array(exercise.prescribedSets.map(setPrescription)),
        ]
    }

    /// One prescribed set, exactly as it was prescribed.
    static func setPrescription(_ set: SetPrescription) -> JSONValue {
        [
            "repRange": .string(set.repRange),
            "suggestedLoad": .mass(set.suggestedLoad),
            "intensity": .intensity(set.intensity),
            "notes": .string(set.notes),
        ]
    }

    // MARK: - Recent sessions

    /// The most recently trained days, newest first.
    ///
    /// A day that was prescribed and never trained is not a session — reporting
    /// it as one would read as a workout of zero sets rather than as a workout
    /// that has not happened yet.
    func recentSessions(_ arguments: JSONValue, in snapshot: TrainingSnapshot) -> ToolOutcome {
        let limit = arguments["limit"]?.intValue ?? Self.defaultSessionLimit
        let sessions = TrainingLog.sessions(in: snapshot)
        return .report([
            "count": .integer(min(limit, sessions.count)),
            "totalSessions": .integer(sessions.count),
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "snapshotAgeDays": .integer(TrainingLog.ageInDays(of: snapshot, at: now())),
            "sessions": .array(sessions.prefix(limit).map(Self.sessionEntry)),
        ])
    }

    /// How many sessions come back when the call does not say.
    static let defaultSessionLimit = 10

    private static func sessionEntry(_ session: SessionRecord) -> JSONValue {
        [
            "date": session.date.map { .date($0) } ?? .null,
            "completedAt": session.completedAt.map { .date($0) } ?? .null,
            "plan": .string(session.planTitle),
            "week": .integer(session.weekOrdinal),
            "weekLabel": .string(session.weekLabel),
            "isDeload": .bool(session.isDeload),
            "weekday": .string(session.weekday.fullName),
            "focus": .string(session.focus),
            "durationMinutes": .integer(session.durationMinutes),
            "exercises": .array(session.exercises.map(sessionExercise)),
        ]
    }

    private static func sessionExercise(_ exercise: SnapshotPlannedExercise) -> JSONValue {
        [
            "exerciseID": .string(exercise.exerciseID.rawValue),
            "displayName": .string(exercise.displayName),
            "order": .integer(exercise.order),
            "prescribed": prescription(exercise),
            "completedWorkingSets": .integer(
                exercise.loggedSets.count { $0.isCompleted && !$0.isWarmup }),
            "sets": .array(
                exercise.loggedSets.map {
                    [
                        "setIndex": .integer($0.setIndex),
                        "load": .mass($0.load),
                        "reps": .integer($0.reps),
                        "durationSeconds": .integer($0.durationSeconds),
                        "rpe": $0.rpe.map { .number($0) } ?? .null,
                        "isCompleted": .bool($0.isCompleted),
                        "isWarmup": .bool($0.isWarmup),
                    ]
                }),
        ]
    }
}
