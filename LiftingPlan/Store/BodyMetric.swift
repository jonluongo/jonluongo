import Foundation
import SwiftData

/// One point in the lifter's bodyweight history.
///
/// Bodyweight is tracked as a series of dated readings rather than a single
/// mutable number on `UserProfile`, so trends and charts are possible and a
/// correction never erases history. `bodyweight` is `nil` rather than zero
/// when a reading has not been entered, the same convention `LoggedSet.load`
/// uses for "no value" versus "zero."
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Mass` from Domain.
@Model
final class BodyMetric {
    var date: Date = Date()
    /// The reading as entered, in the unit entered. `nil` when not recorded.
    var bodyweight: Mass?

    init(date: Date = Date(), bodyweight: Mass? = nil) {
        self.date = date
        self.bodyweight = bodyweight
    }
}
