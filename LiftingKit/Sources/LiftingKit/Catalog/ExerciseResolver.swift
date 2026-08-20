import Foundation

/// How confidently a piece of text was matched to a catalog entry.
///
/// Ordered loosely from most to least certain. Callers that care about
/// precision — persisting a generated plan, say — can require `.exact` or
/// `.alias` and treat the rest as a prompt to ask the lifter.
public enum MatchConfidence: Hashable, Sendable {
    case exact
    case alias
    case normalized
    /// Similarity in 0...1 from the normalized-token comparison.
    case fuzzy(Double)
    /// No name matched; an exercise was chosen from the fallback filter.
    case fallback
}

/// A catalog entry chosen for a piece of free text.
///
/// Produced only by `ExerciseResolver.resolve`, which is the sole path by
/// which generated or user-typed exercise names are allowed to become a
/// concrete `ExerciseID` for persistence. Callers branch on `confidence` to
/// decide whether a resolution is trustworthy enough to save.
///
/// Depends on: `ExerciseID` and `MatchConfidence`.
public struct ResolvedExercise: Hashable, Sendable {
    public let id: ExerciseID
    public let confidence: MatchConfidence
}

/// Maps free text onto a real catalog entry.
///
/// **Nothing calls this today, and the doc comment used to claim otherwise.** It
/// said every name Claude produces passes through here. It does not: a plan
/// states `ExerciseID`s the coach picked out of the catalog with
/// `list_exercises`, and an ID the catalog does not have is refused by name —
/// by `write_plan` before the file is written and by `PlanImporter` before
/// anything is stored. Refusing beats guessing, and that refusal is what
/// actually keeps invented exercises out of the database.
///
/// **What it would be for.** Anywhere free text has to become an `ExerciseID`:
/// a search field, or `list_exercises` finding *incline dumbbell bench* when
/// the catalog calls it something else. `ExerciseCatalog.search` does that job
/// today with a substring match, which finds less.
///
/// Construct one with any `ExerciseCatalogProviding` and reuse it — the
/// normalized index is built once at initialization.
///
/// Depends on: `ExerciseCatalogProviding` and Foundation.
public struct ExerciseResolver: Sendable {

    /// Below this similarity a fuzzy match is considered wrong. Chosen so that
    /// single-character typos resolve while different exercises do not.
    static let fuzzyThreshold = 0.82

    private let catalog: any ExerciseCatalogProviding
    private let byExactName: [String: ExerciseID]
    private let byAlias: [String: ExerciseID]
    private let byNormalized: [String: ExerciseID]

    public init(catalog: any ExerciseCatalogProviding) {
        self.catalog = catalog

        var exact: [String: ExerciseID] = [:]
        var aliasCandidates: [String: Set<ExerciseID>] = [:]
        var normalizedCandidates: [String: Set<ExerciseID>] = [:]

        for exercise in catalog.all {
            exact[exercise.displayName.lowercased()] = exercise.id
            exact[exercise.id.rawValue] = exercise.id
            for alias in exercise.aliases {
                aliasCandidates[alias.lowercased(), default: []].insert(exercise.id)
            }
            normalizedCandidates[Self.normalize(exercise.displayName), default: []].insert(exercise.id)
            normalizedCandidates[Self.normalize(exercise.id.rawValue), default: []].insert(exercise.id)
        }

        self.byExactName = exact
        // A key claimed by more than one exercise is ambiguous — e.g. token
        // sorting collapses "cable-high-to-low-fly" and "cable-low-to-high-fly"
        // to the same normalized key, and two different exercises can share a
        // literal alias string. Silently keeping the last writer risks
        // resolving to the WRONG exercise at a confidence tier callers treat as
        // safe to persist. Drop both colliding entries instead: losing a
        // resolution (falling through to fuzzy or nil) is acceptable, silently
        // resolving wrong is not.
        self.byAlias = Self.droppingCollisions(aliasCandidates)
        self.byNormalized = Self.droppingCollisions(normalizedCandidates)
    }

    /// Keeps only keys claimed by exactly one id, discarding ambiguous ones.
    private static func droppingCollisions(_ candidates: [String: Set<ExerciseID>]) -> [String: ExerciseID] {
        candidates.compactMapValues { ids in ids.count == 1 ? ids.first : nil }
    }

    /// Lowercased, punctuation stripped, tokens sorted — so "Bench Press
    /// (Barbell)" and "barbell bench press" collapse to one key.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "&", with: " and ")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").sorted().joined(separator: " ")
    }

    /// Resolves text to a catalog entry, or `nil` if nothing matches well enough.
    public func resolve(_ text: String) -> ResolvedExercise? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if let id = byExactName[lowered] {
            return ResolvedExercise(id: id, confidence: .exact)
        }
        if let id = byAlias[lowered] {
            return ResolvedExercise(id: id, confidence: .alias)
        }

        let key = Self.normalize(trimmed)
        guard !key.isEmpty else { return nil }
        if let id = byNormalized[key] {
            return ResolvedExercise(id: id, confidence: .normalized)
        }

        // `byNormalized` is a Dictionary, whose iteration order is randomized
        // per process — without an explicit tie-break, a score tie (e.g. two
        // candidates equidistant from a typo) would resolve to a different
        // exercise on different launches. Break ties on the lowest
        // `id.rawValue` so the result is deterministic regardless of order.
        var best: (id: ExerciseID, score: Double)?
        for (candidate, id) in byNormalized {
            let score = Self.similarity(key, candidate)
            guard score > 0 else { continue }
            if let current = best {
                let better = score > current.score
                    || (score == current.score && id.rawValue < current.id.rawValue)
                if better {
                    best = (id, score)
                }
            } else {
                best = (id, score)
            }
        }
        guard let best, best.score >= Self.fuzzyThreshold else { return nil }
        return ResolvedExercise(id: best.id, confidence: .fuzzy(best.score))
    }

    /// Resolves text, and when nothing matches, substitutes the first exercise
    /// satisfying `fallback`. Returns `nil` only when the fallback itself
    /// matches nothing — an exercise is never invented.
    public func resolve(_ text: String, fallback: ExerciseFilter) -> ResolvedExercise? {
        if let resolved = resolve(text) { return resolved }
        guard let substitute = catalog.exercises(matching: fallback).first else { return nil }
        return ResolvedExercise(id: substitute.id, confidence: .fallback)
    }

    /// Dice coefficient over character bigrams, in 0...1.
    ///
    /// Chosen over edit distance because it tolerates word reordering and
    /// length differences, which is how generated exercise names actually
    /// differ from catalog names.
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard lhs != rhs else { return 1 }
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        let leftTotal = left.values.reduce(0, +)
        let rightTotal = right.values.reduce(0, +)
        guard leftTotal > 0, rightTotal > 0 else { return 0 }

        var shared = 0
        for (gram, leftCount) in left {
            shared += min(leftCount, right[gram] ?? 0)
        }
        return 2.0 * Double(shared) / Double(leftTotal + rightTotal)
    }

    /// Character-bigram counts, with spaces removed so word order cannot
    /// change the result.
    private static func bigrams(_ text: String) -> [String: Int] {
        let characters = Array(text.replacingOccurrences(of: " ", with: ""))
        guard characters.count > 1 else { return [:] }
        var counts: [String: Int] = [:]
        for index in 0..<(characters.count - 1) {
            counts[String(characters[index...index + 1]), default: 0] += 1
        }
        return counts
    }
}
