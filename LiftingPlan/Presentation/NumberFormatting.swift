import Foundation

extension Double {
    /// The number as the user would write it on a whiteboard: `135`, not
    /// `135.0`, but `62.5` kept intact.
    ///
    /// Used wherever a weight or a distance is rendered — the set table, the
    /// previous-performance column, and the history view — so the same number
    /// reads the same way everywhere. Display only: it never rounds a value,
    /// it only chooses how many digits to show. Depends on: Foundation.
    var compactString: String {
        self == rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}
