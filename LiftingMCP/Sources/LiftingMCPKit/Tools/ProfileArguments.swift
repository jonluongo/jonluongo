import Foundation
import LiftingKit

// How `update_profile`'s arguments become a `ProfileUpdate`.
//
// Kept apart from the tool itself because it is a different job: the tool
// decides what to write and reports it, this decides what a caller meant. The
// whole file exists to preserve one distinction — a key that is absent, a key
// that is `null`, and a key with a value are three different instructions, and
// everything else in this server is free to collapse the first two.

extension ToolRunner {

    /// Turns the call's arguments into the document, or throws the sentence
    /// that says why it could not.
    ///
    /// The document's identity and timestamp are supplied here rather than
    /// asked for: they are facts about the write, and this is the code that
    /// knows them. `id` is fresh on every call, so an update written after one
    /// that has already been applied is applied in its turn rather than
    /// mistaken for it.
    func makeUpdate(from arguments: JSONValue) throws -> ProfileUpdate {
        try Self.refuseUnknownFacts(in: arguments)
        return ProfileUpdate(
            id: UUID(),
            generatedAt: now(),
            displayUnit: try Self.stated(arguments, "displayUnit", Self.massUnit),
            experience: try Self.stated(arguments, "experience", Self.experience),
            equipment: try Self.stated(arguments, "equipment", Self.equipmentOwned),
            goal: try Self.stated(arguments, "goal", { try Self.text($0, "goal") }),
            constraints: try Self.stated(
                arguments, "constraints", { try Self.text($0, "constraints") }),
            avoidedPatterns: try Self.stated(arguments, "avoidedPatterns", patterns),
            avoidedExercises: try Self.stated(arguments, "avoidedExercises", exercises),
            preferredWeekdays: try Self.stated(arguments, "preferredWeekdays", Self.weekdays),
            preferredDurationMinutes: try Self.stated(
                arguments, "preferredDurationMinutes",
                { try Self.wholeNumber($0, "preferredDurationMinutes") }),
            bodyweight: try Self.readings(arguments["bodyweight"]),
            baselines: try baselines(arguments["baselines"])
        )
    }

    /// Throws when the call names a fact this document cannot hold.
    ///
    /// Refused rather than dropped, and refused before anything is written: a
    /// key quietly ignored here is reported back as "Recorded" while the fact
    /// is written down nowhere, which is the failure a caller cannot detect and
    /// therefore cannot correct. The facts it can hold come from the document
    /// itself, so a field added there is not one this keeps rejecting.
    ///
    /// Keys are checked in sorted order, so the same call always names the same
    /// key rather than a different one each time.
    private static func refuseUnknownFacts(in arguments: JSONValue) throws {
        let unknown = (arguments.objectValue ?? [:]).keys.sorted()
            .first { !ProfileUpdate.statedKeys.contains($0) }
        guard let unknown else { return }
        throw ProfileArgumentError(
            "'\(unknown)' is not a fact this profile can record, so it would have been dropped "
                + "without anyone noticing. Nothing was written. What it records is: "
                + "\(ProfileUpdate.statedKeys.sorted().joined(separator: ", ")). Anything else "
                + "the lifter has told you can go in 'constraints' or 'goal', in his words.")
    }

    /// The three-way read the whole design rests on: a key that is not there
    /// means "leave it alone", a key that is `null` means "this is no longer
    /// known", and anything else is a stated value.
    ///
    /// It reads the object directly rather than through `JSONValue`'s
    /// subscript, which answers `nil` for an explicit `null` — convenient
    /// everywhere else in this server, and exactly the distinction that must
    /// survive here.
    private static func stated<Value>(
        _ arguments: JSONValue, _ key: String, _ parse: (JSONValue) throws -> Value
    ) rethrows -> StatedValue<Value> {
        guard let raw = arguments.objectValue?[key] else { return .unchanged }
        guard raw != .null else { return .unstated }
        return .stated(try parse(raw))
    }

    static func text(_ value: JSONValue, _ key: String) throws -> String {
        guard let text = value.stringValue else {
            throw ProfileArgumentError(
                "'\(key)' has to be text, in the lifter's own words. Nothing was written.")
        }
        return text
    }

    static func wholeNumber(_ value: JSONValue, _ key: String) throws -> Int {
        guard let number = value.intValue else {
            throw ProfileArgumentError(
                "'\(key)' has to be a whole number. Nothing was written.")
        }
        return number
    }

    private static func massUnit(_ value: JSONValue) throws -> MassUnit {
        guard let unit = MassUnit.named(try text(value, "displayUnit")) else {
            throw ProfileArgumentError(
                "'displayUnit' has to be 'lb' or 'kg'. Nothing was written.")
        }
        return unit
    }

    private static func experience(_ value: JSONValue) throws -> ExperienceLevel {
        guard let level = ExperienceLevel.named(try text(value, "experience")) else {
            throw ProfileArgumentError(
                "'experience' has to be one of \(Self.listed(ExperienceLevel.allCases)). "
                    + "Nothing was written.")
        }
        return level
    }

    private static func weekdays(_ value: JSONValue) throws -> [Weekday] {
        try Self.list(value, "preferredWeekdays").map { entry in
            if let number = entry.intValue, let weekday = Weekday(rawValue: number) {
                return weekday
            }
            guard let weekday = entry.stringValue.flatMap(Weekday.named) else {
                throw ProfileArgumentError(
                    "'\(entry.stringValue ?? "that value")' is not a weekday. Write a name such "
                        + "as 'monday', or Calendar's numbering where 1 is Sunday and 7 is "
                        + "Saturday. Nothing was written.")
            }
            return weekday
        }
    }

    /// Avoided patterns, checked against the patterns the catalog actually
    /// uses. An invented one would be stored as a filter that excludes nothing.
    private func patterns(_ value: JSONValue) throws -> [MovementPattern] {
        let known = Set(catalog.all.map(\.pattern))
        return try Self.list(value, "avoidedPatterns").map { entry in
            let pattern = MovementPattern(rawValue: try Self.text(entry, "avoidedPatterns"))
            guard known.contains(pattern) else {
                throw ProfileArgumentError(
                    "'\(pattern.rawValue)' is not a movement pattern this catalog uses, so "
                        + "avoiding it would exclude nothing. The patterns in use are "
                        + "\(known.map(\.rawValue).sorted().joined(separator: ", ")). Nothing "
                        + "was written.")
            }
            return pattern
        }
    }

    /// Avoided exercises, checked against the catalog for the same reason
    /// `write_plan` checks a prescription: an ID the catalog does not have is
    /// not a lift, and storing one would read as a rule that is quietly doing
    /// nothing.
    private func exercises(_ value: JSONValue) throws -> [ExerciseID] {
        try Self.list(value, "avoidedExercises").map { entry in
            let id = ExerciseID(rawValue: try Self.text(entry, "avoidedExercises"))
            guard catalog.exercise(id: id) != nil else {
                throw ProfileArgumentError(
                    "'\(id.rawValue)' is not in the exercise catalog (version "
                        + "\(catalog.version)), so avoiding it would exclude nothing. Find the "
                        + "real ID with \(ToolCatalog.listExercises). Nothing was written.")
            }
            return id
        }
    }

    /// A list, tolerating a bare value in place of a one-element array — the
    /// same latitude `list_exercises` gives its filters.
    static func list(_ value: JSONValue, _ key: String) throws -> [JSONValue] {
        if case .array(let entries) = value { return entries }
        if case .object = value {
            throw ProfileArgumentError("'\(key)' has to be a list. Nothing was written.")
        }
        return [value]
    }

    private static func listed(_ values: [some RawRepresentable<String>]) -> String {
        values.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }

}

/// Why a profile update could not be read, as a sentence the caller can act on.
///
/// Thrown while the arguments are being read and turned straight back into a
/// tool failure, so a bad field never reaches the file. It carries a message
/// rather than a case per field because there is nothing to switch on: the only
/// consumer is the caller reading the sentence.
struct ProfileArgumentError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

extension MassUnit {

    /// The unit a caller named, however he wrote it.
    ///
    /// Lives here rather than on `MassUnit` in `LiftingKit` for the same reason
    /// `Weekday.named` does: it exists to accept a value written in prose at the
    /// MCP boundary, and the shared type keeps exactly one way to decode.
    static func named(_ name: String) -> MassUnit? {
        switch ProfileNaming.normalized(name) {
        case "lb", "lbs", "pound", "pounds": .pounds
        case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms": .kilograms
        default: nil
        }
    }
}

extension Equipment {

    /// The access tier a caller named, ignoring case, spacing and punctuation
    /// so 'full_gym' and 'Full gym' are the same answer.
    static func named(_ name: String) -> Equipment? {
        let needle = ProfileNaming.normalized(name)
        return allCases.first { ProfileNaming.normalized($0.rawValue) == needle }
    }
}

extension ExperienceLevel {

    /// The experience level a caller named, ignoring case and punctuation.
    static func named(_ name: String) -> ExperienceLevel? {
        let needle = ProfileNaming.normalized(name)
        return allCases.first { ProfileNaming.normalized($0.rawValue) == needle }
    }
}

/// How a name written in prose is compared with a raw value.
///
/// One place, so 'Full gym', 'full gym' and 'full_gym' cannot be accepted by one
/// taxonomy and refused by the next. Depends on: Foundation only.
enum ProfileNaming {
    static func normalized(_ name: String) -> String {
        name.lowercased().filter(\.isLetter)
    }
}
