import Foundation
import LiftingKit

/// What a set row's two fields show, and what a lifter's typing means.
///
/// **What it does.** Translates between a `LoggedSet`'s stored values and the
/// strings in the row's weight and work fields — both directions, for all four
/// things a row can record: a load, a rep count, a hold in seconds, and a carry
/// over a distance.
///
/// **Why it is here and not in the row.** It was in `SetRowView`, wrapped in
/// `Binding`s, where the only way to reach it was to build a view. The rules it
/// carries are the ones this app is most careful about — *a hold that was not
/// timed is `nil`, never zero*, and *nothing may put seconds or metres in a rep
/// total* — and they were the least tested code in the project, because a
/// `Binding` is not a thing a test can type into. Everything here is a pure
/// function over a string.
///
/// **The asymmetry between reps and the other two is deliberate.** `reps` is a
/// non-optional `Int` on the model, so an emptied field means zero reps. A hold
/// and a carry are optional, and an emptied field means *not recorded* — a set
/// he did not time did not last no time, and one he did not carry did not travel
/// no distance. Those are different claims and the store keeps them apart.
///
/// **What it depends on.** `Mass` and `Distance` from LiftingKit. It reads no
/// model and holds no state.
enum SetEntry {

    // MARK: - The weight field

    /// What the weight field shows: the load in the lifter's own unit, or
    /// nothing at all when no load was recorded. A set logged without one shows
    /// an empty field rather than a zero he did not lift.
    static func text(for load: Mass?, in unit: MassUnit) -> String {
        load.map { $0.converted(to: unit).value.compactString } ?? ""
    }

    /// The load a typed string means, or `nil` when it means none.
    ///
    /// A comma is read as a decimal point, because a lifter typing `2,5` on a
    /// keyboard that offers one has typed two and a half. Anything else that is
    /// not a number — a stray letter, a half-typed entry — clears the load
    /// rather than keeping the last good value, so the field and the record
    /// always say the same thing.
    static func load(from text: String, in unit: MassUnit) -> Mass? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return Mass(value: value, unit: unit)
    }

    // MARK: - The work field, in whichever of three things the row records

    /// What the work field shows for a counted set. Zero shows as nothing: the
    /// row is offering a place to type, not reporting that he did none.
    static func text(forReps reps: Int) -> String {
        reps > 0 ? String(reps) : ""
    }

    /// The rep count a typed string means. Non-digits are dropped rather than
    /// refused, so a stray character does not swallow the number around it, and
    /// an empty field is zero — `reps` is not optional, and a counted set with
    /// nothing in the field has no reps rather than an unknown number of them.
    static func reps(from text: String) -> Int {
        Int(text.filter(\.isNumber)) ?? 0
    }

    /// What the work field shows for a hold, in seconds, or nothing when it was
    /// not timed.
    static func text(forSeconds seconds: Int?) -> String {
        seconds.map(String.init) ?? ""
    }

    /// The hold a typed string means, or `nil` when the field is empty — which
    /// is *not timed*, and is a different statement from a hold of zero
    /// seconds.
    static func seconds(from text: String) -> Int? {
        Int(text.filter(\.isNumber))
    }

    /// What the work field shows for a carry, in the unit it was prescribed in.
    /// Nothing here converts: a carry prescribed in yards is shown in yards.
    static func text(for distance: Distance?) -> String {
        distance.map { $0.value.compactString } ?? ""
    }

    /// The carry a typed string means, in the unit the plan prescribed, or `nil`
    /// when the field is empty — which is *did not happen*, not a carry of no
    /// distance. Commas are read as decimal points, as in the weight field.
    static func distance(from text: String, in unit: DistanceUnit) -> Distance? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return Distance(value: value, unit: unit)
    }
}
