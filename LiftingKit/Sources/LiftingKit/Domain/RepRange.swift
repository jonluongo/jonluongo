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
/// **A target that is not counted in repetitions is refused, not converted.**
/// `"30 seconds"` names a hold, `"40 m"` names a carry, `"1:30"` names a clock;
/// none of them names thirty, forty or ninety repetitions. Reading a number out
/// of them produced a rep count nobody prescribed — a plank recorded as 30 reps,
/// counted as 30 reps by every volume report that followed. This type cannot
/// represent a duration or a distance, so it says so: no bounds, and `isEmpty`.
/// Nothing is lost by that, because a prescription carries its rep target as the
/// free text it was written in and reports it back unaltered; only this type's
/// claim to have parsed reps out of it is withdrawn. A hold is read by
/// `WorkDuration`, which is this type's mirror and logs into a set's
/// `durationSeconds` rather than its reps.
///
/// Text that names no target at all (`""`, `"AMRAP"`) is the same answer: both
/// bounds are 0 and `isEmpty` is true, so a caller can tell "there is no rep
/// count here" apart from "the target really is zero reps".
///
/// Used by `PerformanceHistory` to seed a set's rep count from the plan's
/// prescription, and by the active-workout views to prefill new sets.
///
/// Depends on: Foundation only.
public struct RepRange: Codable, Hashable, Sendable, CustomStringConvertible {

    /// The smaller of the two bounds found in the source text (0 if none were found).
    public let lowerBound: Int

    /// The larger of the two bounds found in the source text (0 if none were found).
    public let upperBound: Int

    /// True when no rep count could be read out of the source text — because it
    /// held no digits, or because the digits it held were counting something
    /// other than repetitions. Either way there is no rep target here, which is
    /// not the same as a target of zero reps.
    public let isEmpty: Bool

    /// Parses free text into bounds. See the type doc for the parsing rules.
    public init(_ text: String) {
        let numbers = text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }

        guard let first = numbers.first, let last = numbers.last,
              !Self.countsSomethingOtherThanReps(text)
        else {
            lowerBound = 0
            upperBound = 0
            isEmpty = true
            return
        }

        lowerBound = min(first, last)
        upperBound = max(first, last)
        isEmpty = false
    }

    /// Whether the text measures its target in some unit other than repetitions.
    ///
    /// Two tells, and both are about *language*, not about training: a unit word
    /// beside the number, or digits separated by a colon, which is a clock and
    /// never a rep range. Nothing here says how long a plank should be held or
    /// how far a carry should go — it only declines to read seconds as reps.
    ///
    /// The vocabulary is `TargetUnits`, shared with `WorkDuration`, so the type
    /// that refuses to read a hold as reps and the type that reads it as a hold
    /// cannot disagree about which words those are.
    private static func countsSomethingOtherThanReps(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter })
        if words.contains(where: { TargetUnits.nonRepWords.contains(String($0)) }) { return true }
        return text.contains(where: \.isNumber) && text.contains(TargetUnits.clockSeparator)
    }

    /// A readable form: `"8-12"` for a range, `"5"` when both bounds match,
    /// `""` when the range is empty.
    public var description: String {
        guard !isEmpty else { return "" }
        return lowerBound == upperBound ? "\(lowerBound)" : "\(lowerBound)-\(upperBound)"
    }
}
