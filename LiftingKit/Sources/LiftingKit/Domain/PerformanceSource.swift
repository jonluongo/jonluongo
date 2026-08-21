import Foundation

/// How a performed set came to be known.
///
/// **What it does.** Distinguishes a set the lifter ticked in the app from one
/// he told the coach about — a starting point stated in conversation, a lift he
/// did before any of this existed.
///
/// **Why it is not two tables.** A stated baseline and a logged set have exactly
/// the same columns and the same immutability, and differ only in where the fact
/// came from. That is what a discriminator is for. `StrengthBaseline` was a
/// second table saying the same thing in the same shape, so `exercise_history`
/// had to report two of them.
///
/// **What it depends on.** Foundation. It is a closed set the app owns rather
/// than an extensible taxonomy: there is no third way for a fact about a
/// completed set to arrive, and data cannot invent one.
public enum PerformanceSource: String, Codable, Hashable, Sendable, CaseIterable {

    /// Ticked in the app, at the time.
    case logged

    /// Told to the coach rather than logged. He did it; nobody watched.
    case stated
}
