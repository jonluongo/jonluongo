import Foundation

/// What one prescribed set asks for: a count, a hold, or a carry.
///
/// **What it does.** Holds a prescribed target as the thing it is, read once,
/// rather than as text that every reader must scan again. A set is counted,
/// held, or carried, and no two of them are the same number — the record side
/// has carried `reps`, `durationSeconds` and `distance` as separate fields for
/// exactly that reason. This is the prescription side gaining the same
/// guarantee: a forty-metre sled push was stored as the string `"40m"` in a
/// field named `repRange`, and `TargetUnits` ran on every read to find out what
/// it meant.
///
/// **How it is used.** A plan document decodes one per prescribed set, from
/// either the typed form or the shorthand a coach writes; `measure` gives the
/// single answer everything downstream binds to; `shorthand` writes it back the
/// way it was written. Nothing between those two points parses anything.
///
/// **What it depends on.** `WorkMeasure` for the answer it reports,
/// `TargetUnits` through `RepRange`, `WorkDuration` and `WorkDistance` for the
/// one-time parse, and `DistanceUnit`, which travels inside the case because
/// forty metres and forty yards are different work and nothing here converts
/// one into the other.
///
/// **A target it cannot read is refused**, with the text quoted, rather than
/// kept as prose to be interpreted later. That is the difference between a
/// target and a note: a note is for the lifter to read, a target is for the app
/// to act on, and something the app cannot act on must not be stored where it
/// will be acted on anyway.
public enum Target: Hashable, Sendable {

    /// Counted. `high` is `nil` for a single count: `5` and `5-5` are the same
    /// instruction, and storing the second puts a bound in the record that
    /// nobody stated.
    case repetitions(low: Int, high: Int?)

    /// Counted, with no number: as many as the lifter can manage. Still
    /// `.repetitions` as a measure, and still logged in `reps` — this says what
    /// was asked for, not what it is measured in.
    case repetitionsToFailure

    /// Held, in seconds.
    case time(low: Int, high: Int?)

    /// Carried, over the unit it was prescribed in.
    case distance(low: Double, high: Double?, unit: DistanceUnit)

    /// Which of the three things a set can be measured in this target names.
    public var measure: WorkMeasure {
        switch self {
        case .repetitions, .repetitionsToFailure: .repetitions
        case .time: .time
        case .distance(_, _, let unit): .distance(unit)
        }
    }
}

// MARK: - Reading what a coach wrote

extension Target {

    /// The words that name a set taken as far as it goes. They are checked
    /// before the numeric readers because none of them holds a number, and a
    /// reader looking for one would report the set as unreadable rather than as
    /// what it plainly says.
    private static let toFailureWords: Set<String> = [
        "amrap", "to failure", "failure", "max reps", "as many as possible",
    ]

    /// The only words that may sit beside a rep count. Everything else means
    /// the number is not a rep count, whatever the number looks like.
    ///
    /// **This is a whitelist, and it has to be.** `WorkDistance` reports no unit
    /// for a word it does not know, so before this, `"40furlongs"` fell through
    /// to `RepRange`, which found the 40 and reported forty repetitions — a
    /// carry landing in the rep column, which is the exact defect `WorkMeasure`
    /// exists to prevent, and which then propagates into every volume total the
    /// coach reads. A coach who states a unit this build has never heard of gets
    /// a refusal naming it, not a number nobody performed.
    private static let repWords: Set<String> = [
        "rep", "reps", "repetition", "repetitions", "x",
    ]

    /// Reads a target from the shorthand a coach writes — `"8-12"`, `"45s"`,
    /// `"40m"`, `"AMRAP"` — or refuses it.
    ///
    /// The readers are asked in a fixed order, the same one `WorkMeasure` uses,
    /// so no target is ever claimed by two of them.
    public init?(shorthand text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if Self.toFailureWords.contains(trimmed.lowercased()) {
            self = .repetitionsToFailure
            return
        }

        let duration = WorkDuration(trimmed)
        if duration.isTimed, !duration.isEmpty {
            self = .time(
                low: duration.lowerSeconds,
                high: Self.upper(duration.upperSeconds, over: duration.lowerSeconds))
            return
        }

        let carry = WorkDistance(trimmed)
        if let unit = carry.unit, !carry.isEmpty {
            self = .distance(
                low: carry.lowerValue,
                high: Self.upper(carry.upperValue, over: carry.lowerValue),
                unit: unit)
            return
        }

        let words = trimmed.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard words.allSatisfy(Self.repWords.contains) else { return nil }

        let reps = RepRange(trimmed)
        guard !reps.isEmpty else { return nil }
        self = .repetitions(
            low: reps.lowerBound,
            high: Self.upper(reps.upperBound, over: reps.lowerBound))
    }

    /// An upper bound only when there is one. The readers report a single value
    /// as a range whose ends match; this is where that stops being carried.
    private static func upper<Value: Comparable>(_ upper: Value, over lower: Value) -> Value? {
        upper > lower ? upper : nil
    }
}

// MARK: - Writing it back

extension Target: CustomStringConvertible {

    /// The target as a coach would write it: `"8-12"`, `"5"`, `"AMRAP"`,
    /// `"30-45s"`, `"40m"`. What a screen draws and what a report states.
    public var shorthand: String {
        switch self {
        case .repetitions(let low, let high):
            Self.span("\(low)", high.map(String.init))
        case .repetitionsToFailure:
            "AMRAP"
        case .time(let low, let high):
            Self.span("\(low)", high.map(String.init)) + "s"
        case .distance(let low, let high, let unit):
            Self.span(Self.number(low), high.map(Self.number)) + unit.rawValue
        }
    }

    public var description: String { shorthand }

    private static func span(_ low: String, _ high: String?) -> String {
        guard let high else { return low }
        return "\(low)-\(high)"
    }

    /// A carry's distance as it was written: `40`, not `40.0`, and `2.5` kept.
    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }
}

// MARK: - The wire

extension Target: Codable {

    private enum CodingKeys: String, CodingKey { case measure, low, high, unit }

    /// The name each case is written under. Spelled out rather than derived,
    /// because these are format, and a case renamed in Swift must not silently
    /// change what a document says.
    private enum Written: String {
        case reps
        case repsToFailure
        case seconds
        case distance
    }

    /// Decodes the typed form, or the shorthand a coach may have written.
    ///
    /// **Shorthand is read here and nowhere else.** That is what "parsed once
    /// at the boundary" means in practice: a hand-written plan works, the
    /// server's own documents work, and what the store holds is typed either
    /// way, so nothing downstream can reach a different conclusion about the
    /// same target.
    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
            let text = try? single.decode(String.self) {
            guard let parsed = Target(shorthand: text) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: """
                            Target "\(text)" could not be read. State a count \
                            (\"8-12\", \"5\"), a hold (\"45s\"), a carry \
                            (\"40m\"), or \"AMRAP\".
                            """))
            }
            self = parsed
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stated = try container.decode(String.self, forKey: .measure)
        guard let measure = Written(rawValue: stated) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: """
                        Target measure "\(stated)" is not one this format has. \
                        It states reps, repsToFailure, seconds or distance.
                        """))
        }

        switch measure {
        case .reps:
            self = .repetitions(
                low: try container.decode(Int.self, forKey: .low),
                high: try container.decodeIfPresent(Int.self, forKey: .high))
        case .repsToFailure:
            self = .repetitionsToFailure
        case .seconds:
            self = .time(
                low: try container.decode(Int.self, forKey: .low),
                high: try container.decodeIfPresent(Int.self, forKey: .high))
        case .distance:
            self = .distance(
                low: try container.decode(Double.self, forKey: .low),
                high: try container.decodeIfPresent(Double.self, forKey: .high),
                unit: DistanceUnit(
                    rawValue: try container.decode(String.self, forKey: .unit)))
        }
    }

    /// Always the typed form. Shorthand is something this reads, never
    /// something it writes: a document it produced must not need parsing.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .repetitions(let low, let high):
            try container.encode(Written.reps.rawValue, forKey: .measure)
            try container.encode(low, forKey: .low)
            try container.encodeIfPresent(high, forKey: .high)
        case .repetitionsToFailure:
            try container.encode(Written.repsToFailure.rawValue, forKey: .measure)
        case .time(let low, let high):
            try container.encode(Written.seconds.rawValue, forKey: .measure)
            try container.encode(low, forKey: .low)
            try container.encodeIfPresent(high, forKey: .high)
        case .distance(let low, let high, let unit):
            try container.encode(Written.distance.rawValue, forKey: .measure)
            try container.encode(low, forKey: .low)
            try container.encodeIfPresent(high, forKey: .high)
            try container.encode(unit.rawValue, forKey: .unit)
        }
    }
}
