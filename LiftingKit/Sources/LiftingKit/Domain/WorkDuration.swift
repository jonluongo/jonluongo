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
/// **What it depends on.** `TargetUnits` for the vocabulary, which `RepRange`
/// shares, so the two cannot disagree about whether `"30 seconds"` counts
/// repetitions. Foundation otherwise. It decides nothing about training: no
/// value here says how long anything should be held, only what a word means.
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
    /// decides which field the lifter is given, so it deliberately answers for
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
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if words.contains(where: { TargetUnits.secondsPerTimeWord[$0] != nil }) { return true }
        if !words.isDisjoint(with: TargetUnits.timingWords) { return true }
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

    /// Every number in the text converted through the unit word that applies to
    /// it, or `nil` when any of them cannot be, or when they do not all share
    /// one unit.
    private static func unitDurations(in text: String) -> [Int]? {
        let tokens = TargetUnits.tokens(in: text)
        var units: Set<String> = []
        var durations: [Int] = []

        for (index, token) in tokens.enumerated() {
            guard case .number(let value) = token else { continue }
            guard let unit = tokens.dropFirst(index + 1).compactMap(\.unitWord).first,
                let secondsPerUnit = TargetUnits.secondsPerTimeWord[unit]
            else {
                // A number with no unit after it, or one measuring a distance.
                return nil
            }
            units.insert(unit)
            durations.append(value * secondsPerUnit)
        }
        guard units.count == 1 else { return nil }
        return durations
    }
}

/// The unit words a prescribed target may be written in, and what each one
/// measures.
///
/// One vocabulary in one place, so `RepRange` and `WorkDuration` cannot
/// disagree about whether `"30 seconds"` counts repetitions. Nothing here is a
/// training opinion: no value says what a set should be, only what a word
/// means. Time and distance both appear because timed holds and loaded carries
/// are both work the catalog already carries.
///
/// Depends on: Foundation only.
enum TargetUnits {

    /// How many seconds each time word is worth. Unit arithmetic rather than a
    /// prescription: a minute is sixty seconds by definition.
    static let secondsPerTimeWord: [String: Int] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
    ]

    /// Words that say the work is measured in time without naming a unit, so
    /// `"max hold"` and `"hold for time"` reach the lifter as holds rather than
    /// as a rep field. They are read only when no rep count could be found, so
    /// `"8-12, hold at the top"` stays eight to twelve repetitions.
    static let timingWords: Set<String> = ["hold", "holds", "time", "timed", "isometric"]

    /// Words that mean the number beside them measures distance. Read so a
    /// carry is not mistaken for a hold, and so neither is read as reps.
    static let distanceWords: Set<String> = [
        "m", "meter", "meters", "metre", "metres",
        "yd", "yds", "yard", "yards",
        "ft", "foot", "feet",
    ]

    /// Every unit word that means the number beside it is not a rep count.
    static var nonRepWords: Set<String> { Set(secondsPerTimeWord.keys).union(distanceWords) }

    /// What separates the parts of a clock, which is never a rep range.
    static let clockSeparator: Character = ":"

    /// How many of one clock part make the next one up. Calendar arithmetic.
    static let secondsPerClockStep = 60

    /// One piece of a target string: a number, a unit word, or a word that is
    /// neither.
    enum Token: Equatable {
        case number(Int)
        case unit(String)
        case word

        /// The unit this token names, or `nil` when it names none.
        var unitWord: String? {
            guard case .unit(let word) = self else { return nil }
            return word
        }
    }

    /// The text as numbers and words in the order they were written, so a
    /// number can be read together with the unit that follows it.
    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsNumber = false

        func flush() {
            guard !current.isEmpty else { return }
            if currentIsNumber {
                // A run of digits too long for an `Int` is not a target anyone
                // wrote; treating it as a plain word refuses it rather than
                // trapping.
                tokens.append(Int(current).map(Token.number) ?? .word)
            } else {
                tokens.append(nonRepWords.contains(current) ? .unit(current) : .word)
            }
            current = ""
        }

        for character in text.lowercased() {
            let isNumber = character.isNumber
            let isLetter = character.isLetter
            guard isNumber || isLetter else {
                flush()
                continue
            }
            if current.isEmpty || isNumber == currentIsNumber {
                currentIsNumber = isNumber
                current.append(character)
            } else {
                flush()
                currentIsNumber = isNumber
                current.append(character)
            }
        }
        flush()
        return tokens
    }
}
