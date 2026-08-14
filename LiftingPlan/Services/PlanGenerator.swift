import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates weekly lifting plans. Prefers Apple's on-device Foundation Model
/// (guided generation for a guaranteed shape), and transparently falls back to a
/// deterministic template when the model isn't available or a call fails — so the
/// app works on any device or simulator.
@Observable
@MainActor
final class PlanGenerator {

    /// Whether the on-device model can be used right now, with a reason if not.
    enum ModelAvailability: Equatable {
        case available
        case appleIntelligenceNotEnabled
        case deviceNotEligible
        case modelNotReady
        case unsupported

        var isAvailable: Bool { self == .available }

        /// A short line for the UI explaining the current status.
        var statusMessage: String {
            switch self {
            case .available:
                "On-device AI is ready — plans are tailored to your goal."
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in Settings to get AI-tailored plans. Using built-in templates for now."
            case .deviceNotEligible:
                "This device can't run on-device AI. Using built-in templates."
            case .modelNotReady:
                "The on-device model is still downloading. Using built-in templates until it's ready."
            case .unsupported:
                "On-device AI isn't available in this build. Using built-in templates."
            }
        }
    }

    /// Cached availability, refreshed on demand.
    private(set) var availability: ModelAvailability = .unsupported

    init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                availability = .appleIntelligenceNotEnabled
            case .deviceNotEligible:
                availability = .deviceNotEligible
            case .modelNotReady:
                availability = .modelNotReady
            @unknown default:
                availability = .modelNotReady
            }
        @unknown default:
            availability = .unsupported
        }
        #else
        availability = .unsupported
        #endif
    }

    /// Produce a plan for `weekdays`/`durationMinutes`, drawing equipment/goal/
    /// experience from `profile`. `performanceSummary` (from the
    /// `ProgressionEngine`) is included on regeneration so intensity ratchets up.
    /// Returns the blueprint plus whether the on-device model actually produced it.
    func generatePlan(
        profile: UserProfile,
        weekdays: Set<Weekday>,
        durationMinutes: Int,
        performanceSummary: String?
    ) async -> (blueprint: PlanBlueprint, usedModel: Bool) {
        let orderedWeekdays = Weekday.displayOrder.filter(weekdays.contains)
        let fallback = TemplatePlanBuilder.build(
            weekdays: orderedWeekdays,
            durationMinutes: durationMinutes,
            equipment: profile.equipmentAccess,
            experience: profile.experience
        )

        refreshAvailability()
        guard availability.isAvailable, !orderedWeekdays.isEmpty else {
            return (fallback, false)
        }

        #if canImport(FoundationModels)
        do {
            let generated = try await runModel(
                profile: profile,
                orderedWeekdays: orderedWeekdays,
                durationMinutes: durationMinutes,
                performanceSummary: performanceSummary
            )
            let blueprint = Self.blueprint(
                from: generated,
                orderedWeekdays: orderedWeekdays,
                durationMinutes: durationMinutes,
                fallback: fallback
            )
            // If the model returned nothing usable, keep the template.
            return blueprint.days.isEmpty ? (fallback, false) : (blueprint, true)
        } catch {
            return (fallback, false)
        }
        #else
        return (fallback, false)
        #endif
    }

    // MARK: - Model path

    #if canImport(FoundationModels)
    private func runModel(
        profile: UserProfile,
        orderedWeekdays: [Weekday],
        durationMinutes: Int,
        performanceSummary: String?
    ) async throws -> GeneratedPlan {
        let session = LanguageModelSession {
            Self.instructions
        }
        let prompt = Self.prompt(
            profile: profile,
            orderedWeekdays: orderedWeekdays,
            durationMinutes: durationMinutes,
            performanceSummary: performanceSummary
        )
        let response = try await session.respond(to: prompt, generating: GeneratedPlan.self)
        return response.content
    }
    #endif

    // MARK: - Prompt construction

    static let instructions = """
    You are an experienced strength coach who designs efficient, progressive \
    resistance-training programs. Prioritize compound movements first, keep rest \
    periods tight to maintain intensity, and match the plan to the lifter's \
    equipment, experience, and available time. Every day should fit the requested \
    duration. Return only structured plan data.
    """

    static func prompt(
        profile: UserProfile,
        orderedWeekdays: [Weekday],
        durationMinutes: Int,
        performanceSummary: String?
    ) -> String {
        let dayList = orderedWeekdays.map(\.fullName).joined(separator: ", ")
        var lines = [
            "Design a \(orderedWeekdays.count)-day weekly lifting plan.",
            "Training days (return days in this exact order): \(dayList).",
            "Time per session: \(durationMinutes) minutes.",
            "Equipment: \(profile.equipmentAccess.promptDescription).",
            "Experience: \(profile.experience.promptDescription).",
            "Primary goal: \(profile.goal.isEmpty ? "general strength and muscle" : profile.goal).",
            "Give each day a clear focus, 3–6 exercises (compounds first), sets, a rep range, rest seconds (45–180), a rep tempo, and one short cue.",
        ]
        if let summary = performanceSummary, !summary.isEmpty {
            lines.append("")
            lines.append("Recent performance — push intensity where the lifter is ready (more load or reps), hold where they struggled:")
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Mapping

    #if canImport(FoundationModels)
    /// Convert the model's output into a `PlanBlueprint`, assigning weekdays from
    /// the requested order and filling any shortfall from the template.
    ///
    /// Exercises are deliberately left empty here: turning a model-generated
    /// name into a persisted `ExerciseID` requires resolving it against the
    /// catalog through `ExerciseResolver` first (see
    /// `docs/superpowers/specs/2026-08-14-workout-programming-design.md`, "Anything
    /// it returns still passes through `ExerciseResolver`"), and that wiring is
    /// not in place yet. Persisting the generated name directly — or a
    /// name-derived id — would reintroduce the name-keyed-history bug
    /// `ExerciseID` exists to eliminate, so the day skeleton (weekday, focus) is
    /// kept and the exercise list stays empty until that wiring lands, same as
    /// `TemplatePlanBuilder.build`.
    static func blueprint(
        from generated: GeneratedPlan,
        orderedWeekdays: [Weekday],
        durationMinutes: Int,
        fallback: PlanBlueprint
    ) -> PlanBlueprint {
        var days: [DayBlueprint] = []
        for (index, weekday) in orderedWeekdays.enumerated() {
            if index < generated.days.count {
                let g = generated.days[index]
                let focus = g.focus.trimmingCharacters(in: .whitespacesAndNewlines)
                days.append(DayBlueprint(
                    weekday: weekday,
                    focus: focus.isEmpty ? "Training" : focus,
                    durationMinutes: durationMinutes,
                    exercises: []
                ))
            } else if index < fallback.days.count {
                days.append(fallback.days[index])
            }
        }
        return PlanBlueprint(days: days)
    }
    #endif
}

#if canImport(FoundationModels)
// MARK: - Guided-generation schema

@Generable
struct GeneratedPlan {
    @Guide(description: "One entry per requested training day, in the same order as requested.")
    var days: [GeneratedDay]
}

@Generable
struct GeneratedDay {
    @Guide(description: "Short focus label such as Push, Pull, Legs, Upper Body, Lower Body, or Full Body.")
    var focus: String
    @Guide(description: "Three to six exercises for this day, ordered with the main compound lifts first.")
    var exercises: [GeneratedExercise]
}

@Generable
struct GeneratedExercise {
    @Guide(description: "The exercise name, e.g. Barbell Bench Press.")
    var name: String
    @Guide(description: "Primary muscle group, e.g. Chest, Back, Quads.")
    var muscleGroup: String
    @Guide(description: "Number of working sets, from 2 to 5.")
    var sets: Int
    @Guide(description: "Rep range like 8-12, or a single number like 5.")
    var repRange: String
    @Guide(description: "Rest between sets in seconds, from 45 to 180 — keep it tight to maintain intensity.")
    var restSeconds: Int
    @Guide(description: "Rep tempo written as eccentric-pause-concentric-pause, e.g. 3-0-1-0.")
    var tempo: String
    @Guide(description: "One short coaching cue for the movement.")
    var notes: String
}
#endif
