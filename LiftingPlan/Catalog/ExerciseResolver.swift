import Foundation

/// How confidently a piece of text was matched to a catalog entry.
///
/// Ordered loosely from most to least certain. Callers that care about
/// precision — persisting a generated plan, say — can require `.exact` or
/// `.alias` and treat the rest as a prompt to ask the lifter.
enum MatchConfidence: Hashable, Sendable {
    case exact
    case alias
    case normalized
    /// Similarity in 0...1 from the normalized-token comparison.
    case fuzzy(Double)
    /// No name matched; an exercise was chosen from the fallback filter.
    case fallback
}

/// A catalog entry chosen for a piece of free text.
struct ResolvedExercise: Hashable, Sendable {
    let id: ExerciseID
    let confidence: MatchConfidence
}

/// Maps free text onto a real catalog entry.
///
/// This is the guard that keeps invented exercises out of the database. The
/// on-device model is free to name a movement however it likes; every name it
/// produces passes through here, and anything that cannot be resolved is
/// either replaced from a fallback filter or rejected. **A name that does not
/// resolve is never persisted.**
///
/// Construct one with any `ExerciseCatalogProviding` and reuse it — the
/// normalized index is built once at initialization.
///
/// Depends on: `ExerciseCatalogProviding` and Foundation.
struct ExerciseResolver: Sendable {

    /// Below this similarity a fuzzy match is considered wrong. Chosen so that
    /// single-character typos resolve while different exercises do not.
    static let fuzzyThreshold = 0.82

    private let catalog: any ExerciseCatalogProviding
    private let byExactName: [String: ExerciseID]
    private let byAlias: [String: ExerciseID]
    private let byNormalized: [String: ExerciseID]

    init(catalog: any ExerciseCatalogProviding) {
        self.catalog = catalog

        var exact: [String: ExerciseID] = [:]
        var aliases: [String: ExerciseID] = [:]
        var normalized: [String: ExerciseID] = [:]

        for exercise in catalog.all {
            exact[exercise.displayName.lowercased()] = exercise.id
            exact[exercise.id.rawValue] = exercise.id
            for alias in exercise.aliases {
                aliases[alias.lowercased()] = exercise.id
            }
            normalized[Self.normalize(exercise.displayName)] = exercise.id
            normalized[Self.normalize(exercise.id.rawValue)] = exercise.id
        }

        self.byExactName = exact
        self.byAlias = aliases
        self.byNormalized = normalized
    }

    /// Lowercased, punctuation stripped, tokens sorted — so "Bench Press
    /// (Barbell)" and "barbell bench press" collapse to one key.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "&", with: " and ")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").sorted().joined(separator: " ")
    }

    /// Resolves text to a catalog entry, or `nil` if nothing matches well enough.
    func resolve(_ text: String) -> ResolvedExercise? {
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

        var best: (id: ExerciseID, score: Double)?
        for (candidate, id) in byNormalized {
            let score = Self.similarity(key, candidate)
            if score > (best?.score ?? 0) {
                best = (id, score)
            }
        }
        guard let best, best.score >= Self.fuzzyThreshold else { return nil }
        return ResolvedExercise(id: best.id, confidence: .fuzzy(best.score))
    }

    /// Resolves text, and when nothing matches, substitutes the first exercise
    /// satisfying `fallback`. Returns `nil` only when the fallback itself
    /// matches nothing — an exercise is never invented.
    func resolve(_ text: String, fallback: ExerciseFilter) -> ResolvedExercise? {
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
