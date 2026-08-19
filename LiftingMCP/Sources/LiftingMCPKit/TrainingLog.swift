import Foundation
import LiftingKit

/// One training day that actually happened, with the plan that prescribed it.
///
/// Produced by `TrainingLog.sessions(in:)`, newest first. A day counts as a
/// session when something was logged on it or the lifter marked it finished; a
/// day that was prescribed and never trained is not a session, because reporting
/// it as one would read as a workout of zero sets.
///
/// Depends on: the snapshot value types in `LiftingKit`.
struct SessionRecord: Sendable {
    let routine: SnapshotRoutine
    let weekOrdinal: Int
    let weekday: Weekday
    let completedAt: Date?
    let lastLoggedAt: Date?
    /// The sets logged on this day, in the order they were logged.
    let sets: [LoggedSetRecord]
    /// What the lifter wrote about performing the movements of this day.
    let notes: [LifterNote]

    var planTitle: String { routine.document.title }
    /// What the plan calls this week, or empty when it named it nothing.
    var weekLabel: String { week?.label ?? "" }
    var isDeload: Bool { week?.isDeload ?? false }
    var focus: String { day?.focus ?? "" }
    var durationMinutes: Int? { day?.durationMinutes }

    /// The week this session sits in, as the document states it.
    var week: PlanDocumentWeek? {
        routine.document.weeks.indices.contains(weekOrdinal - 1)
            ? routine.document.weeks[weekOrdinal - 1] : nil
    }

    /// The day as it was prescribed. `nil` when the record holds a day the
    /// document does not — a plan reimported over a logged block, say — which is
    /// reported as an absence rather than papered over.
    var day: PlanDocumentDay? { week?.days.first { $0.weekday == weekday } }

    /// The movements prescribed for this day, in order, groups flattened into
    /// the sequence they are performed in.
    var exercises: [PlanDocumentExercise] { day?.entries.flatMap(\.exercises) ?? [] }

    /// What he wrote about the movement at `order`, or `nil` when he wrote
    /// nothing about it.
    func lifterNote(atOrder order: Int) -> String? {
        notes.first { $0.exerciseOrder == order }?.text
    }

    /// When the session happened. The last set logged is the truer answer than
    /// the day's own completion mark, which a lifter may never tap; the mark is
    /// the fallback for a day finished with nothing logged.
    var date: Date? { lastLoggedAt ?? completedAt }
}

/// Reads a `TrainingSnapshot` the way a question wants it.
///
/// **The flattening is gone.** The snapshot used to nest logged sets five deep —
/// plan, week, day, exercise, set — so every tool began by walking the tree into
/// a flat list. The wire carries the flat list now and the plans travel as the
/// documents the coach wrote, so what is left here is grouping, sorting and the
/// one lookup that joins a logged set back to its prescription.
///
/// Everything here *reports*: it re-shapes what the snapshot says and adds
/// nothing. Nothing in this file decides anything about training.
///
/// Depends on: `TrainingSnapshot` from `LiftingKit`.
enum TrainingLog {

    /// Every logged set in the snapshot, oldest first.
    ///
    /// Includes warm-ups and unfinished rows; each record says which it is, so a
    /// caller chooses what counts rather than being handed a filtered truth.
    static func records(in snapshot: TrainingSnapshot) -> [LoggedSetRecord] {
        snapshot.log.sorted { $0.completedAt < $1.completedAt }
    }

    /// The days that were trained, newest first.
    ///
    /// A day appears when it holds logged sets or when the lifter marked it
    /// finished. Both come from different places — the log and the routine's
    /// sessions — so they are merged here rather than either being taken as the
    /// whole answer.
    static func sessions(in snapshot: TrainingSnapshot) -> [SessionRecord] {
        let routines = Dictionary(
            snapshot.routines.map { ($0.document.id, $0) }, uniquingKeysWith: { first, _ in first })
        var setsByDay: [DayKey: [LoggedSetRecord]] = [:]
        for record in records(in: snapshot) {
            setsByDay[DayKey(record), default: []].append(record)
        }
        var notesByDay: [DayKey: [LifterNote]] = [:]
        for note in snapshot.lifterNotes {
            let key = DayKey(
                routineID: note.routineID, weekOrdinal: note.weekOrdinal,
                weekday: note.weekday)
            notesByDay[key, default: []].append(note)
        }

        var sessions: [SessionRecord] = []
        for routine in snapshot.routines {
            for session in routine.sessions {
                let key = DayKey(
                    routineID: routine.document.id,
                    weekOrdinal: session.weekOrdinal, weekday: session.weekday)
                let sets = setsByDay.removeValue(forKey: key) ?? []
                guard !sets.isEmpty || session.completedAt != nil else { continue }
                sessions.append(SessionRecord(
                    routine: routine, weekOrdinal: session.weekOrdinal,
                    weekday: session.weekday, completedAt: session.completedAt,
                    lastLoggedAt: sets.map(\.completedAt).max(), sets: sets,
                    notes: notesByDay[key] ?? []))
            }
        }
        // A day with sets logged against it that no routine claims. It cannot be
        // dropped — the work happened — so it is reported under whatever routine
        // its rows name, with nothing prescribed beside it.
        for (key, sets) in setsByDay {
            guard let routine = routines[key.routineID] else { continue }
            sessions.append(SessionRecord(
                routine: routine, weekOrdinal: key.weekOrdinal, weekday: key.weekday,
                completedAt: nil, lastLoggedAt: sets.map(\.completedAt).max(), sets: sets,
                notes: notesByDay[key] ?? []))
        }
        return sessions.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The block the lifter is on: the last one that has not been superseded.
    ///
    /// `nil` when every block is finished or there are none, which is a real
    /// state — a lifter between blocks is waiting for a plan.
    static func currentRoutine(in snapshot: TrainingSnapshot) -> SnapshotRoutine? {
        snapshot.routines.last { $0.completedAt == nil }
    }

    /// The last completed working set on each movement the lifter has trained,
    /// newest first.
    ///
    /// This is what "current working weight" means here: the last thing he
    /// actually did, not an average, an estimate, or a projection. Warm-ups and
    /// unfinished rows are excluded because neither is a weight he worked with.
    static func lastWorkingSets(in snapshot: TrainingSnapshot) -> [LoggedSetRecord] {
        var latest: [ExerciseID: LoggedSetRecord] = [:]
        for record in records(in: snapshot) where record.isCompletedWorkingSet {
            // Ascending, so the last one written wins.
            latest[record.exerciseID] = record
        }
        return latest.values.sorted { $0.completedAt > $1.completedAt }
    }

    /// How many whole days old the snapshot is at `now`, never negative.
    ///
    /// Reported everywhere a window is, so a reader can tell a quiet month apart
    /// from an app that has not written a snapshot in a month.
    static func ageInDays(of snapshot: TrainingSnapshot, at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(snapshot.generatedAt) / (24 * 60 * 60)))
    }

    /// Which day a logged set belongs to.
    private struct DayKey: Hashable {
        let routineID: UUID
        let weekOrdinal: Int
        let weekday: Weekday

        init(routineID: UUID, weekOrdinal: Int, weekday: Weekday) {
            self.routineID = routineID
            self.weekOrdinal = weekOrdinal
            self.weekday = weekday
        }

        init(_ record: LoggedSetRecord) {
            self.init(
                routineID: record.routineID, weekOrdinal: record.weekOrdinal,
                weekday: record.weekday)
        }
    }
}

/// What a logged set was prescribed, found by where the set says it sits.
///
/// **Why this exists.** A logged set used to carry a copy of its exercise's
/// prescription beside it, which is how the same prescription came to be written
/// in two shapes. The log names its position instead — block, week, day, the
/// movement's place in that day — and this walks that position into the document
/// the coach wrote. One description of a prescription, looked up rather than
/// duplicated.
///
/// Build one per snapshot and ask it per set; it indexes the routines once so a
/// report over hundreds of sets does not search a list per row.
///
/// Depends on: `TrainingSnapshot` and the plan document types.
struct Prescriptions {

    private let routines: [UUID: SnapshotRoutine]

    init(_ snapshot: TrainingSnapshot) {
        routines = Dictionary(
            snapshot.routines.map { ($0.document.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The movement this set was logged against, as the plan prescribed it.
    ///
    /// `nil` when the document does not hold the position the set names, which
    /// is a real state rather than an error: a block can be reimported over one
    /// already trained. The set is still reported; what was asked of it is
    /// reported as unknown rather than guessed at.
    func exercise(for record: LoggedSetRecord) -> PlanDocumentExercise? {
        guard
            let routine = routines[record.routineID],
            routine.document.weeks.indices.contains(record.weekOrdinal - 1),
            let day = routine.document.weeks[record.weekOrdinal - 1]
                .days.first(where: { $0.weekday == record.weekday })
        else { return nil }
        let exercises = day.entries.flatMap(\.exercises)
        guard exercises.indices.contains(record.exerciseOrder) else { return nil }
        return exercises[record.exerciseOrder]
    }

    /// What was asked of this set in particular — its own row of the
    /// prescription when the plan listed its sets one at a time, and the
    /// exercise's otherwise.
    func prescription(for record: LoggedSetRecord) -> SetPrescription? {
        guard let exercise = exercise(for: record) else { return nil }
        let sets = exercise.prescribedSets
        guard sets.indices.contains(record.setIndex) else { return nil }
        return sets[record.setIndex]
    }

    /// The group this set's movement was performed in, or `nil` when it was
    /// performed on its own.
    func group(for record: LoggedSetRecord) -> PlanDocumentGroup? {
        guard
            let routine = routines[record.routineID],
            routine.document.weeks.indices.contains(record.weekOrdinal - 1),
            let day = routine.document.weeks[record.weekOrdinal - 1]
                .days.first(where: { $0.weekday == record.weekday })
        else { return nil }
        var position = 0
        for entry in day.entries {
            let count = entry.exercises.count
            if (position..<(position + count)).contains(record.exerciseOrder) {
                return entry.group
            }
            position += count
        }
        return nil
    }
}
