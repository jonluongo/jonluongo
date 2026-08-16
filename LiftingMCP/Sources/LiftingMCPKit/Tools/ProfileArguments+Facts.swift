import Foundation
import LiftingKit

// The three facts `update_profile` reads that are not a single scalar: the open
// set of equipment the lifter owns, his bodyweight series, and his strength
// baselines.
//
// Kept apart from the rest of the argument reading because each of these has a
// shape of its own to accept, and the file that preserves the absent/null/stated
// distinction should not also be the file that knows how a weight is written.
// Nothing here decides anything about training — it turns what a caller wrote
// into what the document holds, or says why it could not.

extension ToolRunner {

    // MARK: - What he owns

    /// The equipment types a caller named, expanding any coarse tier it used as
    /// shorthand into the types that tier stands for.
    ///
    /// **A tier is a convenience, never the vocabulary.** What is recorded is
    /// the open set, because a real gym is not a tier — "barbell and bands but
    /// no rack" is what a great many people train in, and forcing that into
    /// `.fullGym` grants machine and cable work the lifter does not have while
    /// `.homeMinimal` denies him the bar he does.
    ///
    /// An equipment type this build has never heard of is recorded as stated
    /// rather than refused: it is a true fact about the lifter, and refusing the
    /// call would refuse it at the exact moment someone was writing it down. It
    /// grants no catalog movement, which is honest — nothing in the catalog
    /// requires it.
    static func equipmentOwned(_ value: JSONValue) throws -> [EquipmentType] {
        var owned: [EquipmentType] = []
        for entry in try list(value, "equipment") {
            let name = try text(entry, "equipment")
            if let tier = Equipment.named(name) {
                owned.append(
                    contentsOf: EquipmentAccess.permitted(for: tier)
                        .sorted { $0.rawValue < $1.rawValue })
            } else {
                owned.append(EquipmentType(rawValue: name))
            }
        }
        var seen: Set<EquipmentType> = []
        return owned.filter { seen.insert($0).inserted }
    }

    // MARK: - What he weighs

    /// The bodyweight readings a caller stated, or none when it stated none.
    ///
    /// Accepts one reading or several, and each written either as a bare weight
    /// (`{"value": 182, "unit": "lb"}`) or with the day it is about
    /// (`{"date": …, "value": 182, "unit": "lb"}`). A reading that names no day
    /// belongs to the day the update was written, which is when the fact was
    /// recorded rather than a guess about when he stood on the scale.
    static func readings(_ value: JSONValue?) throws -> [BodyweightReading] {
        guard let value else { return [] }
        return try records(value).map { entry in
            guard let members = entry.objectValue else {
                throw ProfileArgumentError(
                    "'bodyweight' has to say what he weighed and in what unit, as "
                        + "{\"value\": 182, \"unit\": \"lb\"} — a bare number could only be read "
                        + "by guessing the unit. Add a 'date' to record a past weigh-in. Nothing "
                        + "was written.")
            }
            return BodyweightReading(
                date: try date(members["date"], "bodyweight"),
                mass: try mass(.object(members), "bodyweight")
            )
        }
    }

    // MARK: - What he can already do

    /// The strength baselines a caller stated, checked against the catalog.
    ///
    /// An `exerciseID` the catalog does not have fails the whole call with the
    /// ID named and writes nothing — the rule `PlanImporter` and `write_plan`
    /// both apply, for the same reason: training history is keyed on exercise
    /// identity, so an invented ID would anchor a series that nothing else will
    /// ever join.
    func baselines(_ value: JSONValue?) throws -> [BaselineStatement] {
        guard let value else { return [] }
        return try Self.records(value).map { entry in
            guard let members = entry.objectValue else {
                throw ProfileArgumentError(
                    "Each baseline has to name a lift and what he can do on it, as "
                        + "{\"exerciseID\": \"barbell-bench-press\", \"load\": {\"value\": 205, "
                        + "\"unit\": \"lb\"}, \"reps\": 5}. Nothing was written.")
            }
            let id = ExerciseID(
                rawValue: try Self.text(members["exerciseID"] ?? .null, "exerciseID"))
            guard catalog.exercise(id: id) != nil else {
                throw ProfileArgumentError(
                    "'\(id.rawValue)' is not in the exercise catalog (version \(catalog.version)), "
                        + "so a baseline for it would anchor a history nothing else will ever "
                        + "join. Find the real ID with \(ToolCatalog.listExercises). Nothing was "
                        + "written.")
            }
            guard let reps = (members["reps"] ?? .null).intValue else {
                throw ProfileArgumentError(
                    "The baseline for '\(id.rawValue)' has to say how many reps he can do at that "
                        + "load, as a whole number. A load with no reps beside it is not a "
                        + "starting point. Nothing was written.")
            }
            return BaselineStatement(
                exerciseID: id,
                load: try members["load"].flatMap { $0 == .null ? nil : $0 }
                    .map { try Self.mass($0, "load") },
                reps: reps,
                recordedAt: try Self.date(members["recordedAt"], "baselines")
            )
        }
    }

    /// A series as written: several records, or one on its own.
    ///
    /// Unlike the flat lists this tool takes elsewhere, a record here *is* an
    /// object, so a bare object is one record rather than a shape mistake — and
    /// one weigh-in at a time is the ordinary call.
    static func records(_ value: JSONValue) -> [JSONValue] {
        if case .array(let entries) = value { return entries }
        return [value]
    }

    // MARK: - The two shapes both of them are written in

    /// A weight as the caller wrote it, in the unit he wrote it in.
    ///
    /// Takes the nested form `{"mass": {"value": …, "unit": …}}` and the flat
    /// one alike, and reads a unit written as a word — the same latitude a
    /// weekday and a display unit get here, and for the same reason: this is
    /// prose arriving at a boundary, and the shared document type keeps exactly
    /// one way to decode. Nothing is converted; a weight is recorded as given.
    static func mass(_ value: JSONValue, _ key: String) throws -> Mass {
        let members = value.objectValue ?? [:]
        let weight = members["mass"]?.objectValue ?? members
        guard let number = weight["value"].flatMap(Self.double) else {
            throw ProfileArgumentError(
                "'\(key)' has to carry a numeric 'value'. Nothing was written.")
        }
        guard let named = weight["unit"]?.stringValue, let unit = MassUnit.named(named) else {
            throw ProfileArgumentError(
                "'\(key)' has to name its unit — 'lb' or 'kg'. A weight with no unit could only "
                    + "be read by guessing, and a guess about a load is a training decision. "
                    + "Nothing was written.")
        }
        return Mass(value: number, unit: unit)
    }

    private static func double(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let number): number
        case .integer(let number): Double(number)
        default: nil
        }
    }

    /// An instant written the way both documents write instants, or `nil` when
    /// the caller stated none.
    static func date(_ value: JSONValue?, _ key: String) throws -> Date? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue,
            let parsed = try? Date(text, strategy: .iso8601) else {
            throw ProfileArgumentError(
                "A date in '\(key)' has to be written as ISO 8601 in UTC, e.g. "
                    + "'2026-08-15T12:00:00Z'. Nothing was written.")
        }
        return parsed
    }
}
