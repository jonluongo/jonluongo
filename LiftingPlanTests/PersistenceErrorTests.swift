import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

@Suite("Persistence errors")
struct PersistenceErrorTests {

    @Test("A persistence error carries a message a user could be shown")
    func hasUserFacingDescription() {
        struct Underlying: Error {}
        let error = PersistenceError.saveFailed(underlying: Underlying())
        let description = error.errorDescription
        #expect(description != nil)
        #expect(!(description ?? "").isEmpty)
    }

    @Test("A persistence error keeps the underlying cause for diagnosis")
    func preservesUnderlyingError() {
        struct Underlying: Error, Equatable { let code = 42 }
        let error = PersistenceError.saveFailed(underlying: Underlying())
        guard case .saveFailed(let underlying) = error else {
            Issue.record("expected saveFailed")
            return
        }
        #expect(underlying is Underlying)
    }

    @Test("Saving a valid context succeeds")
    func saveSucceeds() throws {
        let container = try StoreContainer.inMemory()
        let context = ModelContext(container)
        context.insert(UserProfile())
        try context.saveOrThrow()
    }
}
