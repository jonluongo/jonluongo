import Foundation

/// The words a catalog actually uses to describe its exercises.
///
/// **What it does.** Reads every muscle, equipment type and movement pattern any
/// exercise in a catalog is tagged with, sorted and deduplicated.
///
/// **Why it is derived rather than listed.** The taxonomies are extensible on
/// purpose — a raw-value struct so a value this build has never heard of
/// round-trips intact instead of crashing or being dropped — which means a
/// hand-written list of "the muscles" is a second statement of something the
/// data already says, and the two drift the moment `exercises.json` gains a
/// value. This asks the catalog. A catalog that grows a muscle publishes it the
/// same day, and nothing has to be remembered.
///
/// **How it is used.** The server publishes these in `list_exercises`'s schema,
/// so the coach filters with words that exist, and refuses one that does not
/// with the real set beside it. Before this he could ask for `"quads"` and get
/// `count: 0` — indistinguishable from *no exercise trains quadriceps*, which is
/// the silent kind of wrong: he narrows, finds nothing, and concludes the
/// catalog is thin rather than that he misspelled it.
///
/// **What it depends on.** `ExerciseCatalogProviding` and the taxonomies. It
/// decides nothing and filters nothing — it reports what is there.
public struct CatalogVocabulary: Sendable {

    /// Every muscle any exercise names, primary or secondary.
    public let muscles: [MuscleGroup]
    /// Every equipment type any exercise needs.
    public let equipment: [EquipmentType]
    /// Every movement pattern any exercise is tagged with.
    public let patterns: [MovementPattern]

    public init(_ catalog: any ExerciseCatalogProviding) {
        let exercises = catalog.all
        // Secondary muscles are included: an exercise that trains the lats
        // secondarily is a real answer to *what trains lats*, and the filter
        // already matches on both.
        muscles = Self.sorted(exercises.flatMap { $0.primaryMuscles + $0.secondaryMuscles })
        equipment = Self.sorted(exercises.map(\.equipment))
        patterns = Self.sorted(exercises.map(\.pattern))
    }

    /// Deduplicated and in a stable order, because a published vocabulary that
    /// reorders between calls reads as a vocabulary that changed.
    private static func sorted<T: ExtensibleTaxonomy>(_ values: [T]) -> [T] {
        Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }
}
