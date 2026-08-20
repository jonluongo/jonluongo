import Foundation
import LiftingKit

/// The compact context that rides along on every turn: who the lifter is, what
/// he has to train with, what block he is on, what he did lately, and what he
/// is currently working with on each lift.
///
/// Built by `ToolRunner.contextResource()` and served as the one MCP resource.
/// It is deliberately small — small enough to carry constantly — which is what
/// makes the drill-down tools worth having: depth is paid for only when it is
/// wanted, and `note` says where to go for it.
///
/// Everything here is a restatement of the snapshot. It concludes nothing: no
/// readiness score, no assessment of whether a lift is stalling, no verdict on
/// balance. Those are Claude's to draw from the data.
///
/// Depends on: `ToolRunner`, `TrainingLog`, and the snapshot value types.
struct ContextReport {
    let runner: ToolRunner
    let snapshot: TrainingSnapshot
    /// What a logged set was asked to be, looked up in the document that asked.
    private let prescriptions: Prescriptions

    init(runner: ToolRunner, snapshot: TrainingSnapshot) {
        self.runner = runner
        self.snapshot = snapshot
        prescriptions = Prescriptions(snapshot)
    }

    /// How many recent sessions ride along before the tools take over.
    static let carriedSessions = 5

    func build() -> JSONValue {
        [
            "snapshotGeneratedAt": .date(snapshot.generatedAt),
            "snapshotAgeDays": .integer(TrainingLog.ageInDays(of: snapshot, at: runner.now())),
            "catalogVersion": .integer(snapshot.catalogVersion),
            "lifter": lifter,
            "currentBlock": currentBlock,
            "recentSessions": recentSessions,
            "workingWeights": workingWeights,
            "note": .string(note),
        ]
    }

    // MARK: - Who he is

    /// Who he is, with the facts nobody has stated left as `null`.
    ///
    /// A `null` here means he has not said, not that the answer is nothing.
    /// The app asks him nothing, so an unfilled field is the ordinary state of
    /// a lifter early in a conversation — and reporting a plausible default
    /// instead would be this server asserting something about him that nobody
    /// ever said.
    private var lifter: JSONValue {
        guard let profile = snapshot.profile else { return .null }
        return [
            "experience": .string(profile.experience?.rawValue),
            "goal": .string(profile.goal),
            "constraints": .string(profile.constraints),
            "availableEquipment": profile.availableEquipment.map { .taxonomy($0) } ?? .null,
            "avoidedPatterns": .taxonomy(profile.avoidedPatterns),
            "avoidedExercises": .array(profile.avoidedExercises.map { .string($0.rawValue) }),
            "preferredWeekdays": .array(profile.preferredWeekdays.map { .string($0.fullName) }),
            "preferredDurationMinutes": .integer(profile.preferredDurationMinutes),
            "displayUnit": .string(profile.displayUnit.rawValue),
            "bodyweight": .mass(LifterFacts.latestBodyweight(in: snapshot)),
            "unstated": .array(unstatedFacts.map { .string($0) }),
        ]
    }

    /// The facts nobody has stated yet, named rather than left for a reader to
    /// notice one `null` at a time.
    ///
    /// Read from `LifterFacts` rather than worked out here, so this list and the
    /// one `unstated_facts` reports are the same list. Two places
    /// counting the record's empty fields separately would eventually disagree,
    /// and a reader told one thing by the resource and another by the tool has
    /// no way to tell which is right.
    private var unstatedFacts: [String] {
        LifterFacts.unstated(in: snapshot).map(\.name)
    }

    // MARK: - What he is on

    /// The block he is on, and only that block.
    ///
    /// **`days` used to be every day of every block, flattened.** A routine of
    /// three blocks of Monday, Wednesday and Friday reported nine days named
    /// Monday, Wednesday, Friday, Monday, … under a key called *currentBlock*,
    /// with nothing saying where one block ended and the next began. A coach
    /// reading it could not tell which block was current, which is the first
    /// thing he needs in order to write the next one.
    ///
    /// **Which block is current is read the way the app reads it**: the earliest
    /// one still holding a session nobody has finished, and the last block when
    /// every session is finished. The record decides it, never the calendar — a
    /// fortnight away does not move him on.
    private var currentBlock: JSONValue {
        guard let routine = TrainingLog.currentRoutine(in: snapshot) else { return .null }
        let plan = routine.document
        // Which weeks hold logged work, read off the flat log rather than by
        // walking the plan: the plan says what was asked for and the log says
        // what happened, and they are two different documents now.
        let loggedWeeks = Set(
            snapshot.log.filter { $0.routineID == plan.id }.map(\.weekOrdinal))
        let ordinal = Self.currentOrdinal(of: routine)
        let week = plan.weeks.indices.contains(ordinal - 1) ? plan.weeks[ordinal - 1] : nil
        return [
            "title": .string(plan.title),
            "goal": .string(plan.goal),
            "startDate": .date(routine.startDate),
            "weekdays": .array(
                Set(plan.weeks.flatMap(\.days).map(\.weekday))
                    .sorted { Weekday.displayOrder.firstIndex(of: $0) ?? 0
                        < Weekday.displayOrder.firstIndex(of: $1) ?? 0 }
                    .map { .string($0.fullName) }),
            "durationMinutes": .integer(plan.durationMinutes),
            "weeksPrescribed": .integer(plan.weeks.count),
            "weeksLogged": .integer(loggedWeeks.count),
            "currentWeekOrdinal": .integer(ordinal),
            "currentWeekLabel": .string(week?.label ?? ""),
            "currentWeekIsDeload": .bool(week?.isDeload ?? false),
            // The fact a weekly loop turns on: he is on the last block that was
            // written and every session in it is finished, so there is nothing
            // prescribed for him to train next. It states the position and
            // nothing about what should follow.
            "nothingPrescribedBeyond": .bool(Self.isSpent(routine, at: ordinal)),
            "days": .array(
                (week?.days ?? []).map {
                    [
                        "weekday": .string($0.weekday.fullName),
                        "focus": .string($0.focus),
                        "exercises": .array(
                            $0.entries.flatMap(\.exercises).map { .string($0.displayName) }),
                    ]
                }),
        ]
    }

    /// The earliest block still holding an unfinished session, or the last block
    /// when every one of them is finished.
    static func currentOrdinal(of routine: SnapshotRoutine) -> Int {
        let unfinished = routine.sessions.filter { $0.completedAt == nil }.map(\.weekOrdinal)
        return unfinished.min() ?? max(1, routine.document.weeks.count)
    }

    /// Whether the routine has nothing left to train: the block he is on is the
    /// last one written, and every session in it is finished.
    static func isSpent(_ routine: SnapshotRoutine, at ordinal: Int) -> Bool {
        guard ordinal == routine.document.weeks.count else { return false }
        return routine.sessions
            .filter { $0.weekOrdinal == ordinal }
            .allSatisfy { $0.completedAt != nil }
    }

    // MARK: - What he did lately

    private var recentSessions: JSONValue {
        .array(
            TrainingLog.sessions(in: snapshot).prefix(Self.carriedSessions).map { session in
                [
                    "date": session.date.map { .date($0) } ?? .null,
                    "plan": .string(session.planTitle),
                    "week": .integer(session.weekOrdinal),
                    "weekday": .string(session.weekday.fullName),
                    "focus": .string(session.focus),
                    "exercises": .array(
                        session.exercises.enumerated().map { order, exercise in
                            let done = session.sets.count {
                                $0.exerciseOrder == order && $0.isCompletedWorkingSet
                            }
                            return .string(
                                "\(exercise.displayName): \(done) of \(exercise.sets)"
                                    + " working sets")
                        }),
                ]
            })
    }

    // MARK: - What he is working with

    /// What he last worked with on each lift, and — beside it — the effort the
    /// plan had asked for on that lift.
    ///
    /// `load` and `reps` are what he actually put up; `prescribedIntensity` is
    /// what was asked of him, on whatever scale it was prescribed on. Both are
    /// here so the comparison can be drawn; nothing here draws it, converts an
    /// RIR into an RPE, or concludes that a target was met. A lift with no
    /// stated target reports `null`, which means nobody stated one — not that it
    /// was easy. He is asked for no rating of his own, so none is reported: a
    /// number he could not supply accurately would be worse than the reps and
    /// the load, which he can.
    private var workingWeights: JSONValue {
        .array(
            TrainingLog.lastWorkingSets(in: snapshot).map { record in
                let prescribed = prescriptions.exercise(for: record)
                return [
                    "exerciseID": .string(record.exerciseID.rawValue),
                    "displayName": .string(
                        prescribed?.displayName ?? record.exerciseID.rawValue),
                    "load": .mass(record.load),
                    "reps": .integer(record.reps),
                    "prescribedIntensity": .intensity(prescribed?.intensity),
                    "lastTrained": .date(record.completedAt),
                ]
            })
    }

    // MARK: - Where to go for more

    private var note: String {
        opening
            + "This is a summary. For depth: \(ToolCatalog.listExercises) for real exercise "
            + "IDs he can perform, \(ToolCatalog.exerciseHistory) for every set on one "
            + "movement, \(ToolCatalog.recentSessions) for full session detail, and "
            + "\(ToolCatalog.volumeByMuscle) for set and rep totals. Write a plan with "
            + "\(ToolCatalog.writePlan), using IDs from \(ToolCatalog.listExercises) verbatim."
    }

    /// What to say before the summary when there is nothing, or not enough, to
    /// summarize. The app has no setup screen, so an empty profile is a
    /// conversation that has not happened rather than a step he skipped.
    private var opening: String {
        guard snapshot.profile != nil else {
            return "Nothing has been recorded about this lifter — the app asks him nothing, so "
                + "everything known about him comes from what he tells you. Not one fact this "
                + "record can hold is stated; \(ToolCatalog.unstatedFacts) names them and says "
                + "what each holds. Assume nothing; ask, then write it down with "
                + "\(ToolCatalog.updateProfile). "
        }
        let unstated = unstatedFacts
        guard !unstated.isEmpty else { return "" }
        return "He has not stated: \(unstated.joined(separator: ", ")). Those read as null "
            + "above and are genuinely unknown, not defaults — do not assume a value for one. "
            + "\(ToolCatalog.unstatedFacts) says what each of them holds. Record what he tells "
            + "you with \(ToolCatalog.updateProfile). "
    }
}
