import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// Call `cloudKit()` from the app entry point and `inMemory()` from tests and
/// previews. Keeping both behind one type means the schema is declared once,
/// so a model added to the app but forgotten in tests cannot happen.
///
/// Depends on: the `Store/` models.
enum StoreContainer {

    /// Every persisted model. Adding a model without adding it here means it
    /// silently never persists.
    static let schema = Schema([
        UserProfile.self,
        TrainingPlan.self,
        TrainingWeek.self,
        WorkoutDay.self,
        PlannedExercise.self,
        LoggedSet.self,
        PlanMessage.self,
        BodyMetric.self,
        StrengthBaseline.self,
    ])

    /// The production container, backed by the user's private CloudKit database.
    static func cloudKit() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An ephemeral container for tests and previews. Never touches CloudKit.
    static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
