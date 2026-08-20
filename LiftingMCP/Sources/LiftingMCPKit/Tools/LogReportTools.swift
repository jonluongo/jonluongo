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

        let prescriptions = Prescriptions(snapshot)
        let sets = TrainingLog.records(in: snapshot).filter { $0.exerciseID == id }
        return .report([
            "exerciseID": .string(id.rawValue),
            "displayName": .string(exercise.displayName),
            "setCount": .integer(sets.count),
            "baselines": .array(
                snapshot.baselines.filter { $0.exerciseID == id }.map {
                    ["recordedAt": .date($0.recordedAt), "load": .mass($0.load),
                     "reps": .integer($0.reps)]
                }),
            "sets": .array(sets.map { Self.historyEntry($0, in: snapshot, prescriptions) }),
        ])
    }

    /// One logged set beside what was prescribed for it.
    ///
    /// `reps`, `durationSeconds` and `distance` answer different questions and
    /// are never the same number: a set counted in repetitions reports `reps`
    /// and nulls for the other two, a hold reports the seconds it was held, and
    /// a carry reports how far it went and in what unit. Adding any of them into
    /// another is the mistake this trio exists to make impossible.
    private static func historyEntry(
        _ record: LoggedSetRecord, in snapshot: TrainingSnapshot, _ prescriptions: Prescriptions
    ) -> JSONValue {
        let routine = snapshot.routines.first { $0.document.id == record.routineID }
        let block = routine?.document.blocks.indices.contains(record.blockOrdinal - 1) == true
            ? routine?.document.blocks[record.blockOrdinal - 1] : nil
        let day = block?.days.first { $0.weekday == record.weekday }
        return [
            "date": .date(record.completedAt),
            "load": .mass(record.load),
            "reps": .integer(record.reps),
            "durationSeconds": .integer(record.durationSeconds),
            "distance": .distance(record.distance),
            "isCompleted": .bool(record.isCompleted),
            "isWarmup": .bool(record.isWarmup),
            "plan": .string(routine?.document.title ?? ""),
            "block": .integer(record.blockOrdinal),
            "blockLabel": .text(block?.label),
            "isDeload": .bool(block?.isDeload ?? false),
            "weekday": .string(record.weekday.fullName),
            "focus": .text(day?.focus),
            // The prescription is looked up in the document the coach wrote
            // rather than carried beside the set. `null` when the block it names
            // no longer holds that position — reported as unknown rather than
            // guessed at.
            "prescribed": prescriptions.exercise(for: record).map(prescription) ?? .null,
        ]
    }

    /// What the plan asked for, carried beside what happened. Absences stay
    /// absent: no rest prescribed is `null`, not zero, and no effort target is
    /// `null` rather than a target nobody wrote.
    ///
    /// `prescribedSets` lists every set in order and in full, so a ramp or a
    /// drop set reads as the sets it actually is — compare it index for index
    /// with the logged sets beside it. `intensity` is the effort that was asked
    /// for; the reps and load logged against it are what was given, and the
    /// lifter is asked for no rating on top. Nothing here draws the comparison
    /// or converts one scale into another.
    static func prescription(_ exercise: PlanDocumentExercise) -> JSONValue {
        [
            "sets": .integer(exercise.sets),
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
            "plan": .text(session.planTitle),
            "block": .integer(session.blockOrdinal),
            "blockLabel": .text(session.blockLabel),
            "isDeload": .bool(session.isDeload),
            "weekday": .string(session.weekday.fullName),
            "focus": .text(session.focus),
            "durationMinutes": .integer(session.durationMinutes),
            "exercises": .array(exercises(of: session)),
        ]
    }

    /// The day's movements in prescribed order, each with the sets logged
    /// against it.
    ///
    /// The prescription and the log come from two places now — the document the
    /// coach wrote and the flat series — and this is where they are put back
    /// together, by the movement's position in the day. A set logged against a
    /// position the document no longer holds keeps its own entry rather than
    /// being dropped: the work happened.
    private static func exercises(of session: SessionRecord) -> [JSONValue] {
        let byOrder = Dictionary(grouping: session.sets, by: \.exerciseOrder)
        let day = session.day
        var letters: [Int: String] = [:]
        var position = 0
        var groupOrdinal = 0
        for entry in day?.entries ?? [] {
            if entry.group != nil {
                for member in 0..<entry.exercises.count {
                    letters[position + member] = "\(letter(at: groupOrdinal))\(member + 1)"
                }
                groupOrdinal += 1
            }
            position += entry.exercises.count
        }

        return session.exercises.enumerated().map { order, exercise in
            let sets = (byOrder[order] ?? []).sorted { $0.setIndex < $1.setIndex }
            return [
                "exerciseID": .string(exercise.exerciseID.rawValue),
                "displayName": .string(exercise.displayName),
                "order": .integer(order),
                // `null` for the ordinary exercise performed on its own. Where
                // it is present, these sets were performed in rounds with the
                // others of the same group — which a flat list of sets cannot
                // say, and which is the whole of what makes them a superset.
                "group": group(at: order, in: day, notation: letters[order]),
                "prescribed": prescription(exercise),
                // What the lifter wrote about doing it, in his own words. Not
                // the coach's note — that is inside `prescribed`, and it is
                // detail about the work rather than a report of it. `null` when
                // he wrote nothing, which is nearly always.
                "lifterNote": .string(session.lifterNote(atOrder: order)),
                "completedWorkingSets": .integer(sets.count { $0.isCompletedWorkingSet }),
                "sets": .array(sets.map(loggedSet)),
            ]
        }
    }

    private static func loggedSet(_ record: LoggedSetRecord) -> JSONValue {
        [
            "setIndex": .integer(record.setIndex),
            "load": .mass(record.load),
            "reps": .integer(record.reps),
            "durationSeconds": .integer(record.durationSeconds),
            "distance": .distance(record.distance),
            "isCompleted": .bool(record.isCompleted),
            "isWarmup": .bool(record.isWarmup),
        ]
    }

    /// The letter for the group at `index`: A, B, … Z, then AA. Spreadsheet
    /// order, which is the one everybody already reads and never runs out.
    private static func letter(at index: Int) -> String {
        var remaining = index
        var letters = ""
        repeat {
            // swiftlint:disable:next force_unwrapping
            let scalar = UnicodeScalar(UInt8(65 + remaining % 26))
            letters = String(Character(scalar)) + letters
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return letters
    }

    /// The group an exercise was performed in, as the plan wrote it.
    ///
    /// `notation` is the A1 / A2 a lifter reads — derived from the day's own
    /// order rather than stored, since the document states which movements are a
    /// group and the letters are only a way of saying it aloud. `restSeconds` is
    /// the rest after each round, which is the only rest a group has.
    private static func group(
        at order: Int, in day: PlanDocumentDay?, notation: String?
    ) -> JSONValue {
        guard let day, let notation else { return .null }
        var position = 0
        for entry in day.entries {
            let count = entry.exercises.count
            if (position..<(position + count)).contains(order), let group = entry.group {
                return [
                    "notation": .string(notation),
                    "position": .integer(order - position + 1),
                    "of": .integer(count),
                    "restSeconds": .integer(group.restSeconds),
                ]
            }
            position += count
        }
        return .null
    }
}
