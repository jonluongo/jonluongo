import Foundation
import LiftingKit

/// How the lifter's own account of a set's effort is written down, and which
/// sets are asked for one at all.
///
/// **What it does.** Turns the text of an effort field into the rating stored on
/// `LoggedSet.rpe`, and back again, and answers whether a set should offer the
/// field in the first place. It is `IntensityPrescription`'s counterpart: that
/// one draws the effort the plan asked for, this one records the effort that was
/// given.
///
/// **How it is used.** A set row asks `isInvited(by:)` before drawing anything —
/// the field appears only where the plan named an intensity target, so a lifter
/// working through an ordinary prescription is never asked to rate a set nobody
/// asked him about. When it is drawn, it binds through `text(for:)` and
/// `rating(from:)`.
///
/// **Absence is absence.** An empty field is `nil`, never zero. A set nobody
/// rated said nothing about how it felt; a set rated zero made a claim, and a
/// reader deciding how a block progressed cannot tell the two apart if they
/// arrive as the same number. That is the same rule `durationSeconds` and
/// `distance` keep, and for the same reason.
///
/// **What it depends on.** `SetPrescription` and `IntensityTarget` from
/// LiftingKit, and `IntensityPrescription` for the one question of whether a
/// target is really stated. It judges nothing: no rating is bounded, rounded, or
/// compared with what was prescribed — the scale a coach works in is his, and
/// what a rating means about the next session is his too.
enum EffortEntry {

    /// Whether this set should be asked how hard it felt.
    ///
    /// Only where the plan named an intensity target. The question is worth
    /// asking when somebody asked it: an effort prescribed is an effort the
    /// coach intends to read back, and a field on every set of every exercise
    /// would be a form the app invented for itself. `nil` — a warmup, or a set
    /// the lifter added past the ones prescribed — is not asked.
    static func isInvited(by prescription: SetPrescription?) -> Bool {
        invitation(from: prescription) != nil
    }

    /// The target to ask against, or `nil` when the plan asked for none.
    ///
    /// The row needs the target itself, not the fact that one exists: the field
    /// is labelled with the scale the plan named and shows the number it asked
    /// for. A target whose value is blank invites nothing — there would be
    /// nothing to compare an answer to.
    static func invitation(from prescription: SetPrescription?) -> IntensityTarget? {
        guard let intensity = prescription?.intensity,
              IntensityPrescription.label(for: intensity) != nil
        else { return nil }
        return intensity
    }

    /// The rating a field's text records, or `nil` when it records none.
    ///
    /// An empty or blank field is no rating, and so is text that is not a
    /// number — the same answer the weight and distance fields give, so a
    /// cleared field never leaves a stale number behind. Nothing is bounded:
    /// a coach may work on a scale that runs past ten, and a rating outside the
    /// one this app happens to describe is still what the lifter said.
    static func rating(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// A stored rating as the text of the field it was typed into. No rating is
    /// an empty field — not a zero, and not a dash standing in for one.
    static func text(for rating: Double?) -> String {
        rating.map(\.compactString) ?? ""
    }
}
