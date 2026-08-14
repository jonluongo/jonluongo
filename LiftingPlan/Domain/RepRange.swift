import Foundation

/// A prescribed rep target, parsed once from the free-text string a plan
/// stores (e.g. `"8-12"`, `"5"`, `"8 to 12"`, `"AMRAP"`).
///
/// Programs write rep targets as loose prose, not a strict grammar, so
/// parsing works by scanning for runs of digits and ignoring everything else
/// — hyphens, en dashes, the word "to", whatever separator a template author
/// used. The first digit run found becomes one bound, the last becomes the
/// other; `lowerBound` and `upperBound` are then normalized so
/// `lowerBound <= upperBound` always holds, even when the source text wrote
/// the range backwards (`"12-8"` still yields lower 8, upper 12). A single
/// number (`"5"`) is both bounds. Three or more numbers (`"5-3-1"`, an
/// unusual but seen pattern for descending drop sets) use the first digit run
/// as one bound and the last as the other — the middle numbers are ignored —
/// so `"5-3-1"` yields lower 1, upper 5.
///
/// Text with no digits at all (`""`, `"AMRAP"`) has no target: both bounds
/// are 0 and `isEmpty` is true, so a caller can tell "no target was given"
/// apart from "the target really is zero reps".
///
/// Used by `PerformanceHistory` to seed a set's rep count from the plan's
/// prescription, and by the active-workout views to prefill new sets.
///
/// Depends on: Foundation only.
struct RepRange: Codable, Hashable, Sendable, CustomStringConvertible {

    /// The smaller of the two bounds found in the source text (0 if none were found).
    let lowerBound: Int

    /// The larger of the two bounds found in the source text (0 if none were found).
    let upperBound: Int

    /// True when the source text contained no digits at all, i.e. there was
    /// no rep target to parse (as opposed to a target of literally zero reps).
    let isEmpty: Bool

    /// Parses free text into bounds. See the type doc for the parsing rules.
    init(_ text: String) {
        let numbers = text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }

        guard let first = numbers.first, let last = numbers.last else {
            lowerBound = 0
            upperBound = 0
            isEmpty = true
            return
        }

        lowerBound = min(first, last)
        upperBound = max(first, last)
        isEmpty = false
    }

    /// A readable form: `"8-12"` for a range, `"5"` when both bounds match,
    /// `""` when the range is empty.
    var description: String {
        guard !isEmpty else { return "" }
        return lowerBound == upperBound ? "\(lowerBound)" : "\(lowerBound)-\(upperBound)"
    }
}
