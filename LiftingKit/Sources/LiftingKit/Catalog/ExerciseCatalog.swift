import Foundation

/// Why loading a piece of bundled reference data failed — the exercise
/// catalog, the assembly rules, or anything else this package ships.
///
/// Thrown by `ExerciseCatalog.bundled()`. Public so a client can tell a missing
/// resource apart from a malformed one (which arrives as a `DecodingError`)
/// rather than having to match on a message. Depends on: Foundation only.
public enum CatalogError: Error, LocalizedError {
    case resourceMissing(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            "The bundled reference data '\(name)' is missing from the LiftingKit bundle."
        }
    }
}

/// Criteria for narrowing the catalog.
///
/// An empty set means "no constraint on this axis", so
/// `ExerciseFilter()` matches everything. Depends on: the taxonomies.
public struct ExerciseFilter: Hashable, Sendable {
    public var equipment: Set<EquipmentType>
    public var patterns: Set<MovementPattern>
    public var muscles: Set<MuscleGroup>
    public var categories: Set<ExerciseCategory>
    public var mechanics: Set<Mechanic>

    public init(
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

    public func matches(_ exercise: Exercise) -> Bool {
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
///
/// `version` is part of the seam deliberately: a service that selects
/// exercises must be able to record which generation of the data it selected
/// from (see `TrainingPlan.catalogVersion`), and a fake must be able to vary
/// that number. Depends on: `Exercise`, `ExerciseID`, `ExerciseFilter`.
public protocol ExerciseCatalogProviding: Sendable {
    /// Which generation of `exercises.json` this catalog came from.
    var version: Int { get }
    var all: [Exercise] { get }
    func exercise(id: ExerciseID) -> Exercise?
    func search(_ query: String, limit: Int) -> [Exercise]
    func exercises(matching filter: ExerciseFilter) -> [Exercise]
    func substitutes(for id: ExerciseID, limit: Int) -> [Exercise]
}

/// The on-disk shape of `exercises.json`: a version stamp alongside the
/// exercise list, so a decoded catalog can always say which generation of
/// data it came from.
///
/// Depends on: `Exercise`. Written by `Tools/build-catalog.py`, read only by
/// `ExerciseCatalog.bundled()` — nothing else should decode this file
/// directly, or the version stamp is easy to bypass.
private struct CatalogFile: Decodable {
    var version: Int
    var exercises: [Exercise]
}

/// The bundled catalog of exercises, held in memory.
///
/// Build one with `bundled()` at launch and pass it down, or with
/// `init(exercises:)` for an empty or fixture catalog. This is immutable
/// reference data — it ships inside this package and is never written at
/// runtime, which is why it is not a SwiftData model.
///
/// `version` identifies which generation of `exercises.json` produced this
/// catalog. `TrainingPlan.catalogVersion` stamps a plan with the version that
/// built it, so a later correction to the data (e.g. reclassifying an
/// exercise's muscles) can be detected against plans and logged sets built
/// under an older version instead of silently changing what they mean.
///
/// Depends on: `Exercise` and the taxonomies. No persistence, no UI.
public struct ExerciseCatalog: ExerciseCatalogProviding {

    public let all: [Exercise]
    public let version: Int
    private let byID: [ExerciseID: Exercise]

    /// Builds an in-memory catalog directly from exercises, bypassing
    /// `exercises.json`. Used by tests and previews that need a small
    /// fixture; `version` defaults to 1 since those callers rarely care
    /// which version they're pinned to.
    public init(exercises: [Exercise], version: Int = 1) {
        self.all = exercises.sorted { $0.displayName < $1.displayName }
        self.version = version
        self.byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Loads `exercises.json` from this package's resource bundle.
    ///
    /// The file ships inside `LiftingKit`, not inside any client, so it
    /// resolves through `Bundle.module` and is found identically from the iOS
    /// app and from a macOS command-line tool. There is deliberately no bundle
    /// parameter: the resource has exactly one home.
    ///
    /// Throws `CatalogError.resourceMissing` if the resource is absent, and a
    /// `DecodingError` if it is malformed. Both are build defects that must
    /// fail loudly rather than yield a silently empty catalog.
    public static func bundled() throws -> ExerciseCatalog {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw CatalogError.resourceMissing("exercises.json")
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        return ExerciseCatalog(exercises: file.exercises, version: file.version)
    }

    public func exercise(id: ExerciseID) -> Exercise? { byID[id] }

    /// Case-insensitive match on display name and aliases, ranked so that
    /// names beginning with the query come first.
    public func search(_ query: String, limit: Int) -> [Exercise] {
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

    public func exercises(matching filter: ExerciseFilter) -> [Exercise] {
        all.filter(filter.matches)
    }

    /// Other exercises training the same pattern, closest first — those sharing
    /// primary muscles rank above those that merely share the pattern.
    public func substitutes(for id: ExerciseID, limit: Int) -> [Exercise] {
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
