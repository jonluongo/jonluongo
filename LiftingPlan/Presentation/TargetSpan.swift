import Foundation
import LiftingKit

/// The one phrase that covers several prescribed targets — `"3-5"`, `"30-60s"`,
/// `"40-80 m"`, `"8 / AMRAP"`.
///
/// **What it does.** Answers what a list of targets asks for as a whole, without
/// ever naming a figure nobody prescribed. Targets that all say the same thing
/// answer with that thing, verbatim. Targets that differ answer with the span
/// they cover — read as counts, as holds, or as carries in one unit, whichever
/// all of them are — and when they are not all the same kind of work, or one of
/// them names a target no reader here can resolve, they answer by naming each
/// distinct one instead. Nothing is rounded, averaged, or dropped, and no single
/// target is ever picked out to stand for the others.
///
/// **How it is used.** `PrescriptionSummary` asks it for the rep target of an
/// exercise whose sets differ, and for the effort when every set states one on
/// the same scale. It is the reason a ramp reads as one line on a screen the
/// lifter is browsing rather than as one line per set: a span says *these
/// differ, and this is how far* in the space a count used to take.
///
/// **What it depends on.** `RepRange`, `WorkDuration` and `WorkDistance` from
/// LiftingKit — the same three readers the logging screen binds its fields to,
/// so what the span calls a hold and what the row records as a hold cannot
/// disagree. It reads text and states nothing about training.
enum TargetSpan {

    /// What `targets` ask for between them, or `nil` when any of them states
    /// nothing — a span across an absence would be claiming a target for a set
    /// that was never given one.
    static func text(covering targets: [String]) -> String? {
        let stated = targets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !stated.isEmpty, stated.allSatisfy({ !$0.isEmpty }) else { return nil }

        let distinct = distinctInOrder(stated)
        guard distinct.count > 1 else { return distinct.first }
        return counted(distinct)
            ?? held(distinct)
            ?? carried(distinct)
            // Targets measured in different things, or one no reader here can
            // resolve: each is named, unspaced, because this line shares a row
            // with the rest the exercise prescribes and every character it
            // spends is one the rest has not got.
            ?? distinct.joined(separator: "/")
    }

    /// The values in the order they were prescribed, each said once.
    private static func distinctInOrder(_ targets: [String]) -> [String] {
        var seen: Set<String> = []
        return targets.filter { seen.insert($0).inserted }
    }

    /// The span in repetitions, when every target is a rep count.
    private static func counted(_ targets: [String]) -> String? {
        let ranges = targets.map { RepRange($0) }
        guard ranges.allSatisfy({ !$0.isEmpty }),
            let low = ranges.map(\.lowerBound).min(),
            let high = ranges.map(\.upperBound).max()
        else { return nil }
        return low == high ? "\(low)" : "\(low)-\(high)"
    }

    /// The span in seconds, when every target is a hold this build can read.
    /// A hold whose length cannot be resolved leaves the whole list to the
    /// readers after this one rather than being counted as no seconds.
    private static func held(_ targets: [String]) -> String? {
        let holds = targets.map { WorkDuration($0) }
        guard holds.allSatisfy({ $0.isTimed && !$0.isEmpty }),
            let low = holds.map(\.lowerSeconds).min(),
            let high = holds.map(\.upperSeconds).max()
        else { return nil }
        return low == high ? "\(low)s" : "\(low)-\(high)s"
    }

    /// The span over the ground, when every target is a carry in one unit.
    /// Two units are two measurements and nothing here converts one into the
    /// other, so a list mixing them names each of them instead.
    private static func carried(_ targets: [String]) -> String? {
        let carries = targets.map { WorkDistance($0) }
        let units = Set(carries.compactMap(\.unit))
        guard carries.allSatisfy({ $0.isDistance && !$0.isEmpty }),
            units.count == 1, let unit = units.first,
            let low = carries.map(\.lowerValue).min(),
            let high = carries.map(\.upperValue).max()
        else { return nil }
        let value = low == high
            ? low.compactString
            : "\(low.compactString)-\(high.compactString)"
        return "\(value) \(unit.rawValue)"
    }
}
