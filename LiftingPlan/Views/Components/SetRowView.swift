import SwiftUI
import SwiftData
import LiftingKit

/// One editable set row: a set badge, the previous session's result, inline
/// weight and reps fields, and a check to complete it (which starts the rest
/// timer). Row tint for the completed state is applied by the enclosing list.
///
/// Weight is entered and displayed in `unit` (the lifter's `profile.displayUnit`)
/// regardless of what unit `set.load` was originally logged in — the field
/// always shows and writes a value converted to `unit`, so the day Claude is
/// told the lifter thinks in kilos, no row is stranded showing the old number.
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
    /// while it is empty — `"8-12"`, `"AMRAP"`, `"30"` — and nothing at all when
    /// the plan named none. It is a placeholder rather than a value so the
    /// prescription reaches the lifter without the app claiming he lifted it.
    /// A hold and a carry arrive as the figure alone, because the row draws
    /// their unit beside the field; see `WorkPrescription.targetFigure`.
    /// Sets of one exercise may carry different targets: a ramp and a drop set
    /// are exactly that.
    var repTargetText: String
    /// The load the plan prescribed for this set, shown the same way and for
    /// the same reason. Empty when it prescribed none — a dash in a field whose
    /// job is to invite a number hints at nothing.
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
    /// Whether the session this row belongs to has been marked finished.
    ///
    /// **A finished session is a statement, not a draft.** It is what the coach
    /// has already read, so the figures stop being editable until the lifter
    /// says otherwise — which he does with the button at the foot of the screen,
    /// never by being refused here. Nothing is greyed: the record reads exactly
    /// as it did, and what goes is the rule under each field, which is the mark
    /// that says *write here*.
    var isLocked: Bool = false
    /// Called when the check changes, with what it changed to. Unchecking is
    /// reported as well as checking: a set taken back is a set that did not
    /// happen, and the rest it started has nothing left to be resting from.
    var onCompletionChanged: (Bool) -> Void

    // Every binding here is plumbing: the reading and the writing are
    // `SetEntry`'s, which is a pure function over a string and therefore
    // something a test can type into. What a field means was the least covered
    // code in the app while it lived in these closures.
    private var weightText: Binding<String> {
        Binding(
            get: { SetEntry.text(for: set.load, in: unit) },
            set: { set.load = SetEntry.load(from: $0, in: unit) }
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
            get: { SetEntry.text(forReps: set.reps) },
            set: { set.reps = SetEntry.reps(from: $0) }
        )
    }

    /// A hold, in seconds. Cleared to `nil` rather than to zero when the field
    /// is emptied — a set that was not timed did not last no time.
    private var durationText: Binding<String> {
        Binding(
            get: { SetEntry.text(forSeconds: set.durationSeconds) },
            set: { set.durationSeconds = SetEntry.seconds(from: $0) }
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
            get: { SetEntry.text(for: set.distance) },
            set: { set.distance = SetEntry.distance(from: $0, in: unit) }
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
                    .font(.supersetSupport)
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
            if isLocked {
                badge
            } else {
                Menu {
                    Picker("Kind of set", selection: kind) {
                        Text("Working set").tag(false)
                        Text("Warm-up").tag(true)
                    }
                } label: {
                    badge.contentShape(.rect)
                }
                .accessibilityLabel(identity.spoken)
                .accessibilityHint("Changes whether this set counts as working volume")
            }

            Spacer(minLength: 0)

            field(text: weightText, placeholder: loadTargetText, isDecimal: true)
                // **Named, because a placeholder is not a name.** A `TextField`
                // takes its accessibility label from its placeholder, and this
                // one's placeholder is the prescribed load — so a set prescribed
                // at 185 announced its weight field as "185", beside a work
                // field announcing "8-12". Two fields naming figures, neither
                // naming itself, on the screen where a lifter enters numbers he
                // may not be able to see.
                .accessibilityLabel(SetFieldLabel.load(unit: unit, identity: identity))
            // **The unit, wherever there is a weight to name.** The field said
            // `185` and left the reader to know what in; it says `185 lb` now,
            // in the same device the hold and the carry already use for their
            // seconds and their metres. A dash was the other candidate and is
            // the one thing this field must not draw — a placeholder is a hint
            // about what to type, and a dash hints at nothing.
            //
            // It is drawn under exactly the condition the `×` is, which is what
            // keeps a push-up honest: an exercise carrying no load has an empty
            // field on purpose, and `lb` beside it would be the app asking for
            // a number nobody prescribed.
            // Held rather than removed: a row with no load to name still keeps
            // the slot, so the rep figure sits in the same column as the rep
            // figure above it. Dropped from the stack, the warm-up's reps slid
            // left under the weight column — Jon: *"the alignments off on the 7s
            // when the lb label is gone."* A column is a column on every row of
            // the table or it is not one.
            marker(Text(unit.rawValue), shown: namesALoad)
            // The two figures are one statement — a hundred and thirty-five for
            // eight — and the sign says so. It replaces two column headings
            // redrawn above every exercise of every session, which said the
            // same thing to a lifter who has already used this once.
            //
            // Drawn only where there are two figures to join. A plank carries no
            // load, and `× 45 s` is a sign multiplying nothing.
            marker(Text("×"), shown: joinsTwoFigures)
            // A distance can be a fraction of its unit; reps and seconds cannot.
            field(text: workText, placeholder: repTargetText, isDecimal: measuresDistance)
                // Named for what this exercise measures, so the field that
                // records a hold says seconds and the one that records a carry
                // says the unit it was prescribed in.
                .accessibilityLabel(SetFieldLabel.work(measure: measure, identity: identity))
            // What the figure beside it is measured in, on the one row that
            // needs saying. A column header used to carry this — `SECS`, or a
            // carry's own unit — and deleting it left a plank reading `34` with
            // nothing anywhere on screen saying seconds. Counted work needs no
            // suffix: the `×` has already said it.
            if let workUnit {
                marker(Text(workUnit), shown: true)
            }

            Spacer(minLength: 0)

            if isLocked {
                mark
            } else {
                Button {
                    complete()
                } label: {
                    mark.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completionLabel)
                .accessibilityAddTraits(set.isCompleted ? [.isSelected] : [])
            }
        }
    }

    /// A word beside a figure — the unit, the sign between two figures — kept
    /// in the layout whether or not this row has anything for it to say. Reading
    /// down a table is reading down columns, and a column that closes up on one
    /// row moves every figure after it.
    private func marker(_ text: Text, shown: Bool) -> some View {
        text
            .font(.supersetSupport)
            .foregroundStyle(Palette.muted)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(!shown)
    }

    /// What the row is called, drawn the same whether or not it can be changed.
    private var badge: some View {
        Text(identity.badge)
            .font(.supersetSupport)
            .foregroundStyle(set.isWarmup ? Palette.muted : Palette.ink)
            .frame(
                width: SetTableMetrics.setColumnWidth,
                height: SetTableMetrics.controlHeight)
    }

    /// Whether the set is in the record, drawn the same either way.
    private var mark: some View {
        RecordedMark(isRecorded: set.isCompleted)
            .frame(
                width: SetTableMetrics.checkColumnWidth,
                height: SetTableMetrics.controlHeight)
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

    /// Whether this row has a load as well as a count — the two things the `×`
    /// sits between. A set with no weight on it, prescribed or entered, has one
    /// figure and needs no sign.
    ///
    /// `self` is written out for the same reason `completionLabel` writes it: a
    /// property body opening with `set` reads as the start of a setter.
    private var joinsTwoFigures: Bool {
        // A locked row draws only what was recorded, and a set he never filled
        // in has one figure — so the sign would be a multiplication with nothing
        // after it. While the row is editable the placeholder stands in for the
        // second figure, which is what the sign is joining.
        guard isLocked else { return namesALoad }
        return namesALoad && !workText.wrappedValue.isEmpty
    }

    /// Whether there is a weight on this row at all — prescribed or entered.
    ///
    /// The unit hangs on this and not on the sign: a set recorded at 185 and
    /// never finished still says what the 185 is, and it was only ever the `×`
    /// that needed two figures.
    private var namesALoad: Bool {
        self.set.load != nil || !loadTargetText.isEmpty
    }

    /// What the second figure is measured in, or `nil` for counted work.
    ///
    /// The suffix exists because the unit is no longer a column heading, and a
    /// number whose unit is not on screen is the failure `WorkMeasure` was built
    /// to prevent — not in the store, which still writes the right field, but
    /// in front of the lifter, who cannot tell a hold from a rep count by
    /// looking at `34`.
    private var workUnit: String? {
        switch measure {
        case .repetitions: nil
        case .time: "s"
        case .distance(let unit): unit.rawValue
        }
    }

    /// Whether the field the lifter types into holds a distance, which is the
    /// one of the three that can be a fraction of its unit.
    private var measuresDistance: Bool {
        if case .distance = measure { return true }
        return false
    }

    @ViewBuilder
    private func field(text: Binding<String>, placeholder: String, isDecimal: Bool) -> some View {
        if isLocked {
            // The figure as the record holds it, in the same type and the same
            // column — and nothing underneath it. A blank one stays blank: a
            // set nobody filled in is a set nobody filled in, and inventing a
            // dash for it now would put a mark in the record after the fact.
            Text(text.wrappedValue)
                .font(.supersetMetric)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, SetTableMetrics.entryInset)
                .frame(
                    width: SetTableMetrics.entryColumnWidth,
                    height: SetTableMetrics.entryHeight)
        } else {
            editableField(text: text, placeholder: placeholder, isDecimal: isDecimal)
        }
    }

    private func editableField(
        text: Binding<String>, placeholder: String, isDecimal: Bool
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(isDecimal ? .decimalPad : .numberPad)
            // **The caret is ink, and stated rather than inherited.** It takes
            // the tint, and the tint is the theme — a highlighter, which on a
            // white panel is a caret nobody can see. Nothing about where this
            // field sits should decide whether the lifter can tell it is
            // focused.
            .tint(Palette.ink)
            .multilineTextAlignment(.center)
            // Not stated. A colour set here paints the placeholder as well, and
            // a prescribed load drawn in the same ink as a logged one is the app
            // claiming he lifted a figure he has not typed — which is the one
            // thing this row must never do. Left to the system, a placeholder
            // reads as grey and what he enters reads as his.
            // The weight and the work are what this screen is for, and they are
            // read at arm's length: they are the type ramp's Metric, which is
            // the role that exists for exactly these two fields.
            .font(.supersetMetric)
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
