import Foundation

/// Why loading the bundled catalog failed.
enum CatalogError: Error, LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The bundled exercise catalog '\(name)' is missing from the app bundle."
        }
    }
}

/// Criteria for narrowing the catalog.
///
/// An empty set means "no constraint on this axis", so
/// `ExerciseFilter()` matches everything. Depends on: the taxonomies.
struct ExerciseFilter: Hashable, Sendable {
    var equipment: Set<EquipmentType>
    var patterns: Set<MovementPattern>
    var muscles: Set<MuscleGroup>
    var categories: Set<ExerciseCategory>
    var mechanics: Set<Mechanic>

    init(
        equipment: Set<EquipmentType> = [],
        patterns: Set<MovementPattern> = [],
        muscles: Set<MuscleGroup> = [],
        categories: Set<ExerciseCategory> = [],
        mechanics: Set<Mechanic> = []
    ) {
        self.equipment = equipment
        self.patterns = patterns
        self.muscles = muscles
        self.categories = categories
        self.mechanics = mechanics
    }

    func matches(_ exercise: Exercise) -> Bool {
        if !equipment.isEmpty, !equipment.contains(exercise.equipment) { return false }
        if !patterns.isEmpty, !patterns.contains(exercise.pattern) { return false }
        if !categories.isEmpty, !categories.contains(exercise.category) { return false }
        if !mechanics.isEmpty {
            guard let mechanic = exercise.mechanic, mechanics.contains(mechanic) else { return false }
        }
        if !muscles.isEmpty, muscles.isDisjoint(with: Set(exercise.primaryMuscles)) { return false }
        return true
    }
}

/// Read access to the exercise catalog.
///
/// Depend on this rather than `ExerciseCatalog` so tests and previews can
/// supply a small fixture instead of loading 412 bundled entries.
protocol ExerciseCatalogProviding: Sendable {
    var all: [Exercise] { get }
    func exercise(id: ExerciseID) -> Exercise?
    func search(_ query: String, limit: Int) -> [Exercise]
    func exercises(matching filter: ExerciseFilter) -> [Exercise]
    func substitutes(for id: ExerciseID, limit: Int) -> [Exercise]
}

/// The bundled catalog of exercises, held in memory.
///
/// Build one with `bundled()` at app start and pass it down, or with
/// `init(exercises:)` in tests. This is immutable reference data — it ships
/// with the app and is never written at runtime, which is why it is not a
/// SwiftData model.
///
/// Depends on: `Exercise` and the taxonomies. No persistence, no UI.
struct ExerciseCatalog: ExerciseCatalogProviding {

    let all: [Exercise]
    private let byID: [ExerciseID: Exercise]

    init(exercises: [Exercise]) {
        self.all = exercises.sorted { $0.displayName < $1.displayName }
        self.byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Loads `exercises.json` from the app bundle.
    ///
    /// Throws `CatalogError.resourceMissing` if the resource is absent, and a
    /// `DecodingError` if it is malformed. Both are programmer errors that must
    /// fail loudly rather than yield a silently empty catalog.
    static func bundled(bundle: Bundle = .main) throws -> ExerciseCatalog {
        guard let url = bundle.url(forResource: "exercises", withExtension: "json") else {
            throw CatalogError.resourceMissing("exercises.json")
        }
        let data = try Data(contentsOf: url)
        return ExerciseCatalog(exercises: try JSONDecoder().decode([Exercise].self, from: data))
    }

    func exercise(id: ExerciseID) -> Exercise? { byID[id] }

    /// Case-insensitive match on display name and aliases, ranked so that
    /// names beginning with the query come first.
    func search(_ query: String, limit: Int) -> [Exercise] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Array(all.prefix(limit)) }
        return all
            .filter { $0.searchText.contains(needle) }
            .sorted { lhs, rhs in
                let lhsLeads = lhs.displayName.lowercased().hasPrefix(needle)
                let rhsLeads = rhs.displayName.lowercased().hasPrefix(needle)
                if lhsLeads != rhsLeads { return lhsLeads }
                return lhs.displayName < rhs.displayName
            }
            .prefix(limit)
            .map { $0 }
    }

    func exercises(matching filter: ExerciseFilter) -> [Exercise] {
        all.filter(filter.matches)
    }

    /// Other exercises training the same pattern, closest first — those sharing
    /// primary muscles rank above those that merely share the pattern.
    func substitutes(for id: ExerciseID, limit: Int) -> [Exercise] {
        guard let original = byID[id] else { return [] }
        let originalMuscles = Set(original.primaryMuscles)
        return all
            .filter { $0.id != id && $0.pattern == original.pattern }
            .sorted { lhs, rhs in
                let lhsShared = originalMuscles.intersection(lhs.primaryMuscles).count
                let rhsShared = originalMuscles.intersection(rhs.primaryMuscles).count
                if lhsShared != rhsShared { return lhsShared > rhsShared }
                return lhs.displayName < rhs.displayName
            }
            .prefix(limit)
            .map { $0 }
    }
}
