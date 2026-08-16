import Foundation
import SwiftData
import LiftingKit

/// Applies a `ProfileUpdate` — the standing facts Claude learned — to the
/// stored `UserProfile`.
///
/// Call `apply(_:to:)` with the app's `ModelContext`; it returns the profile as
/// it now stands. This is the inbound mirror of the profile half of
/// `SnapshotExporter`, and the only path by which a fact about the lifter enters
/// the database: the app has no setup screen and asks him nothing.
///
/// **It merges, and it records what it is given.** A field the update says
/// nothing about is left exactly as it was — that is what lets one fact be
/// recorded at a time without restating the rest. A field the update sets to
/// `null` returns to not-known rather than to a plausible default, which is the
/// only way a fact recorded in error can be taken back. Nothing here validates
/// a training judgement, and nothing substitutes a value for one that is
/// missing.
///
/// **An update is applied once.** `UserProfile.appliedProfileUpdateID` records
/// the last one, so an update left sitting in the shared folder is not
/// re-imposed at every launch over something the lifter has changed since.
///
/// Depends on: `ProfileUpdate` from LiftingKit and the `Store/` models.
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
    /// Throws `PersistenceError.saveFailed` when the write fails, and whatever
    /// the fetch throws.
    @discardableResult
    static func apply(
        _ update: ProfileUpdate,
        to context: ModelContext,
        appliedAt: Date = Date()
    ) throws -> UserProfile {
        let profile = try existingProfile(in: context) ?? inserted(into: context)
        guard profile.appliedProfileUpdateID != update.id else { return profile }

        profile.displayUnit = update.displayUnit.resolved(from: profile.displayUnit)
            ?? Self.fallbackDisplayUnit
        profile.experience = update.experience.resolved(from: profile.experience)
        profile.equipmentAccess = update.equipmentAccess.resolved(from: profile.equipmentAccess)
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

    /// The profile to write to.
    ///
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
