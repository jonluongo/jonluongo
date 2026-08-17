import Foundation

extension String {

    /// The same string with its first character lowercased, for a phrase that
    /// was written to lead a line and now follows a dot in one.
    ///
    /// `RestPrescription` writes "Rest 2min" because it was a heading; joined
    /// behind a prescription it reads "3 × 10-12 · rest 2min". Only the first
    /// character changes, so a phrase that begins with a figure or an acronym is
    /// returned as written.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
