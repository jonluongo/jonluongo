import Foundation

/// The unit a distance was stated in.
///
/// **What it does.** Names a unit of length without claiming to know how it
/// relates to any other one. Raw values are the abbreviations a prescription and
/// the log are written in — `"m"`, `"yd"` — and every spelling of a unit
/// (`"metre"`, `"meters"`) canonicalizes to the same value, because those are
/// two ways of writing one unit rather than two units.
///
/// **How it is used.** Read it off a `Distance`. `known` is what this build can
/// read out of a prescription's free text; it is not what it can carry. A
/// distance recorded in a unit nobody here thought of decodes, stores and
/// reports intact — that is what makes this a taxonomy rather than an enum, and
/// the day someone logs a sled push in furlongs is not the day the log stops
/// reading.
///
/// **What it depends on.** `ExtensibleTaxonomy`. Nothing here converts one unit
/// into another and nothing ranks them: there is no factor in this file, because
/// a distance is reported in the unit it was performed in.
public struct DistanceUnit: ExtensibleTaxonomy {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    public static let metres = DistanceUnit(rawValue: "m")
    public static let kilometres = DistanceUnit(rawValue: "km")
    public static let yards = DistanceUnit(rawValue: "yd")
    public static let feet = DistanceUnit(rawValue: "ft")
    public static let miles = DistanceUnit(rawValue: "mi")

    public static let known: [DistanceUnit] = [.metres, .kilometres, .yards, .feet, .miles]
}

/// A distance that always knows the unit it was measured in.
///
/// **What it does.** Holds how far the work went and in what unit, together, so
/// neither can travel without the other. It is `Mass`'s mirror for a carry: a
/// sled pushed 40 metres and one pushed 40 yards are different work, and a
/// number without its unit cannot tell them apart.
///
/// **How it is used.** Construct one with the number the lifter actually
/// entered, in the unit the plan prescribed. `LoggedSet.distance` stores it,
/// `SnapshotLoggedSet.distance` reports it, and `volume_by_muscle` totals it
/// per unit.
///
/// **What it depends on.** `DistanceUnit`, Foundation. **Deliberately unlike
/// `Mass`, it offers no conversion at all.** `Mass` can convert because a pound
/// is exactly 0.45359237 kg and both units are closed and known; a distance here
/// may be stated in a unit this build has never seen, and a total that quietly
/// turned yards into metres would report a number nobody carried. Distances are
/// reported side by side in the units they were done in, and whoever is
/// reasoning about them may relate them however he means to.
public struct Distance: Codable, Hashable, Sendable, CustomStringConvertible {

    /// The number as stated, in `unit`.
    public let value: Double
    public let unit: DistanceUnit

    public init(value: Double, unit: DistanceUnit) {
        self.value = value
        self.unit = unit
    }

    /// A readable form: `"40 m"`, `"12.5 yd"`.
    public var description: String {
        let written = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(written) \(unit.rawValue)"
    }
}
