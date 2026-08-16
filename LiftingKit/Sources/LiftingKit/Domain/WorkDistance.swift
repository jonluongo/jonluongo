import Foundation

/// A prescribed carry, read out of the free text a plan writes its target in —
/// `"40 metres"`, `"40 m"`, `"50-100 yd"`, `"20 ft"`.
///
/// **What it does.** Answers two questions about one target string, and keeps
/// them apart: *is this work measured over a distance rather than counted or
/// held* (`isDistance`, with `unit` saying in what), and *how far does it say*
/// (`lowerValue`, `upperValue`, `distance`). The two are separate for the reason
/// they are separate in `WorkDuration`: a target can plainly be a carry without
/// naming a number this build can resolve, and a carry whose distance cannot be
/// read is still a carry.
///
/// **How it is used.** Through `WorkMeasure`, which is what the app actually
/// asks: the active-workout log needs one answer about which of three things a
/// row records, not three booleans it could get contradictory answers from.
/// `distance` is the value a new row is seeded with. The prescription itself is
/// always shown verbatim; this type only says what can be read out of it.
///
/// **What it depends on.** `TargetUnits` for the vocabulary and for the scan,
/// both shared with `RepRange` and `WorkDuration` — it is the same reader with a
/// different unit family, not a second parser — plus `Distance` for the answer.
/// It decides nothing about training: no value here says how far anything should
/// be carried, only what a word means.
///
/// **The unit is kept, never converted.** `"50 yards"` reads as fifty yards and
/// stays fifty yards through the log, the snapshot and the volume report. This
/// is where a distance parts company with a duration: a minute is sixty seconds
/// by definition, so `WorkDuration` can answer in one number, while yards and
/// metres are two units a report must keep apart rather than one it may quietly
/// pick between.
///
/// A distance is read only when the text is unambiguous. Two different units in
/// one string (`"40 m then 20 yd"`), a number with no unit at all, or a time
/// named beside it (`"40 m in 30 seconds"`, which the clock claims) leave the
/// bounds empty rather than guessing which number meant what.
public struct WorkDistance: Hashable, Sendable, CustomStringConvertible {

    /// Whether the target is measured over a distance rather than counted or
    /// held.
    ///
    /// True when the text names a distance unit, no rep count could be read out
    /// of it, and the clock has not already claimed it. This is what decides
    /// which field the lifter is given, so it deliberately answers for text
    /// whose number cannot be read.
    public let isDistance: Bool

    /// The unit the target is measured in — the first one it names. `nil` when
    /// the target is not a distance at all. A target naming two units states no
    /// one distance, but it is still measured in the unit it opens in, which is
    /// what the field the lifter types into has to be labelled with.
    public let unit: DistanceUnit?

    /// The shorter of the two bounds, in `unit` (0 when none was read).
    public let lowerValue: Double

    /// The longer of the two bounds, in `unit` (0 when none was read).
    public let upperValue: Double

    /// True when no distance could be read out of the text — because it names
    /// none, or because what it names cannot be resolved to a number without
    /// guessing.
    public let isEmpty: Bool

    /// The single distance this target names, or `nil` when it names a range, or
    /// none. What a new set is seeded with: a range names no one distance, and
    /// picking an end of it would be the app deciding how far to carry.
    public var distance: Distance? {
        guard !isEmpty, lowerValue == upperValue, let unit else { return nil }
        return Distance(value: lowerValue, unit: unit)
    }

    /// Reads free text. See the type doc for what is read and what is refused.
    ///
    /// A target is a carry when it names a distance unit, `RepRange` could read
    /// no rep count out of it, *and* `WorkDuration` has not already claimed it.
    /// That last clause is what keeps three readers from ever claiming one
    /// target: a reader only takes what nothing before it took, so `"40 m in 30
    /// seconds"` stays the timed target it already was rather than becoming a
    /// carry as well.
    public init(_ text: String) {
        let named = TargetUnits.unitWords(in: text)
            .compactMap { TargetUnits.distanceUnitPerWord[$0] }
            .first
        isDistance = named != nil && RepRange(text).isEmpty && !WorkDuration(text).isTimed
        unit = isDistance ? named : nil

        guard isDistance, let stated = TargetUnits.statedQuantities(in: text),
            TargetUnits.distanceUnitPerWord[stated.unit] != nil,
            let first = stated.values.first, let last = stated.values.last,
            first > 0, last > 0
        else {
            lowerValue = 0
            upperValue = 0
            isEmpty = true
            return
        }
        lowerValue = Double(min(first, last))
        upperValue = Double(max(first, last))
        isEmpty = false
    }

    /// A readable form: `"40 m"`, `"50-100 yd"`, or `""` when nothing was read.
    public var description: String {
        guard !isEmpty, let unit else { return "" }
        guard let single = distance else {
            return "\(Self.written(lowerValue))-\(Self.written(upperValue)) \(unit.rawValue)"
        }
        return single.description
    }

    /// A bound as it would be written on a whiteboard: `40`, not `40.0`.
    private static func written(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
