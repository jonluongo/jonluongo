import SwiftUI
import SwiftData
import LiftingKit

/// The editable body of one exercise's section inside `ActiveWorkoutView`:
/// notes, the prescribed rest, the set table, and "Add Set". Split out to keep
/// `ActiveWorkoutView` focused on the workout's overall flow rather than
/// per-row mechanics.
///
/// Weight is shown and entered in `profile.displayUnit`; `previousText` reads
/// the lifter's most recent performance on this exercise (keyed by
/// `exerciseID`, never by name) and converts it to that same unit.
///
/// **The only thing this section writes is the log.** The prescription — sets,
/// reps, rest — is read and displayed, never edited: a rest the lifter changed
/// in the gym would go out in the snapshot as though Claude had prescribed it,
/// and he would read his own plan back with a number he never wrote. The rest
/// line is a control now, but what it edits is the lifter's clock in
/// `RestPreferences`, which lives outside the store entirely; when his clock and
/// the prescription differ the line names both, so the screen never claims the
/// plan asked for his number.
///
/// **Every per-set statement reaches the lifter on the row it describes.** This
/// section used to draw the whole prescription again as a numbered block above
/// the table; the sentence about set four was off the top of the screen by the
/// time he reached set four. Each row now carries its own: its load and its reps
/// as the placeholders in its two fields, and its effort target and its note in
/// the line underneath. The numbered block still earns its place in
/// `PrescribedExerciseRow`, which states a session that has no rows yet.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onAddSet: (PlannedExercise, Bool) -> Void
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    /// Told which exercise, and whether the set was ticked or taken back.
    var onCompletionChanged: (PlannedExercise, Bool) -> Void
    /// Opens this exercise's clock. Tapping the rest line is the whole of the
    /// rest control now — there is no timer button in the toolbar, because one
    /// button up there could not mean anything specific when every exercise
    /// prescribes its own rest.
    var onEditRest: (PlannedExercise) -> Void

    /// The lifter's own clock, which is not part of the plan and not in the
    /// store. Read here only to draw the line.
    @Environment(RestPreferences.self) private var restPreferences

    private var orderedSets: [LoggedSet] {
        (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// What the plan asked of each set, in order. Read rather than rebuilt so
    /// a ramp or a drop set shows the load and reps of the set actually being
    /// logged rather than one figure standing in for all of them.
    private var prescribedSets: [SetPrescription] { exercise.prescribedSets }

    /// What this exercise's work is measured in — reps, seconds, or a distance
    /// in the unit it was prescribed in. It decides both what the column is
    /// called and which of the three things every row here writes, and it comes
    /// from the prescription and nothing else.
    private var measure: WorkMeasure { WorkPrescription.measure(of: exercise) }

    /// What the rest line says: the plan's rest, and the lifter's clock beside
    /// it whenever the two differ. `nil` when the plan prescribed no rest and
    /// the lifter has asked for nothing.
    private var restLine: String? {
        RestPrescription.line(
            prescribed: exercise.restSeconds,
            lifter: restPreferences.rest(for: exercise.exerciseID),
            timersEnabled: restPreferences.timersEnabled
        )
    }

    var body: some View {
        Group {
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }

            // Shown when the plan prescribed a rest, or when the lifter set a
            // clock of his own on an exercise it did not. Nothing is drawn when
            // neither is true, and nothing invites him to fill the gap in — the
            // menu is where a timer on an unprescribed exercise is asked for.
            if let restLine {
                Button {
                    onEditRest(exercise)
                } label: {
                    HStack(spacing: Spacing.tight) {
                        Label(restLine, systemImage: "timer")
                        Image(systemName: "chevron.right")
                            .font(.barbellLabel)
                    }
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: TapTarget.minimum, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restLine)
                .accessibilityHint("Sets the rest timer for this exercise")
            }

            columnHeader

            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                let number = workingNumber(at: index)
                let prescribed = prescription(forWorkingNumber: number, isWarmup: set.isWarmup)
                SetRowView(
                    set: set,
                    workingNumber: number,
                    previousText: previousText(workingIndex: number - 1, isWarmup: set.isWarmup),
                    repTargetText: RepPrescription.targetText(for: prescribed?.repRange),
                    loadTargetText: loadTargetText(prescribed),
                    prescriptionDetail: PrescriptionSummary.detail(for: prescribed, in: exercise),
                    intensity: EffortEntry.invitation(from: prescribed),
                    measure: measure,
                    unit: profile.displayUnit,
                    onCompletionChanged: { onCompletionChanged(exercise, $0) }
                )
                .listRowBackground(set.isCompleted ? Color.green.opacity(0.12) : nil)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDeleteSet(set, exercise) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                onAddSet(exercise, false)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.barbellSupport)
                    .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    /// The column names. The last-but-one names the unit the rows under it are
    /// actually recorded in — seconds for a hold, the prescribed distance unit
    /// for a carry, repetitions otherwise — so the number the lifter types is
    /// the number the log keeps.
    ///
    /// The widths come from `SetTableMetrics`, which `SetRowView` reads too:
    /// they were the same three numbers written out in both files, and a header
    /// that stops sitting over its column is a table that lies about what it
    /// contains.
    private var columnHeader: some View {
        HStack(spacing: SetTableMetrics.columnGutter) {
            Text("SET").frame(width: SetTableMetrics.setColumnWidth)
            Text("PREVIOUS").frame(maxWidth: .infinity)
            Text(profile.displayUnit.rawValue.uppercased())
                .frame(width: SetTableMetrics.entryColumnWidth)
            Text(workColumnName).frame(width: SetTableMetrics.entryColumnWidth)
            Image(systemName: "checkmark").frame(width: SetTableMetrics.checkColumnWidth)
        }
        .font(.barbellLabel)
        .foregroundStyle(.secondary)
    }

    /// What the second field is called: the unit its rows are recorded in.
    private var workColumnName: String {
        switch measure {
        case .repetitions: "REPS"
        case .time: "SECS"
        case .distance(let unit): unit.rawValue.uppercased()
        }
    }

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int) -> Int {
        orderedSets.prefix(index + 1).filter { !$0.isWarmup }.count
    }

    /// What the plan asked of the working set at `workingNumber`, or `nil` when
    /// it asked for nothing about it — a warmup, or a set the lifter added past
    /// the ones prescribed. Nothing is stretched to cover an extra set: a
    /// fourth row under a three-set prescription is his own, not the plan's.
    private func prescription(
        forWorkingNumber workingNumber: Int, isWarmup: Bool
    ) -> SetPrescription? {
        guard !isWarmup, prescribedSets.indices.contains(workingNumber - 1) else { return nil }
        return prescribedSets[workingNumber - 1]
    }

    /// What an empty weight field shows: the load this set was prescribed, in
    /// the lifter's display unit, or `"—"` when none was. A placeholder rather
    /// than a value, so the prescription reaches him without the app claiming
    /// he lifted it.
    private func loadTargetText(_ prescription: SetPrescription?) -> String {
        guard let load = prescription?.suggestedLoad else { return "—" }
        return load.converted(to: profile.displayUnit).value.compactString
    }

    /// What he did on this set last time, in the unit he did it in. A hold is
    /// reported as the seconds it was held and a carry as the distance it
    /// covered; nothing here converts one measure into another, because they are
    /// not the same measurement.
    private func previousText(workingIndex: Int, isWarmup: Bool) -> String {
        guard !isWarmup, workingIndex >= 0 else { return "—" }
        let previous = PerformanceHistory.latestHistory(
            for: exercise.exerciseID, excluding: exercise, from: plans
        )?.recentSets ?? []
        guard workingIndex < previous.count else { return "—" }
        let record = previous[workingIndex]
        let measured = record.durationSeconds.map { "\($0)s" } ?? record.distance?.description
        let work = measured ?? "\(record.reps)"
        if let load = record.load?.converted(to: profile.displayUnit), load.value > 0 {
            return "\(load.value.compactString) × \(work)"
        }
        return measured != nil ? work : "\(work) reps"
    }
}
