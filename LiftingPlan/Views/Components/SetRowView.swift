import SwiftUI
import LiftingKit

/// One row of a set table: what was asked for, what he did, and the tick.
///
/// **A row is a prescription until he performs it.** This used to bind straight
/// to a stored row that existed from the moment the screen opened, and carried
/// six `Binding<String>` properties translating between that row's fields and
/// the two text fields on screen. There is nothing stored to bind to now: the
/// fields hold text, the tick commits it, and untick takes it back out of the
/// record.
///
/// **What is typed never decides what is recorded.** The prescription says
/// whether this set is counted, held or carried, and the number goes into that
/// field and no other. A user tapping the wrong box cannot put seconds into a
/// rep total.
///
/// **Nothing on this row asks how hard it felt.** He is not rated and does not
/// rate himself; what he put up is the whole of what he reports.
///
/// **What it depends on.** `TrainingSlot` and `SetRowPrescription` for what the
/// row shows, `SetEntry` to read what he typed, `SetFieldLabel` for what each
/// field says aloud, and `SetTableMetrics` for the columns.
struct SetRowView: View {

    let slot: TrainingSlot
    let prescription: SetRowPrescription
    /// Whether the session has been marked finished. A finished session is a
    /// statement rather than a draft, so its rows are read-only until he
    /// reopens it.
    let isLocked: Bool
    /// Commits what is in the fields, in the measure the prescription named.
    var onRecord: (Mass?, Int?, Int?, Distance?) -> Void
    /// Takes this set back out of the record.
    var onTakeBack: () -> Void

    @State private var loadText = ""
    @State private var workText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            columns
            // Drawn only when this set says something of its own, so a uniform
            // prescription gains no line per row for saying nothing new. It gets
            // the row's whole width to wrap in: a sentence squeezed into a
            // column narrower than its own words ran off the card.
            // A row he added has no prescription to summarise, and inventing a
            // line for it would be the app describing work it never asked for.
            if let planned = slot.planned,
                let detail = PrescriptionSummary.detail(for: planned, in: slot.exercise) {
                Text(detail)
                    .font(.supersetSupport)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: seedFields)
    }

    private var columns: some View {
        HStack(spacing: SetTableMetrics.columnGutter) {
            badge
            Spacer(minLength: 0)
            field(text: $loadText, placeholder: prescription.loadPlaceholder, isDecimal: true)
                .accessibilityLabel(SetFieldLabel.load(unit: .pounds, identity: slot.identity))
            marker(Text(MassUnit.pounds.rawValue), shown: namesALoad)
            marker(Text("×"), shown: joinsTwoFigures)
            field(text: $workText, placeholder: prescription.workPlaceholder, isDecimal: measuresDistance)
                .accessibilityLabel(
                    SetFieldLabel.work(measure: prescription.measure, identity: slot.identity))
            marker(Text(workUnit ?? ""), shown: workUnit != nil)
            check
        }
    }

    /// What the row is called — a number on an exercise of its own, a warm-up
    /// where the coach prescribed one.
    ///
    /// **It states and no longer switches.** It used to open a menu changing
    /// whether the set counted as working volume, which is now the coach's to
    /// say: he prescribes a warm-up, and a set the user adds says which it is
    /// as he adds it.
    private var badge: some View {
        Text(slot.identity.badge)
            .font(.supersetLabel)
            .foregroundStyle(Palette.muted)
            .frame(width: SetTableMetrics.setColumnWidth)
            .accessibilityLabel(slot.identity.spoken)
    }

    /// The tick. On is *this happened*; off takes it back out of the record.
    ///
    /// **`RecordedMark`, not an SF circle.** This app has one mark for *in the
    /// record* and it is drawn in one place; a rebuild that reached for
    /// `checkmark.circle.fill` gave the same idea a second appearance, smaller
    /// and rounder, on the one screen where it is tapped most.
    private var check: some View {
        Button(action: toggle) {
            RecordedMark(isRecorded: slot.isDone)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // **Not `.disabled`, which dims what it touches.** A finished session's
        // marks came out olive-on-olive — the recorded wash showing through a
        // greyed-out tick — and a mark states a *fact*: the set was done, and it
        // is not less done because the session was closed. The fields beside it
        // keep `.disabled`, because an input that cannot be typed into should
        // look like one. `toggle()` refuses the tap either way.
        .allowsHitTesting(!isLocked)
        .frame(width: SetTableMetrics.checkColumnWidth)
        .accessibilityLabel(slot.isDone ? "Recorded, \(slot.identity.spoken)"
                                        : "Record \(slot.identity.spoken)")
        .accessibilityHint(isLocked ? "This session is finished" : "")
    }

    private func toggle() {
        guard !isLocked else { return }
        if slot.isDone { return onTakeBack() }
        commit()
    }

    /// Sends what is in the fields into the measure the prescription named.
    ///
    /// Only one of the three is ever filled. A blank field commits `nil` rather
    /// than a zero: he ticked the set without saying how many, which is not the
    /// same as saying none.
    private func commit() {
        let load = SetEntry.load(from: loadText, in: .pounds)
        switch prescription.measure {
        case .repetitions:
            onRecord(load, SetEntry.reps(from: workText), nil, nil)
        case .time:
            onRecord(load, nil, SetEntry.seconds(from: workText), nil)
        case .distance(let unit):
            onRecord(load, nil, nil, SetEntry.distance(from: workText, in: unit))
        }
    }

    /// Fills the fields from the record when there is one, so reopening a
    /// session shows what he did rather than an empty table.
    private func seedFields() {
        guard let record = slot.record else { return }
        loadText = SetEntry.text(for: record.load, in: .pounds)
        workText = SetEntry.workText(of: record, measure: prescription.measure)
    }

    // MARK: - The markers between the columns

    /// One or two characters — `lb`, `m`, `s`, `×`.
    ///
    /// **It takes the width of its word and is never squeezed.** The row's other
    /// columns are fixed, so a narrow screen has nowhere to take space from
    /// except here. On an iPhone SE at ordinary text size that meant `lb`
    /// wrapping into `l` above `b`: a unit stacked like a fraction next to the
    /// figure it belongs to. The few points it costs come out of the gaps, which
    /// have them to give.
    private func marker(_ text: Text, shown: Bool) -> some View {
        text
            .font(.supersetSupport)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(!shown)
    }

    /// Whether this row has a load to name — a bodyweight movement has none, and
    /// the marker would be labelling an empty column.
    private var namesALoad: Bool { !loadText.isEmpty || !prescription.loadPlaceholder.isEmpty }

    /// The `×` joins a load to what was done with it, so it is drawn wherever
    /// the load column has something to say. A bodyweight movement draws
    /// neither, and the row reads as the single figure it is.
    private var joinsTwoFigures: Bool { namesALoad }

    /// What the work column is measured in, or `nil` for reps — a count needs no
    /// unit, and drawing one would be the row inventing a vocabulary.
    private var workUnit: String? {
        switch prescription.measure {
        case .repetitions: nil
        case .time: "s"
        case .distance(let unit): unit.rawValue
        }
    }

    private var measuresDistance: Bool {
        if case .distance = prescription.measure { return true }
        return false
    }

    private func field(
        text: Binding<String>, placeholder: String, isDecimal: Bool
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.supersetMetric)
            .multilineTextAlignment(.center)
            .keyboardType(isDecimal ? .decimalPad : .numberPad)
            .textFieldStyle(.plain)
            .disabled(isLocked)
            .frame(width: SetTableMetrics.entryColumnWidth,
                   height: SetTableMetrics.entryHeight)
            .minimumScaleFactor(0.6)
            .onChange(of: text.wrappedValue) { _, _ in
                // Editing a row already in the record updates it. Nothing is
                // written for a row that has not been ticked: typing is not
                // claiming the work happened.
                if slot.isDone { commit() }
            }
    }
}
