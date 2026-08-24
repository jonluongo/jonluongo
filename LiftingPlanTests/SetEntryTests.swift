import Testing
import Foundation
import SwiftData
@testable import LiftingPlan
import LiftingKit

/// What a user's typing means.
///
/// These rules were the least covered in the app until this suite: they lived
/// inside `SetRowView`'s bindings, and a `Binding` is not a thing a test can
/// type into. They are also the rules the record depends on most — a hold that
/// was not timed must not become a hold of zero, and nothing typed into a work
/// field may reach a rep total unless the row counts reps.
@Suite("Typing into a set")
struct SetEntryTests {

    // MARK: - The weight field

    @Test("A load is shown in the user's own unit")
    func loadIsShownConverted() {
        let hundredKilos = Mass(value: 100, unit: .kilograms)
        #expect(SetEntry.text(for: hundredKilos, in: .kilograms) == "100")
        #expect(SetEntry.text(for: hundredKilos, in: .pounds).hasPrefix("220"))
    }

    @Test("A set logged without a load shows an empty field, not a zero")
    func absentLoadShowsNothing() {
        // A zero would be a claim he lifted nothing, which is a different thing
        // from a bodyweight set nobody put a number on.
        #expect(SetEntry.text(for: nil, in: .pounds).isEmpty)
    }

    @Test("A comma is a decimal point, because the keyboard offers one")
    func commaIsADecimalPoint() {
        #expect(SetEntry.load(from: "2,5", in: .kilograms) == Mass(value: 2.5, unit: .kilograms))
        #expect(SetEntry.load(from: "2.5", in: .kilograms) == Mass(value: 2.5, unit: .kilograms))
    }

    @Test("Typing something that is not a number clears the load")
    func nonsenseClearsTheLoad() {
        // Rather than keeping the last good value, so the field and the record
        // never disagree about what was lifted.
        #expect(SetEntry.load(from: "", in: .pounds) == nil)
        #expect(SetEntry.load(from: "abc", in: .pounds) == nil)
        #expect(SetEntry.load(from: "185", in: .pounds) == Mass(value: 185, unit: .pounds))
    }

    @Test("The unit written is the unit shown, and nothing converts on the way in")
    func loadKeepsTheUnitItWasTypedIn() {
        #expect(SetEntry.load(from: "100", in: .kilograms)?.unit == .kilograms)
        #expect(SetEntry.load(from: "100", in: .pounds)?.unit == .pounds)
    }

    // MARK: - Reps

    @Test("An unstated count shows an empty field; a stated nought shows the nought")
    func repsAreShownOnlyWhenStated() {
        #expect(SetEntry.text(forReps: nil).isEmpty)
        #expect(SetEntry.text(forReps: 8) == "8")
        // **Zero is a number somebody typed.** It used to draw as an empty
        // field, because `reps` was not optional and zero was how absence was
        // spelled — so a set he failed and recorded honestly looked the same as
        // one he never touched.
        #expect(SetEntry.text(forReps: 0) == "0")
    }

    @Test("An emptied rep field says nothing rather than saying none")
    func emptyRepsIsUnstated() {
        // `reps` is optional on the model. A counted set he ticked without
        // typing has no *stated* count — which is not the same as having done
        // none of them, and the coach used to read it as a completed working set
        // at 185 lb by 0.
        #expect(SetEntry.reps(from: "") == nil)
        #expect(SetEntry.reps(from: "   ") == nil)
        #expect(SetEntry.reps(from: "12") == 12)
        #expect(SetEntry.reps(from: "0") == 0, "he said none, which is a statement")
    }

    @Test("A stray character does not swallow the number around it")
    func repsIgnoreNonDigits() {
        #expect(SetEntry.reps(from: "1o2") == 12)
        #expect(SetEntry.reps(from: "8 reps") == 8)
    }

    // MARK: - A hold, which is not a rep count

    @Test("A hold nobody timed is nothing, not zero seconds")
    func untimedHoldIsNil() {
        // The distinction the whole `WorkMeasure` design exists to keep: a set
        // he did not time did not last no time.
        #expect(SetEntry.seconds(from: "") == nil)
        #expect(SetEntry.seconds(from: "abc") == nil)
        #expect(SetEntry.seconds(from: "45") == 45)
    }

    @Test("A hold shows its seconds, and an untimed one shows nothing")
    func holdText() {
        #expect(SetEntry.text(forSeconds: nil).isEmpty)
        #expect(SetEntry.text(forSeconds: 45) == "45")
        // Zero is a hold of no seconds, which somebody did record — so unlike
        // reps it is shown rather than blanked.
        #expect(SetEntry.text(forSeconds: 0) == "0")
    }

    // MARK: - A carry, which is neither

    @Test("A carry that did not happen is nothing, not a distance of zero")
    func absentCarryIsNil() {
        #expect(SetEntry.distance(from: "", in: .metres) == nil)
        #expect(SetEntry.distance(from: "abc", in: .metres) == nil)
        #expect(SetEntry.text(for: nil).isEmpty)
    }

    @Test("A carry keeps the unit it was prescribed in")
    func carryKeepsItsUnit() {
        // Nothing converts a distance, so a carry prescribed in yards is
        // recorded and shown in yards.
        #expect(SetEntry.distance(from: "40", in: .yards)
            == Distance(value: 40, unit: .yards))
        #expect(SetEntry.distance(from: "40", in: .metres)
            == Distance(value: 40, unit: .metres))
        #expect(SetEntry.text(for: Distance(value: 40.5, unit: .yards)) == "40.5")
    }

    @Test("A carry takes a comma for a decimal point too")
    func carryTakesAComma() {
        #expect(SetEntry.distance(from: "12,5", in: .metres)
            == Distance(value: 12.5, unit: .metres))
    }
}

/// What an added row shows before he types into it.
///
/// **A control that works and cannot be found.** An added set has no
/// prescription, so it had neither a value nor a placeholder — two empty boxes
/// that looked like blank space. Editing a recorded row *does* commit, so he
/// could have typed into it; nothing on screen said so.
@MainActor
@Suite("An added row's placeholders")
struct AddedRowPlaceholderTests {

    private func session() throws -> (ModelContext, Session, PlannedExercise) {
        let context = try StoreFixture.imported(StoreFixture.plan(sessions: 1))
        let session = try #require(try StoreFixture.sessions(in: context).first)
        return (context, session, try #require(session.orderedExercises.first))
    }

    private func log(_ context: ModelContext, _ session: Session) -> SessionLog {
        SessionLog(
            session: session, context: context,
            restTimer: RestTimerModel(), restPreferences: RestPreferences())
    }

    @Test("It hints the set he just did, since an extra set is usually that again")
    func itHintsTheSetBefore() throws {
        let (context, session, exercise) = try session()
        let log = log(context, session)
        let first = try #require(SessionOrder.trainingOrder(of: session).first)
        try log.record(first, load: Mass(value: 245, unit: .pounds), work: .repetitions(3))

        try log.addSet(to: exercise, warmup: false,
                       at: Date().addingTimeInterval(120))

        let added = try #require(SessionOrder.trainingOrder(of: session).last)
        let shown = SetRowPrescription(slot: added, previous: nil)
        #expect(added.planned == nil)
        #expect(shown.loadPlaceholder == "245")
        #expect(shown.workPlaceholder == "3")
    }

    @Test("A prescribed row still shows what was prescribed")
    func thePrescriptionStillWins() throws {
        // The hint fills a field that would otherwise be blank. It must never
        // stand in front of a figure the coach wrote.
        let (_, session, _) = try session()
        let slot = try #require(SessionOrder.trainingOrder(of: session).first)
        let shown = SetRowPrescription(slot: slot, previous: nil)

        #expect(shown.loadPlaceholder == "100", "the prescription's own load")
        #expect(shown.workPlaceholder == "5")
    }

    @Test("With nothing recorded yet, an added row hints nothing rather than zero")
    func nothingRecordedHintsNothing() throws {
        let (context, session, exercise) = try session()
        try log(context, session).addSet(to: exercise, warmup: false)

        let added = try #require(SessionOrder.trainingOrder(of: session).last)
        let shown = SetRowPrescription(slot: added, previous: nil)
        #expect(shown.loadPlaceholder == "")
        #expect(shown.workPlaceholder == "")
    }
}

/// The unit a row is drawn in, and typed in.
///
/// **The row wrote `lb` beside every load whatever it was.** A hundred-kilogram
/// bench drew as `100 lb` — the coach's number under a unit he did not write,
/// a 2.2× error reported as a fact — and typing into it recorded pounds against
/// a kilogram prescription. Everything beneath the row already keeps units
/// straight; the view was the one place that threw the answer away.
@MainActor
@Suite("The unit a load is drawn in")
struct LoadUnitTests {

    private func slot(load: Mass?) throws -> TrainingSlot {
        let context = try StoreFixture.imported(
            StoreFixture.plan(sessions: 1, entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench, displayName: "",
                sets: [PlanDocumentSet(target: .repetitions(low: 5, high: nil), load: load)]))]))
        let session = try #require(try StoreFixture.sessions(in: context).first)
        return try #require(SessionOrder.trainingOrder(of: session).first)
    }

    @Test("A kilogram prescription is drawn in kilograms")
    func kilogramsStayKilograms() throws {
        let shown = SetRowPrescription(
            slot: try slot(load: Mass(value: 100, unit: .kilograms)), previous: nil)
        #expect(shown.loadUnit == .kilograms)
        #expect(shown.loadPlaceholder == "100")
    }

    @Test("A pound prescription is drawn in pounds")
    func poundsStayPounds() throws {
        let shown = SetRowPrescription(
            slot: try slot(load: Mass(value: 225, unit: .pounds)), previous: nil)
        #expect(shown.loadUnit == .pounds)
    }

    @Test("A row with no load at all falls to pounds")
    func nothingPrescribedIsPounds() throws {
        // The app's own default, and what an empty field commits.
        let shown = SetRowPrescription(slot: try slot(load: nil), previous: nil)
        #expect(shown.loadUnit == .pounds)
    }
}

/// What a set records, in the measure its prescription named.
///
/// **The one thing this project says it insists on is data integrity**, and a
/// hold logged as reps is exactly the corruption `WorkMeasure` was written to
/// prevent. `SessionLog.record` used to take `reps`, `durationSeconds` and
/// `distance` as three separate optionals and store whatever it was handed —
/// while its own doc comment promised the opposite. These assert the promise
/// against the store, not against the view that happened to be calling it.
@MainActor
@Suite("A performed set records one measure")
struct RecordedMeasureTests {

    /// A store holding one session of one exercise prescribing `target`.
    private func slot(target: Target) throws -> (TrainingSlot, Session, ModelContext) {
        let context = try StoreFixture.imported(
            StoreFixture.plan(sessions: 1, entries: [.exercise(PlanDocumentExercise(
                exerciseID: StoreFixture.bench, displayName: "",
                sets: [PlanDocumentSet(target: target)]))]))
        let session = try #require(try StoreFixture.sessions(in: context).first)
        return (try #require(SessionOrder.trainingOrder(of: session).first), session, context)
    }

    private func log(_ session: Session, _ context: ModelContext) -> SessionLog {
        SessionLog(
            session: session, context: context, restTimer: RestTimerModel(),
            restPreferences: RestPreferences())
    }

    @Test("A hold is written as seconds, and nothing lands in the rep column")
    func aHoldIsHeld() throws {
        let (slot, session, context) = try slot(target: .time(low: 45, high: nil))
        try log(session, context).record(slot, work: .time(seconds: 45))

        let performed = try #require(slot.exercise.session?.performedExercises?.first?.sets?.first)
        #expect(performed.durationSeconds == 45)
        #expect(performed.reps == nil, "a hold is not a count")
        #expect(performed.distance == nil)
    }

    @Test("A carry is written as a distance, in the unit it was prescribed in")
    func aCarryIsCarried() throws {
        let (slot, session, context) = try slot(target: .distance(low: 40, high: nil, unit: .metres))
        try log(session, context).record(slot, work: .distance(Distance(value: 40, unit: .metres)))

        let performed = try #require(slot.exercise.session?.performedExercises?.first?.sets?.first)
        #expect(performed.distance?.unit == .metres)
        #expect(performed.reps == nil, "forty metres is not forty reps")
        #expect(performed.durationSeconds == nil)
    }

    @Test("A count is written as reps")
    func aCountIsCounted() throws {
        let (slot, session, context) = try slot(target: .repetitions(low: 8, high: nil))
        try log(session, context).record(slot, work: .repetitions(8))

        let performed = try #require(slot.exercise.session?.performedExercises?.first?.sets?.first)
        #expect(performed.reps == 8)
        #expect(performed.durationSeconds == nil)
        #expect(performed.distance == nil)
    }

    @Test("A ticked set that said no figure records the tick, not a zero")
    func blankIsAbsenceNotZero() throws {
        // He ticked it without saying how many, which is not the same as saying
        // none — and a zero would be a fact he never stated.
        let (slot, session, context) = try slot(target: .repetitions(low: 8, high: nil))
        try log(session, context).record(slot, work: .repetitions(nil))

        let performed = try #require(slot.exercise.session?.performedExercises?.first?.sets?.first)
        #expect(performed.reps == nil)
    }

    @Test("Every case of WorkDone fills exactly one field")
    func oneMeasureEach() {
        // The fan-out happens in one place and is exhaustive. Asserted over the
        // cases rather than through the store, so a fourth measure that forgets
        // to answer here fails as itself.
        let cases: [WorkDone] = [
            .repetitions(5), .time(seconds: 45),
            .distance(Distance(value: 40, unit: .metres)),
        ]
        for work in cases {
            let filled = [work.reps != nil, work.durationSeconds != nil, work.carried != nil]
            #expect(filled.filter { $0 }.count == 1, "\(work) fills \(filled)")
        }
    }
}
