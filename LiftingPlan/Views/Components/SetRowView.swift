import SwiftUI
import SwiftData
import LiftingKit

/// One editable set row: a set badge, the previous session's result, inline
/// weight and reps fields, and a check to complete it (which starts the rest
/// timer). Row tint for the completed state is applied by the enclosing list.
///
/// Weight is entered and displayed in `unit` (the lifter's `profile.displayUnit`)
/// regardless of what unit `set.load` was originally logged in — the field
/// always shows/writes a value converted to `unit`, so switching units in
/// Settings doesn't strand a row showing the wrong number.
///
/// **The second field records what the plan prescribed, in the unit it
/// prescribed it in.** For counted work it writes `set.reps`; for a hold it
/// writes `set.durationSeconds`; for a carry it writes `set.distance` in the
/// unit the carry was prescribed in. Exactly one of the three is ever written,
/// because `measure` is one value rather than a pair of flags. The number the
/// lifter types under a placeholder reading "30 seconds" is thirty-four
/// *seconds*, and writing it into a rep count is how a plank became thirty-four
/// repetitions in every report that followed.
///
/// **Anything else this set asks or is asked sits directly under it**, in
/// `SetDetailLine` — the effort prescribed for this set alone, the note written
/// about it, and the field that records how hard it felt. A sixth column would
/// crowd five that are already tight, and a block above the table is off-screen
/// by the time the lifter reaches set four. The line is drawn only when it has
/// something to say, so an ordinary set of an ordinary prescription is exactly
/// the row it always was.
struct SetRowView: View {
    @Bindable var set: LoggedSet
    /// 1-based working-set number, ignored when the row is a warmup.
    var workingNumber: Int
    var previousText: String
    /// The target the plan prescribed *for this set*, shown in the second field
    /// while it is empty — `"8-12"`, `"AMRAP"`, `"30 seconds"`, or `"—"` when
    /// the plan named none. It is a placeholder rather than a value so the
    /// prescription reaches the lifter without the app claiming he lifted it.
    /// Sets of one exercise may carry different targets: a ramp and a drop set
    /// are exactly that.
    var repTargetText: String
    /// The load the plan prescribed for this set, shown the same way and for
    /// the same reason. `"—"` when it prescribed none.
    var loadTargetText: String
    /// What this set asks that the exercise's header has not already said — its
    /// own effort target, its own note — or `nil` when it asks nothing of its
    /// own, which is the ordinary case and draws nothing.
    var prescriptionDetail: String?
    /// The intensity the plan asked of this set, or `nil` when it asked none.
    /// Carried rather than reduced to a flag so the field can be labelled with
    /// the scale the plan named and show the number it asked for.
    var intensity: IntensityTarget?
    /// What this row records — reps, a hold, or a distance in the unit it was
    /// prescribed in. Decided by the prescription, in `WorkPrescription`, and
    /// never by what is typed.
    var measure: WorkMeasure
    var unit: MassUnit
    var onComplete: () -> Void

    private var weightText: Binding<String> {
        Binding(
            get: { set.load.map { $0.converted(to: unit).value.compactString } ?? "" },
            set: { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
                    set.load = nil
                    return
                }
                set.load = Mass(value: value, unit: unit)
            }
        )
    }

    /// The second field's text, bound to whichever of the three things this row
    /// records. Nothing is ever written to more than one: a row is counted, or
    /// held, or carried.
    private var workText: Binding<String> {
        switch measure {
        case .repetitions: repsText
        case .time: durationText
        case .distance(let unit): distanceText(in: unit)
        }
    }

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps > 0 ? String(set.reps) : "" },
            set: { set.reps = Int($0.filter(\.isNumber)) ?? 0 }
        )
    }

    /// A hold, in seconds. Cleared to `nil` rather than to zero when the field
    /// is emptied — a set that was not timed did not last no time.
    private var durationText: Binding<String> {
        Binding(
            get: { set.durationSeconds.map(String.init) ?? "" },
            set: { set.durationSeconds = Int($0.filter(\.isNumber)) }
        )
    }

    /// A carry, in the unit the plan prescribed it in — which is the unit named
    /// in the column header above the field, so the number he types and the
    /// number the log keeps are the same measurement. Cleared to `nil` rather
    /// than to zero when the field is emptied: a set that was not carried did
    /// not travel no distance. Nothing here converts, so a carry prescribed in
    /// yards is recorded in yards.
    private func distanceText(in unit: DistanceUnit) -> Binding<String> {
        Binding(
            get: { set.distance.map { $0.value.compactString } ?? "" },
            set: { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
                    set.distance = nil
                    return
                }
                set.distance = Distance(value: value, unit: unit)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            columns
            // Drawn only when this set says something of its own or is asked
            // something of its own. Nothing is drawn otherwise, so a uniform
            // prescription gains no line per set for saying nothing new.
            if prescriptionDetail != nil || intensity != nil {
                SetDetailLine(
                    set: set,
                    detail: prescriptionDetail,
                    intensity: intensity,
                    spokenSetName: spokenSetName
                )
            }
        }
    }

    private var columns: some View {
        HStack(spacing: SetTableMetrics.columnGutter) {
            // The set badge names what the row is, and changing that is a
            // deliberate choice from a menu rather than a toggle under a
            // fingertip. It used to flip on a single tap: a mis-tap eight
            // points from a number field silently took a set out of the
            // lifter's working volume and out of everything the coach reads,
            // with nothing on screen to say it had happened.
            Menu {
                Picker("Kind of set", selection: kind) {
                    Text("Working set").tag(false)
                    Text("Warm-up").tag(true)
                }
            } label: {
                Text(set.isWarmup ? "W" : "\(workingNumber)")
                    .font(.barbellSupport)
                    .foregroundStyle(set.isWarmup ? .orange : .primary)
                    .frame(
                        width: SetTableMetrics.setColumnWidth,
                        height: SetTableMetrics.controlHeight
                    )
                    .contentShape(.rect)
            }
            .accessibilityLabel(
                set.isWarmup ? "Warm-up set" : "Working set \(workingNumber)"
            )
            .accessibilityHint("Changes whether this set counts as working volume")

            Text(previousText)
                .font(.barbellSupport)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)

            field(text: weightText, placeholder: loadTargetText, isDecimal: true)
            // A distance can be a fraction of its unit; reps and seconds cannot.
            field(text: workText, placeholder: repTargetText, isDecimal: measuresDistance)

            Button {
                complete()
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.barbellMetric)
                    .foregroundStyle(set.isCompleted ? .green : .secondary)
                    .frame(
                        width: SetTableMetrics.checkColumnWidth,
                        height: SetTableMetrics.controlHeight
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completionLabel)
            .accessibilityAddTraits(set.isCompleted ? [.isSelected] : [])
        }
    }

    /// Whether this row counts as working volume. Written through a picker so
    /// the change is stated rather than stumbled into.
    private var kind: Binding<Bool> {
        Binding(get: { set.isWarmup }, set: { set.isWarmup = $0 })
    }

    /// How this row is named aloud. Every row on the screen is otherwise
    /// identical, so each control on one has to say which set it belongs to.
    /// `self` is written out because a property body opening with `set` reads
    /// as the start of a setter to the parser.
    private var spokenSetName: String {
        self.set.isWarmup ? "warm-up set" : "set \(workingNumber)"
    }

    /// Spoken aloud, this control has to say which set it completes.
    private var completionLabel: String {
        self.set.isCompleted
            ? "Completed \(spokenSetName)"
            : "Complete \(spokenSetName)"
    }

    /// Whether the field the lifter types into holds a distance, which is the
    /// one of the three that can be a fraction of its unit.
    private var measuresDistance: Bool {
        if case .distance = measure { return true }
        return false
    }

    private func field(text: Binding<String>, placeholder: String, isDecimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(isDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            // The weight and the work are what this screen is for, and they are
            // read at arm's length: they are the type ramp's Metric, which is
            // the role that exists for exactly these two fields.
            .font(.barbellMetric)
            // A prescribed target like "8-12" is wider than a logged number;
            // shrink it rather than truncate the prescription.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: SetTableMetrics.entryColumnWidth, height: SetTableMetrics.entryHeight)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: Radius.small))
    }

    private func complete() {
        let wasCompleted = set.isCompleted
        set.isCompleted.toggle()
        if set.isCompleted {
            set.completedAt = Date()
            if !wasCompleted { onComplete() }
        }
    }
}
