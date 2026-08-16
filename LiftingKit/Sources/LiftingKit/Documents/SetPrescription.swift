import Foundation

/// What one set is meant to be: its reps, its load, how hard it should feel,
/// and anything to say about it.
///
/// **What it does.** Lets a prescription say that one set differs from the
/// next — a drop set, a ramp, a back-off set, a last set taken to failure. Every
/// field is optional and `nil` means *this set did not state it*, which is not
/// the same as stating nothing: an exercise states a prescription for its sets,
/// and a set that adds nothing of its own is prescribed exactly that.
///
/// **How it is used.** Three places share this one type, so the vocabulary
/// cannot drift: a `PlanDocumentExercise` lists them when its sets differ, the
/// app stores them, and `SnapshotPlannedExercise` reports every set back in
/// full. Read `PlanDocumentExercise.prescribedSets` rather than these raw
/// values when you want what a set actually prescribes — that is where a set's
/// own statements and the exercise's are put together, by `everySet(...)`
/// below.
///
/// **What it depends on.** `Mass`, `IntensityTarget`, `DocumentRefusal`. It
/// judges nothing: a load is not turned into an intensity, an intensity is not
/// turned into a load, and no absent value is filled with a number the app
/// chose.
public struct SetPrescription: Codable, Hashable, Sendable {

    /// This set's rep target as written — `"5"`, `"8-12"`, `"AMRAP"`. `nil`
    /// when the set did not state one of its own.
    public let repRange: String?
    /// The load for this set, in the unit it was written in. `nil` when the set
    /// did not state one of its own.
    public let suggestedLoad: Mass?
    /// How hard this set is meant to be. `nil` when the set did not state a
    /// target of its own — never a zero, and never inferred from the load.
    public let intensity: IntensityTarget?
    /// Anything about this set in particular, such as "last set AMRAP". `nil`
    /// when there is none. An exercise's own note stays on the exercise; a set
    /// never inherits it, because a note about the movement is not a note about
    /// one set of it.
    public let notes: String?

    public init(
        repRange: String? = nil, suggestedLoad: Mass? = nil,
        intensity: IntensityTarget? = nil, notes: String? = nil
    ) {
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.intensity = intensity
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case repRange, suggestedLoad, intensity, notes
    }

    /// Nothing is required: `{}` is a legitimate set, meaning "the same as this
    /// exercise prescribes". A key this format does not have is refused with
    /// the key named, as everywhere else in this format.
    public init(from decoder: any Decoder) throws {
        try decoder.refuseUnknownKeys(besides: Set(CodingKeys.allCases.map(\.stringValue)))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repRange = try container.decodeIfPresent(String.self, forKey: .repRange)
        suggestedLoad = try container.decodeIfPresent(Mass.self, forKey: .suggestedLoad)
        intensity = try container.decodeIfPresent(IntensityTarget.self, forKey: .intensity)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

extension SetPrescription {

    /// Every set an exercise prescribes, each stated in full and in order.
    ///
    /// Two shapes reach this, and they answer the same question. When the
    /// exercise prescribed the same work throughout, `stated` is empty and
    /// `count` sets are returned, all carrying the exercise's own reps, load and
    /// intensity. When the exercise listed its sets one at a time, each listed
    /// set is returned with anything it did not state taken from the exercise's.
    ///
    /// **That fallback is reading the plan, not filling a gap.** An exercise
    /// that says `repRange: "5"` and then lists three loads has stated the reps
    /// for all three sets; making the writer repeat `"5"` three times is a tax
    /// on every plan, and a format that is tedious to write gets written badly.
    /// Nothing is ever supplied that the plan did not state somewhere: an
    /// unstated rep range stays `nil`, an unstated load stays `nil`, and an
    /// unstated intensity stays `nil`.
    ///
    /// A `count` of zero or less prescribes no sets. The count itself is
    /// recorded wherever it came from exactly as written — this only declines to
    /// build sets that were never asked for.
    public static func everySet(
        stated: [SetPrescription],
        count: Int,
        repRange: String,
        suggestedLoad: Mass?,
        intensity: IntensityTarget?
    ) -> [SetPrescription] {
        let shared = SetPrescription(
            // An empty rep range is how this format has always said "none was
            // prescribed"; it stays an absence here rather than becoming a
            // target of no reps.
            repRange: repRange.isEmpty ? nil : repRange,
            suggestedLoad: suggestedLoad,
            intensity: intensity
        )
        guard !stated.isEmpty else {
            return count > 0 ? Array(repeating: shared, count: count) : []
        }
        return stated.map { $0.completed(by: shared) }
    }

    /// This set with whatever it did not state taken from `shared`. Its own
    /// note is kept and never replaced: a note belongs to the set that wrote it.
    private func completed(by shared: SetPrescription) -> SetPrescription {
        SetPrescription(
            repRange: repRange ?? shared.repRange,
            suggestedLoad: suggestedLoad ?? shared.suggestedLoad,
            intensity: intensity ?? shared.intensity,
            notes: notes
        )
    }
}
