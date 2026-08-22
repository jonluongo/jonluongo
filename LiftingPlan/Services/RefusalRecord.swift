import Foundation
import LiftingKit

/// What the phone last turned away, kept until a plan is taken in.
///
/// **What it does.** Holds one refusal — the arriving plan the phone would not
/// accept, and why, in the words written for its author — so the next snapshot
/// can carry it back to the coach.
///
/// **How it is used.** `DocumentInbox` records a refusal when it turns a plan
/// away and clears it when one lands; `SnapshotOutbox` reads it on its way out.
/// The two never speak directly: the inbox runs when a document arrives and the
/// outbox when the app is leaving, and a value passed between them in memory
/// would be lost by the app being killed in between — which is precisely the
/// case where the coach most needs telling.
///
/// **Why `UserDefaults` and not the store.** `Store/` is the user's training
/// record and mirrors to CloudKit. A refusal is neither: it is this phone's
/// answer about one document, it is true for as long as that document is the
/// last one, and it must never sync — a second device reading it would report a
/// refusal it did not make. It is the same reasoning that keeps the rest
/// preference out of the store.
///
/// **What it depends on.** Foundation, `SnapshotRefusal` from LiftingKit, and a
/// `UserDefaults`. It reads no store and draws nothing.
struct RefusalRecord {

    private let defaults: UserDefaults
    private static let key = "lastPlanRefusal"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The refusal standing against the plan in the folder, or `nil` when the
    /// last plan was taken in.
    var current: SnapshotRefusal? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            // **A record that cannot be read is no record.** It is one string
            // and a date about a document that has since been replaced; failing
            // the export over it would cost the coach the whole log to preserve
            // a note about one plan.
            return try? JSONDecoder().decode(SnapshotRefusal.self, from: data)
        }
        nonmutating set {
            guard let refusal = newValue else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            guard let data = try? JSONEncoder().encode(refusal) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }
}
