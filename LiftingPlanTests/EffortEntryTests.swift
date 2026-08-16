import Testing
import SwiftData
import Foundation
@testable import LiftingPlan
import LiftingKit

/// How hard a set felt, from the field the lifter will type it into to the
/// snapshot the coach reads.
///
/// The gap these close is the one-directional loop an audit named: `LoggedSet`
/// has carried `rpe` all along and the snapshot has always reported it, so Claude
/// could read an effort rating the lifter had no way to enter. The screen is not
/// built here — it is Task 5 — but the value it will write now has somewhere to
/// go and a seam to go through, and these prove it arrives intact.
///
/// **Absence is absence.** A set nobody rated has no rating, not a rating of
/// zero. Intensity entry is offered only where the plan named an intensity
/// target, so most sets will never be rated at all and the difference between
/// "not rated" and "rated 0" is the difference between silence and a claim.
@Suite("Effort the lifter reports")
struct EffortEntryTests {

    private static let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private static let bench = ExerciseID(rawValue: "barbell-bench-press")

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    // MARK: - Which sets are asked how hard they felt

    @Test("A set the plan prescribed an effort for invites one")
    func prescribedEffortInvitesEntry() {
        let prescribed = SetPrescription(
            repRange: "5", intensity: IntensityTarget(scale: .rpe, value: "8"))

        #expect(EffortEntry.isInvited(by: prescribed))
    }

    @Test("An effort on any scale invites one, including a scale this build never heard of")
    func anyScaleInvitesEntry() {
        for scale in [IntensityScale.repsInReserve, .percentOfOneRepMax,
                      IntensityScale(rawValue: "how it felt")] {
            #expect(EffortEntry.isInvited(
                by: SetPrescription(intensity: IntensityTarget(scale: scale, value: "2"))))
        }
    }

    @Test("A set the plan named no effort for is not asked for one")
    func unprescribedEffortInvitesNothing() {
        #expect(!EffortEntry.isInvited(by: SetPrescription(repRange: "8-12")))
    }

    @Test("A set the plan said nothing about at all is not asked either")
    func absentPrescriptionInvitesNothing() {
        #expect(!EffortEntry.isInvited(by: nil))
    }

    @Test("A target with no value to read is not a target")
    func blankTargetInvitesNothing() {
        #expect(!EffortEntry.isInvited(
            by: SetPrescription(intensity: IntensityTarget(scale: .rpe, value: "  "))))
    }

    // MARK: - What the lifter types becomes

    @Test("A rating typed as a whole number is read as it was typed")
    func wholeNumberIsRead() {
        #expect(EffortEntry.rating(from: "8") == 8)
    }

    @Test("A half point is kept rather than rounded away")
    func halfPointIsKept() {
        #expect(EffortEntry.rating(from: "8.5") == 8.5)
        #expect(EffortEntry.rating(from: "8,5") == 8.5, "a comma is a decimal point to most of us")
    }

    @Test("A rating outside the usual scale is recorded as typed, not clamped")
    func nothingIsClamped() {
        #expect(EffortEntry.rating(from: "11") == 11)
        #expect(EffortEntry.rating(from: "0.5") == 0.5)
    }

    @Test("An emptied field clears the rating rather than recording a zero")
    func emptyFieldClearsToAbsent() {
        #expect(EffortEntry.rating(from: "") == nil)
        #expect(EffortEntry.rating(from: "   ") == nil)
    }

    @Test("A rating of zero is a rating, and is not the same as none")
    func zeroIsNotAbsence() {
        #expect(EffortEntry.rating(from: "0") == 0)
        #expect(EffortEntry.rating(from: "0") != EffortEntry.rating(from: ""))
    }

    @Test("Something that is not a number rates nothing")
    func nonsenseRatesNothing() {
        #expect(EffortEntry.rating(from: "hard") == nil)
    }

    @Test("A rating reads back as the field it was typed into, and no rating as an empty one")
    func ratingReadsBackAsTyped() {
        #expect(EffortEntry.text(for: 8) == "8")
        #expect(EffortEntry.text(for: 8.5) == "8.5")
        #expect(EffortEntry.text(for: nil) == "")
        #expect(EffortEntry.text(for: 0) == "0", "zero was rated; it is not an empty field")
    }

    // MARK: - What reaches the coach

    /// A store holding one set logged against a prescription that asked for an
    /// effort, exported whole.
    private func exportedSnapshot(rpe: Double?) throws -> TrainingSnapshot {
        let context = try context()
        let document = PlanDocument(
            id: UUID(), catalogVersion: 5, generatedAt: Self.instant,
            days: [PlanDocumentDay(
                weekday: .monday,
                exercises: [PlanDocumentExercise(
                    exerciseID: Self.bench, displayName: "Barbell Bench Press",
                    sets: 1, repRange: "5",
                    intensity: IntensityTarget(scale: .rpe, value: "8"))])]
        )
        let plan = try PlanImporter.import(
            document, into: context, catalog: try ExerciseCatalog.bundled(),
            importedAt: Self.instant)
        let exercise = try #require(
            plan.orderedWeeks.first?.orderedDays.first?.orderedExercises.first)
        let set = LoggedSet(
            setIndex: 0, load: Mass(value: 100, unit: .kilograms), reps: 5,
            rpe: rpe, isCompleted: true, completedAt: Self.instant)
        context.insert(set)
        set.exercise = exercise
        try context.save()

        return try SnapshotExporter.export(
            from: context, catalogVersion: 5, generatedAt: Self.instant)
    }

    /// The one set that store holds, as the coach reads it.
    private func exported(rpe: Double?) throws -> SnapshotLoggedSet {
        try #require(
            exportedSnapshot(rpe: rpe)
                .plans.first?.weeks.first?.days.first?.exercises.first?.loggedSets.first)
    }

    @Test("An effort written on a set reaches the snapshot")
    func ratingReachesTheSnapshot() throws {
        #expect(try exported(rpe: 8.5).rpe == 8.5)
    }

    @Test("A set nobody rated reports no effort at all, never a zero")
    func absenceReachesTheSnapshotAsAbsence() throws {
        let reported = try exported(rpe: nil)

        #expect(reported.rpe == nil)
        #expect(reported.reps == 5, "the rest of the set is unaffected")
    }

    @Test("A set rated zero reports zero, which is not the same as saying nothing")
    func zeroReachesTheSnapshotAsZero() throws {
        let reported = try exported(rpe: 0)

        #expect(reported.rpe == 0)
        #expect(reported.rpe != nil, "he answered; the answer happens to be zero")
    }

    @Test("An effort survives the snapshot's own encoding, whole")
    func ratingSurvivesEncoding() throws {
        let snapshot = try exportedSnapshot(rpe: 9.5)

        let data = try TrainingSnapshot.makeEncoder().encode(snapshot)
        let decoded = try TrainingSnapshot.makeDecoder()
            .decode(TrainingSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(String(decoding: data, as: UTF8.self).contains("\"rpe\" : 9.5"))
    }

    @Test("A set nobody rated writes no 'rpe' key at all, rather than a zero")
    func absenceWritesNoKey() throws {
        let data = try TrainingSnapshot.makeEncoder().encode(exportedSnapshot(rpe: nil))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plans = try #require(root["plans"] as? [[String: Any]])
        let weeks = try #require(plans.first?["weeks"] as? [[String: Any]])
        let days = try #require(weeks.first?["days"] as? [[String: Any]])
        let exercises = try #require(days.first?["exercises"] as? [[String: Any]])
        let sets = try #require(exercises.first?["loggedSets"] as? [[String: Any]])

        #expect(sets.first?["rpe"] == nil, "he said nothing; a zero would be an answer")
        #expect(sets.first?["reps"] as? Int == 5, "the rest of the set is on the wire")
    }

    // MARK: - The store itself

    @Test("A set nobody rated holds no rating, not a zero")
    func unratedSetHoldsNothing() throws {
        let context = try context()
        let set = LoggedSet(setIndex: 0, reps: 5)
        context.insert(set)
        try context.save()

        #expect(set.rpe == nil)
    }

    @Test("A rating written onto a set is saved and read back")
    func ratingIsSavedAndReadBack() throws {
        let context = try context()
        let set = LoggedSet(setIndex: 0, reps: 5)
        context.insert(set)
        set.rpe = EffortEntry.rating(from: "9.5")
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<LoggedSet>()).first)
        #expect(stored.rpe == 9.5)
    }

    @Test("Clearing the field takes the rating back to absent rather than to zero")
    func clearingTakesTheRatingBack() throws {
        let context = try context()
        let set = LoggedSet(setIndex: 0, reps: 5, rpe: 9)
        context.insert(set)
        set.rpe = EffortEntry.rating(from: "")
        try context.save()

        #expect(set.rpe == nil)
    }
}
