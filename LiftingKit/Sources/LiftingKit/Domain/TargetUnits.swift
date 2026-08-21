import Foundation

/// The unit words a prescribed target may be written in, what each one measures,
/// and the one scan that reads numbers against them.
///
/// **What it does.** Holds one vocabulary in one place, so `RepRange`,
/// `WorkDuration` and `WorkDistance` cannot disagree about whether `"30
/// seconds"` counts repetitions or whether `"40 m"` does. It also does the
/// reading all three share: `statedQuantities(in:)` walks a target string and
/// answers *which unit it is written in and what numbers it states in that
/// unit*, which is the only sentence any of them needs parsed.
///
/// **How it is used.** Internally, by the three readers. Each one asks for the
/// quantities and then decides whether the unit is its own: `WorkDuration`
/// multiplies through `secondsPerTimeWord`, `WorkDistance` keeps the unit as
/// stated, and `RepRange` withdraws its claim as soon as any unit word appears
/// at all. Keeping the scan here rather than in each of them is what stops a
/// third measure from being a third copy of the same parser.
///
/// **What it depends on.** `DistanceUnit` and Foundation. Nothing here is a
/// training opinion: no value says what a set should be, only what a word means.
/// Time, distance and repetitions all appear because timed holds, loaded carries
/// and counted sets are all work the catalog already carries.
enum TargetUnits {

    /// How many seconds each time word is worth. Unit arithmetic rather than a
    /// prescription: a minute is sixty seconds by definition.
    static let secondsPerTimeWord: [String: Int] = [
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
        "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "hr": 3600, "hrs": 3600, "hour": 3600, "hours": 3600,
    ]

    /// Words that say the work is measured in time without naming a unit, so
    /// `"max hold"` and `"hold for time"` reach the user as holds rather than
    /// as a rep field. They are read only when no rep count could be found, so
    /// `"8-12, hold at the top"` stays eight to twelve repetitions.
    static let timingWords: Set<String> = ["hold", "holds", "time", "timed", "isometric"]

    /// Which unit each distance word names. Several spellings map to one unit
    /// because `"metre"`, `"meters"` and `"m"` are three ways of writing the same
    /// unit — that is canonical spelling, not conversion. No two *different*
    /// units are ever related here: there is no factor from yards to metres in
    /// this file, because nothing in this project converts a distance.
    static let distanceUnitPerWord: [String: DistanceUnit] = [
        "m": .metres, "meter": .metres, "meters": .metres,
        "metre": .metres, "metres": .metres,
        "km": .kilometres, "kilometer": .kilometres, "kilometers": .kilometres,
        "kilometre": .kilometres, "kilometres": .kilometres,
        "yd": .yards, "yds": .yards, "yard": .yards, "yards": .yards,
        "ft": .feet, "foot": .feet, "feet": .feet,
        "mi": .miles, "mile": .miles, "miles": .miles,
    ]

    /// Every unit word that means the number beside it is not a rep count.
    static var nonRepWords: Set<String> {
        Set(secondsPerTimeWord.keys).union(distanceUnitPerWord.keys)
    }

    /// What separates the parts of a clock, which is never a rep range.
    static let clockSeparator: Character = ":"

    /// How many of one clock part make the next one up. Calendar arithmetic.
    static let secondsPerClockStep = 60

    /// Whether the text names any of `words`, read as whole words so `"min"`
    /// inside `"minimal"` is not a minute.
    static func names(_ words: Set<String>, in text: String) -> Bool {
        !Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            .isDisjoint(with: words)
    }

    /// The numbers the text states and the unit it states them in, or `nil` when
    /// they cannot all be read against one unit.
    ///
    /// This is the whole of what a target string has to say about how much work
    /// it prescribes, and every reader asks it the same way. A number with no
    /// unit word after it, or two numbers written in different units
    /// (`"1 min 30 s"`, `"40 m then 20 yd"`), answers `nil` rather than guessing
    /// which number meant what — a wrong number in a training log is the failure
    /// this scan exists to prevent. The unit comes back as the word that was
    /// written, so the caller can decide whether it is one it measures in.
    static func statedQuantities(in text: String) -> (unit: String, values: [Int])? {
        let tokens = tokens(in: text)
        var units: Set<String> = []
        var values: [Int] = []

        for (index, token) in tokens.enumerated() {
            guard case .number(let value) = token else { continue }
            guard let unit = tokens.dropFirst(index + 1).compactMap(\.unitWord).first else {
                // A number with no unit after it at all.
                return nil
            }
            units.insert(unit)
            values.append(value)
        }
        guard units.count == 1, let unit = units.first, !values.isEmpty else { return nil }
        return (unit, values)
    }

    /// Every unit word the text names, in the order it names them. Read when a
    /// caller needs to know *what* is being measured even though the numbers
    /// could not be resolved.
    static func unitWords(in text: String) -> [String] {
        tokens(in: text).compactMap(\.unitWord)
    }

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
        let units = nonRepWords

        func flush() {
            guard !current.isEmpty else { return }
            if currentIsNumber {
                // A run of digits too long for an `Int` is not a target anyone
                // wrote; treating it as a plain word refuses it rather than
                // trapping.
                tokens.append(Int(current).map(Token.number) ?? .word)
            } else {
                tokens.append(units.contains(current) ? .unit(current) : .word)
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
