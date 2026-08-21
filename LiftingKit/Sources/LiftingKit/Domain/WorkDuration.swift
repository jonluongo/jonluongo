import Foundation

/// A prescribed hold, read out of the free text a plan writes its target in —
/// `"30 seconds"`, `"45s"`, `"1:30"`, `"2 min"`.
///
/// **What it does.** Answers two questions about one target string, and keeps
/// them apart: *is this work measured in time rather than repetitions*
/// (`isTimed`), and *how long does it say* (`lowerSeconds`, `upperSeconds`,
/// `seconds`). The two are separate because a target can plainly be a hold
/// without naming a number this build can resolve — `"max time hold"` and
/// `"1 min 30 s"` are both timed, and neither yields one duration.
///
/// **How it is used.** The active-workout log asks `isTimed` to decide whether
/// the row it draws records repetitions or a hold, and `seconds` for the number
/// it seeds a new row with. It is the mirror of `RepRange`: between them, a
/// prescription's target text is read as reps, as time, or as neither — and
/// never as the wrong one. The prescription itself is always shown verbatim;
/// this type only says what can be read out of it.
///
/// **What it depends on.** `TargetUnits` for the vocabulary and for the scan
/// that reads numbers against a unit — both shared with `RepRange` and
/// `WorkDistance`, so the three cannot disagree about whether `"30 seconds"`
/// counts repetitions. Foundation otherwise. It decides nothing about training:
/// no value here says how long anything should be held, only what a word means.
///
/// A duration is read only when the text is unambiguous. Two different time
/// units in one string (`"1 min 30 s"`), a distance beside the time
/// (`"40 m in 30 seconds"`), or a number with no unit at all leave the bounds
/// empty rather than guessing which number meant what — a wrong number in a
/// training log is the failure this type exists to prevent.
public struct WorkDuration: Hashable, Sendable, CustomStringConvertible {

    /// Whether the target is measured in time rather than in repetitions.
    ///
    /// True when the text names a time unit or writes a clock. This is what
    /// decides which field the user is given, so it deliberately answers for
    /// text whose number cannot be read: a hold with an unreadable duration is
    /// still a hold.
    public let isTimed: Bool

    /// The shorter of the two bounds, in whole seconds (0 when none was read).
    public let lowerSeconds: Int

    /// The longer of the two bounds, in whole seconds (0 when none was read).
    public let upperSeconds: Int

    /// True when no duration could be read out of the text — because it names
    /// no time, or because what it names cannot be resolved to a number without
    /// guessing.
    public let isEmpty: Bool

    /// The single duration this target names, or `nil` when it names a range,
    /// or none. What a new set is seeded with: a range names no one number, and
    /// picking an end of it would be the app deciding how long to hold.
    public var seconds: Int? {
        guard !isEmpty, lowerSeconds == upperSeconds else { return nil }
        return lowerSeconds
    }

    /// Reads free text. See the type doc for what is read and what is refused.
    ///
    /// A target is a hold when it speaks of time *and* `RepRange` could read no
    /// rep count out of it. That second half is what keeps the two readers from
    /// both claiming a target: `"8-12, hold at the top"` prescribes eight to
    /// twelve repetitions and says so, whatever else it mentions.
    public init(_ text: String) {
        isTimed = Self.namesTime(text) && RepRange(text).isEmpty
        guard isTimed, let stated = Self.statedSeconds(in: text), !stated.isEmpty,
            let first = stated.first, let last = stated.last, first > 0, last > 0
        else {
            lowerSeconds = 0
            upperSeconds = 0
            isEmpty = true
            return
        }
        lowerSeconds = min(first, last)
        upperSeconds = max(first, last)
        isEmpty = false
    }

    /// A readable form: `"30s"`, `"30-45s"`, or `""` when nothing was read.
    public var description: String {
        guard !isEmpty else { return "" }
        return lowerSeconds == upperSeconds
            ? "\(lowerSeconds)s" : "\(lowerSeconds)-\(upperSeconds)s"
    }

    // MARK: - Reading the text

    /// Whether the text speaks of time at all: a time unit word, a word that
    /// says the work is measured in time without naming a unit, or a clock,
    /// which is never anything else.
    private static func namesTime(_ text: String) -> Bool {
        if TargetUnits.names(Set(TargetUnits.secondsPerTimeWord.keys), in: text) { return true }
        if TargetUnits.names(TargetUnits.timingWords, in: text) { return true }
        return text.contains(where: \.isNumber) && text.contains(TargetUnits.clockSeparator)
    }

    /// Every duration the text states, in the order stated, or `nil` when they
    /// cannot all be read as times in one unit.
    private static func statedSeconds(in text: String) -> [Int]? {
        let clocks = clockDurations(in: text)
        guard clocks.isEmpty else { return clocks }
        return unitDurations(in: text)
    }

    /// The clock groups — `"1:30"` is ninety seconds, `"1:30:00"` is an hour
    /// and a half. A group this build cannot read as a clock makes the whole
    /// text unreadable rather than being skipped over.
    private static func clockDurations(in text: String) -> [Int] {
        let groups = text.split(
            whereSeparator: { !$0.isNumber && $0 != TargetUnits.clockSeparator }
        ).filter { $0.contains(TargetUnits.clockSeparator) }

        return groups.compactMap { group in
            let parts = group.split(
                separator: TargetUnits.clockSeparator, omittingEmptySubsequences: false)
            let numbers = parts.compactMap { Int($0) }
            guard numbers.count == parts.count, (2...3).contains(numbers.count) else { return nil }
            return numbers.reduce(0) { $0 * TargetUnits.secondsPerClockStep + $1 }
        }
    }

    /// Every number the text states, converted through the time unit it states
    /// them in, or `nil` when they cannot all be read against one time unit.
    ///
    /// The reading is `TargetUnits.statedQuantities(in:)`, shared with
    /// `WorkDistance`; the only thing this adds is the conversion, which is what
    /// makes time different from every other measure. Sixty seconds to a minute
    /// is arithmetic, not a prescription — and it is the reason a duration can
    /// be one number where a distance must carry its unit.
    private static func unitDurations(in text: String) -> [Int]? {
        guard let stated = TargetUnits.statedQuantities(in: text),
            let secondsPerUnit = TargetUnits.secondsPerTimeWord[stated.unit]
        else {
            // No numbers, no unit, two different units — or one measuring
            // something other than time.
            return nil
        }
        return stated.values.map { $0 * secondsPerUnit }
    }
}
