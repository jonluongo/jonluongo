import Foundation

/// What one field of a `ProfileUpdate` says about a standing fact.
///
/// Read it with `resolved(from:)`, passing what is currently stored. The three
/// cases exist because "say nothing about this" and "this is no longer known"
/// are different instructions, and a two-case model would force one of them to
/// masquerade as the other: an update that could only set values could never
/// take back a fact recorded in error, and one that treated every absent field
/// as a clear would wipe the profile on every partial update.
///
/// On the wire, `unchanged` is the key being absent and `unstated` is the key
/// present with a JSON `null`.
///
/// Depends on: Foundation only.
public enum StatedValue<Value: Hashable & Sendable>: Hashable, Sendable {

    /// The update said nothing about this fact. Whatever is stored stands.
    case unchanged
    /// The update stated this value. It replaces whatever is stored.
    case stated(Value)
    /// The update said this fact is no longer known. Whatever is stored goes.
    case unstated

    /// What should be stored after this update, given what is stored now.
    ///
    /// `nil` out means not known. A caller whose storage cannot hold absence —
    /// a free-text field where empty already means "not said" — writes
    /// `resolved(from: current) ?? ""` and says so.
    public func resolved(from current: Value?) -> Value? {
        switch self {
        case .unchanged: current
        case .stated(let value): value
        case .unstated: nil
        }
    }

    /// The value this field states, or `nil` when it states none. For a caller
    /// reporting back what an update contained rather than applying it.
    public var stated: Value? {
        if case .stated(let value) = self { return value }
        return nil
    }

    /// Whether this field asks for no change at all.
    public var isUnchanged: Bool { self == .unchanged }

    /// This field laid over an earlier one: what it says if it says anything,
    /// and what the earlier one said if it does not.
    ///
    /// For folding two updates into one when the second was written before the
    /// first had been applied.
    public func superseding(_ earlier: StatedValue<Value>) -> StatedValue<Value> {
        isUnchanged ? earlier : self
    }
}
