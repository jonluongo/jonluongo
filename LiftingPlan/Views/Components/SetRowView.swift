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
/// **The last session's figures are the placeholders, not a column.** A
/// `PREVIOUS` column stood beside the fields reporting what he did last time,
/// which is a quarter of the table's width spent on a number he is about to
/// type over. It sits *in* the field now: the ghost he overwrites is the load
/// he used, so the field opens with a starting point instead of a dash and the
/// column is gone. What the plan prescribed still wins where the two differ —
/// see `SetRowPrescription`.
///
/// **Anything else this set asks sits directly under it**, as a quiet line: the
/// note written about it, and the effort prescribed for it where no load was.
/// A sixth column would crowd five that are already tight, and a block above the
/// table is off-screen by the time the lifter reaches set four. The line is
/// drawn only when it has something to say, so an ordinary set of an ordinary
/// prescription is exactly the row it always was.
///
/// **Nothing on this row asks the lifter how hard it felt.** He is not rated and
/// does not rate himself; what he put up is the whole of what he reports, and
/// what was asked of him sits beside it in the record.
struct SetRowView: View {
    @Bindable var set: LoggedSet
    /// What this row is called — the badge it draws and the name it says aloud.
    /// A number on an exercise of its own, `A1` inside a group.
    var identity: SetIdentity
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
    /// own note, and the effort asked of it where no load was — or `nil` when it
    /// asks nothing of its own, which is the ordinary case and draws nothing.
    var prescriptionDetail: String?
    /// What this row records — reps, a hold, or a distance in the unit it was
    /// prescribed in. Decided by the prescription, in `WorkPrescription`, and
    /// never by what is typed.
    var measure: WorkMeasure
    var unit: MassUnit
    /// Called when the check changes, with what it changed to. Unchecking is
    /// reported as well as checking: a set taken back is a set that did not
    /// happen, and the rest it started has nothing left to be resting from.
    var onCompletionChanged: (Bool) -> Void

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
            // Drawn only when this set says something of its own. Nothing is
            // drawn otherwise, so a uniform prescription gains no line per set
            // for saying nothing new. It gets the row's whole width to wrap in:
            // a sentence squeezed into a column narrower than its own words ran
            // off the edge of the card at accessibility sizes.
            if let prescriptionDetail {
                Text(prescriptionDetail)
                    .font(.barbellSupport)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(identity.badge)
                    .font(.barbellSupport)
                    .foregroundStyle(set.isWarmup ? Palette.accent : Palette.ink)
                    .frame(
                        width: SetTableMetrics.setColumnWidth,
                        height: SetTableMetrics.controlHeight
                    )
                    .contentShape(.rect)
            }
            .accessibilityLabel(identity.spoken)
            .accessibilityHint("Changes whether this set counts as working volume")

            Spacer(minLength: 0)

            field(text: weightText, placeholder: loadTargetText, isDecimal: true)
            // The two figures are one statement — a hundred and thirty-five for
            // eight — and the sign says so. It replaces two column headings
            // redrawn above every exercise of every session, which said the
            // same thing to a lifter who has already used this once.
            Text("×")
                .font(.barbellSupport)
                .foregroundStyle(Palette.muted)
            // A distance can be a fraction of its unit; reps and seconds cannot.
            field(text: workText, placeholder: repTargetText, isDecimal: measuresDistance)

            Spacer(minLength: 0)

            Button {
                complete()
            } label: {
                // A filled square, not a tick in a box. The row is a line of a
                // record and the mark is what puts it there — square because
                // every other edge in this table is square, and filled because
                // a set either happened or it did not.
                RoundedRectangle(cornerRadius: 3)
                    .fill(set.isCompleted ? Palette.recorded : .clear)
                    .stroke(set.isCompleted ? Palette.recorded : Palette.rule, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if set.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.panel)
                        }
                    }
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

    /// Spoken aloud, this control has to say which set it completes. Every row
    /// on the screen is otherwise identical, and inside a group the row's name
    /// is the only thing that says which movement and which round it is.
    /// `self` is written out because a property body opening with `set` reads
    /// as the start of a setter to the parser.
    private var completionLabel: String {
        self.set.isCompleted
            ? "Completed \(identity.spoken)"
            : "Complete \(identity.spoken)"
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
            // Not stated. A colour set here paints the placeholder as well, and
            // a prescribed load drawn in the same ink as a logged one is the app
            // claiming he lifted a figure he has not typed — which is the one
            // thing this row must never do. Left to the system, a placeholder
            // reads as grey and what he enters reads as his.
            // The weight and the work are what this screen is for, and they are
            // read at arm's length: they are the type ramp's Metric, which is
            // the role that exists for exactly these two fields.
            .font(.barbellMetric)
            // A prescribed target like "8-12" is wider than a logged number;
            // shrink it rather than truncate the prescription.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, SetTableMetrics.entryInset)
            .frame(width: SetTableMetrics.entryColumnWidth, height: SetTableMetrics.entryHeight)
            // A ruled cell rather than a filled box. Two grey slabs per row made
            // the table read as a form to complete; a hairline underneath says
            // "write here" in the vocabulary the rest of the grid is drawn in.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.rule)
                    .frame(height: Palette.hairline)
                    .padding(.horizontal, Spacing.tight)
            }
    }

    /// Ticks the set, or takes it back.
    ///
    /// Taking it back used to do nothing beyond clearing the tick — the rest it
    /// had started kept counting down, outlasting the set it was counting for.
    /// The change is reported either way now, so unchecking means what it looks
    /// like it means.
    ///
    /// `completedAt` is stamped on the way in and left alone on the way out. It
    /// is not optional, so there is no absence to write; and nothing reads it
    /// without first asking `isCompleted`, which is what actually says whether
    /// the set happened.
    private func complete() {
        set.isCompleted.toggle()
        if set.isCompleted { set.completedAt = Date() }
        onCompletionChanged(set.isCompleted)
    }
}
