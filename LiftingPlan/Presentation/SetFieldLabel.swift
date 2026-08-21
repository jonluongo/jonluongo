import Foundation
import LiftingKit

/// What each field of a set row is called aloud.
///
/// **What it does.** Names the two fields a user types into — the load, and
/// whatever this exercise measures its work in — so each says what it is and
/// which set it belongs to.
///
/// **Why it exists.** A `TextField` takes its accessibility label from its
/// placeholder, and here the placeholder is the *prescription*: the weight field
/// of a set prescribed at 185 announced itself as "185", and the work field of
/// one prescribed 8-12 announced itself as "8-12". Two adjacent fields, both
/// naming a figure and neither naming itself, on the one screen where a user
/// is entering numbers he cannot see. The badge beside them and the check at the
/// end were both labelled; these were not.
///
/// **How it is used.** `SetRowView` asks for each field's label and applies it.
/// The wording is built from what the row already knows — `SetIdentity.spoken`
/// for which set, `WorkMeasure` for what it records — rather than from new copy,
/// so a row cannot say one thing on screen and another aloud.
///
/// **What it depends on.** `WorkMeasure` from LiftingKit, `MassUnit` for the
/// load's unit, and `SetIdentity`. It reads nothing and decides nothing.
enum SetFieldLabel {

    /// The weight field: `"Weight in pounds, working set 3"`.
    static func load(unit: MassUnit, identity: SetIdentity) -> String {
        "Weight in \(spoken(unit)), \(identity.spoken)"
    }

    /// The work field, named for what this exercise actually measures —
    /// `"Repetitions, working set 3"`, `"Seconds held, warm-up set"`,
    /// `"Metres carried, working set 1"`.
    ///
    /// A set is counted, held, or carried, and no two of them are the same
    /// number; the field that records one says which it is.
    static func work(measure: WorkMeasure, identity: SetIdentity) -> String {
        "\(name(of: measure)), \(identity.spoken)"
    }

    private static func name(of measure: WorkMeasure) -> String {
        switch measure {
        case .repetitions: "Repetitions"
        case .time: "Seconds held"
        case .distance(let unit): "\(spoken(unit).capitalizedFirst) carried"
        }
    }

    /// Units are said as words rather than as the abbreviations the column
    /// draws: "lb" is read aloud as letters, and "m" as a letter, neither of
    /// which is what he calls them.
    private static func spoken(_ unit: MassUnit) -> String {
        switch unit {
        case .pounds: "pounds"
        case .kilograms: "kilograms"
        }
    }

    /// `DistanceUnit` is an extensible taxonomy rather than a closed enum, so
    /// this maps the ones the catalog uses and falls through to whatever a
    /// document stated. A unit nobody here has heard of is read out as written,
    /// which is the same answer the rest of the app gives an unknown value.
    private static func spoken(_ unit: DistanceUnit) -> String {
        switch unit {
        case .metres: "metres"
        case .kilometres: "kilometres"
        case .yards: "yards"
        case .feet: "feet"
        case .miles: "miles"
        default: unit.rawValue
        }
    }
}

extension String {
    /// The first character upper-cased, leaving the rest as written — for a
    /// unit word that begins a label rather than following one.
    fileprivate var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
