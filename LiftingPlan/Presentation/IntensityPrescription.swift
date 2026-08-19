import Foundation
import LiftingKit

/// How a prescribed effort is written on screen.
///
/// **What it does.** Turns an `IntensityTarget` into the phrase a lifter would
/// read — `"80% effort"`, `"2 RIR"`, `"80% 1RM"` — for the exercise header, the
/// set rows, and the session preview.
///
/// **RPE is written as a percentage of effort.** `RPE 8` is jargon standing for
/// a position on a ten-point scale, and the owner reads a percentage without
/// having to translate. The figure is the same figure: eight out of ten written
/// as eighty out of a hundred, which is a restatement rather than a conversion.
/// Nothing here maps an RPE onto a percentage of a maximum — that is a table
/// lookup depending on the rep count, a genuine training claim, and not
/// something this app would ever make.
///
/// **`% effort` and `% 1RM` are different sentences and both say `%`.** They are
/// distinguished by the word after the figure, and the second is never derived
/// from the first: `80% 1RM` appears only where Claude prescribed a percentage
/// of a maximum himself.
///
/// **How it is used.** Call `label(for:)` and draw the result; `nil` means the
/// plan named no target, and nothing is drawn rather than a placeholder
/// inviting the lifter to invent one.
///
/// **What it depends on.** `IntensityTarget` from LiftingKit. It formats and
/// nothing else: no scale is converted into another, no value is bounded or
/// rounded, and a scale this build has never heard of is shown as written
/// rather than dropped — which is the only honest thing to do with a target
/// somebody deliberately prescribed.
enum IntensityPrescription {

    /// The target as a phrase, or `nil` when there is none.
    static func label(for intensity: IntensityTarget?) -> String? {
        guard let intensity else { return nil }
        let value = intensity.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        // A value that will not read as a number is not made into one. "RPE
        // 8-9" spans; "RPE top set" is not something to multiply, and is shown
        // as written rather than mangled into a figure nobody prescribed.
        if intensity.scale == .rpe {
            guard let percent = Self.effortPercent(value) else { return "RPE \(value)" }
            return "\(percent) effort"
        }
        if intensity.scale == .repsInReserve { return "\(value) RIR" }
        if intensity.scale == .percentOfOneRepMax {
            // "80" and "80%" both read as a percentage; neither gains a second
            // per-cent sign, and neither loses one it was written with.
            return value.hasSuffix("%") ? "\(value) 1RM" : "\(value)% 1RM"
        }
        // A scale nobody here has heard of is named and shown, in the words it
        // arrived in. Guessing at a phrasing for it would be inventing one.
        return "\(intensity.scale.rawValue) \(value)"
    }

    /// A point or a span on the ten-point scale, written out of a hundred —
    /// `"8"` as `"80%"`, `"7-8"` as `"70-80%"`, `"7.5"` as `"75%"`.
    ///
    /// `nil` when any part of it is not a number, which is the whole of the
    /// guard on this: a value the app cannot read is a value it must print as
    /// written rather than turn into a figure the plan does not contain.
    private static func effortPercent(_ value: String) -> String? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var written: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let rating = Double(trimmed) else { return nil }
            written.append((rating * 10).compactString)
        }
        return written.joined(separator: "-") + "%"
    }
}
