import Foundation
import SwiftData

/// Who produced a turn in a plan's conversation.
enum PlanMessageRole: String, Codable, Sendable, CaseIterable {
    case user
    case assistant
}

/// One turn in the conversation attached to a plan.
///
/// This is what makes a plan project-like rather than a bare record: the
/// discussion that produced and revised it lives with it, so "make week 4 a
/// deload" is scoped to one plan instead of a global chat.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PlanMessage {
    private var roleRaw: String = PlanMessageRole.user.rawValue
    var text: String = ""
    var createdAt: Date = Date()

    var plan: TrainingPlan?

    init(role: PlanMessageRole = .user, text: String = "", createdAt: Date = Date()) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var role: PlanMessageRole {
        get { PlanMessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }
}
