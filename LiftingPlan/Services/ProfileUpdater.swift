import Foundation
import SwiftData
import LiftingKit

/// Why a profile update could not be applied.
///
/// There is exactly one case, and it is the one `PlanImporter` has: the document
/// named an exercise the catalog does not have. Catch it at the inbox boundary
/// and show `errorDescription` — it names the offending ID, which is what makes
/// the failure fixable. Depends on: `ExerciseID`.
enum ProfileUpdateError: Error, LocalizedError, Equatable {

    /// A baseline named an exercise the catalog does not contain.
    case unknownExercise(ExerciseID)

    var errorDescription: String? {
        switch self {
        case .unknownExercise(let id):
            "This update states a baseline for '\(id.rawValue)', which is not in the exercise "
                + "catalog. Nothing was recorded."
        }
    }
}

/// Applies a `ProfileUpdate` — the standing facts Claude learned — to the
/// stored `UserProfile`.
///
/// Call `apply(_:to:catalog:)` with the app's `ModelContext` and the loaded
/// catalog; it returns the profile as it now stands. This is the inbound mirror
/// of the profile half of `SnapshotExporter`, and the only path by which a fact
/// about the lifter enters the database: the app has no setup screen and asks
/// him nothing.
///
/// **It merges, and it records what it is given.** A field the update says
/// nothing about is left exactly as it was — that is what lets one fact be
/// recorded at a time without restating the rest. A field the update sets to
/// `null` returns to not-known rather than to a plausible default, which is the
/// only way a fact recorded in error can be taken back. Nothing here validates
/// a training judgement, and nothing substitutes a value for one that is
/// missing.
///
/// **Bodyweight and baselines are series, and each record replaces the one it is
/// about.** A weigh-in is filed under its day, so a new day is added and a day
/// already recorded is corrected; a baseline is filed under its lift, because a
/// lift has one starting point and progress after it lives in the log. An
/// update carrying none of them leaves both series untouched — silence is not a
/// clearing.
///
/// **One thing is checked and nothing is changed.** Every baseline's
/// `exerciseID` must exist in the catalog, for the reason `PlanImporter` checks
/// a prescription's: history is keyed on exercise identity, and an unknown key
/// would anchor a series nothing else will ever join. An unknown ID fails the
/// whole apply and writes nothing at all.
///
/// **An update is applied once.** `UserProfile.appliedProfileUpdateID` records
/// the last one, so an update left sitting in the shared folder is not
/// re-imposed at every launch over something the lifter has changed since.
///
/// Depends on: `ProfileUpdate` and `ExerciseCatalogProviding` from LiftingKit,
/// and the `Store/` models.
enum ProfileUpdater {

    /// Applies `update`, saves, and returns the profile it wrote to.
    ///
    /// A store with no profile yet gets one: an update can arrive before the
    /// first launch has finished creating the record, and dropping it would
    /// leave Claude believing it had recorded something it had not.
    ///
    /// Re-applying an update already applied returns the profile untouched:
    /// nothing is written and `updatedAt` does not move.
    ///
    /// Throws `ProfileUpdateError.unknownExercise` when a baseline names an
    /// exercise the catalog does not have, `PersistenceError.saveFailed` when
    /// the write fails, and whatever the fetches throw.
    /// Whether this update's identity has already been applied.
    ///
    /// Asked by `DocumentInbox` before applying, for the same reason
    /// `PlanImporter.isImported` is: an update announced again is not an update
    /// that landed. It reads the same field `apply` guards on, so the two
    /// cannot disagree.
    static func isApplied(_ update: ProfileUpdate, in context: ModelContext) throws -> Bool {
        try existingProfile(in: context)?.appliedProfileUpdateID == update.id
    }

    @discardableResult
    static func apply(
        _ update: ProfileUpdate,
        to context: ModelContext,
        catalog: any ExerciseCatalogProviding,
        appliedAt: Date = Date()
    ) throws -> UserProfile {
        // Checked in full before anything is written, so an update with one bad
        // ID cannot leave half its facts recorded behind it.
        try confirmEveryBaselineExists(in: update, using: catalog)

        let profile = try existingProfile(in: context) ?? inserted(into: context)
        guard profile.appliedProfileUpdateID != update.id else { return profile }

        profile.displayUnit = update.displayUnit.resolved(from: profile.displayUnit)
            ?? Self.fallbackDisplayUnit
        profile.experience = update.experience.resolved(from: profile.experience)
        profile.ownedEquipment = update.equipment.resolved(from: profile.ownedEquipment)
        // Free text says "not said" with an empty string rather than with an
        // optional, so taking the fact back empties it.
        profile.goal = update.goal.resolved(from: profile.goal) ?? ""
        profile.constraints = update.constraints.resolved(from: profile.constraints) ?? ""
        profile.avoidedPatterns = Set(
            update.avoidedPatterns.resolved(from: Array(profile.avoidedPatterns)) ?? [])
        profile.avoidedExercises = Set(
            update.avoidedExercises.resolved(from: Array(profile.avoidedExercises)) ?? [])
        profile.preferredWeekdays = Set(
            update.preferredWeekdays.resolved(from: Array(profile.preferredWeekdays)) ?? [])
        profile.preferredDurationMinutes = update.preferredDurationMinutes
            .resolved(from: profile.preferredDurationMinutes)

        try record(update.bodyweight, from: update.generatedAt, in: context, on: profile)
        try record(update.baselines, from: update.generatedAt, in: context)

        profile.appliedProfileUpdateID = update.id
        profile.updatedAt = appliedAt
        try context.saveOrThrow()
        return profile
    }

    /// What the display unit falls back to when an update takes it back.
    ///
    /// Not a training opinion and not a claim about the lifter: the app has to
    /// render a number in some unit, and there is no such thing as a weight
    /// shown in no unit at all.
    private static let fallbackDisplayUnit = MassUnit.pounds

    // MARK: - The series

    /// Files each reading under its day, and carries the latest one onto the
    /// profile.
    ///
    /// **A day is the key.** A lifter has one bodyweight on a given day, so a
    /// second statement about that day is a correction of the first rather than
    /// a second measurement — which is what makes appending and correcting one
    /// verb, with no delete to get wrong and no history quietly discarded. The
    /// day is the device's own reckoning of a day, since that is the calendar
    /// the lifter stood on the scale in.
    ///
    /// `UserProfile.bodyweight` is the latest reading in the series rather than
    /// whatever this update happened to carry, so the convenience copy cannot
    /// disagree with the history it is a copy of.
    private static func record(
        _ readings: [BodyweightReading], from generatedAt: Date,
        in context: ModelContext, on profile: UserProfile
    ) throws {
        guard !readings.isEmpty else { return }
        var stored = try context.fetch(
            FetchDescriptor<BodyMetric>(sortBy: [SortDescriptor(\.date)]))
        let calendar = Calendar.current

        for reading in readings {
            let date = reading.resolvedDate(from: generatedAt)
            let day = calendar.startOfDay(for: date)
            if let existing = stored.first(where: { calendar.startOfDay(for: $0.date) == day }) {
                existing.date = date
                existing.bodyweight = reading.mass
            } else {
                let metric = BodyMetric(date: date, bodyweight: reading.mass)
                context.insert(metric)
                stored.append(metric)
            }
        }
        profile.bodyweight = stored.max { $0.date < $1.date }?.bodyweight
    }

    /// Files each baseline under its lift.
    ///
    /// **The lift is the key.** A baseline is the starting point for a movement
    /// with no logged history, and two of them for one lift is two answers to
    /// one question; what happened after that point is in the log, where it can
    /// be read set by set.
    private static func record(
        _ statements: [BaselineStatement], from generatedAt: Date, in context: ModelContext
    ) throws {
        guard !statements.isEmpty else { return }
        var stored = try context.fetch(FetchDescriptor<StrengthBaseline>())

        for statement in statements {
            let recordedAt = statement.resolvedDate(from: generatedAt)
            if let existing = stored.first(where: { $0.exerciseID == statement.exerciseID }) {
                existing.load = statement.load
                existing.reps = statement.reps
                existing.recordedAt = recordedAt
            } else {
                let baseline = StrengthBaseline(
                    exerciseID: statement.exerciseID, load: statement.load,
                    reps: statement.reps, recordedAt: recordedAt
                )
                context.insert(baseline)
                stored.append(baseline)
            }
        }
    }

    /// Throws for the first baseline the catalog does not have, in document
    /// order, so the error names the one to fix rather than an arbitrary one.
    private static func confirmEveryBaselineExists(
        in update: ProfileUpdate, using catalog: any ExerciseCatalogProviding
    ) throws {
        for statement in update.baselines
        where catalog.exercise(id: statement.exerciseID) == nil {
            throw ProfileUpdateError.unknownExercise(statement.exerciseID)
        }
    }

    // MARK: - The profile to write to

    /// Exactly one is expected, but CloudKit cannot enforce uniqueness, so the
    /// most recently updated one is the honest answer if a duplicate ever syncs
    /// in — the same choice `SnapshotExporter` makes when reading.
    private static func existingProfile(in context: ModelContext) throws -> UserProfile? {
        try context.fetch(
            FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        ).first
    }

    private static func inserted(into context: ModelContext) -> UserProfile {
        let profile = UserProfile()
        context.insert(profile)
        return profile
    }
}
