import Foundation

/// Deterministic plan generator used when the on-device model is unavailable
/// (e.g. a simulator without Apple Intelligence) or as a safety net if a model
/// call fails. It builds a sensible split from the user's inputs so the whole
/// app — timers, logging, progression — is fully usable everywhere.
enum TemplatePlanBuilder {

    /// Builds a week of training without the on-device model.
    ///
    /// **Currently returns an empty plan.** The hardcoded exercise list this used
    /// to carry was deleted with the arrival of the 412-entry catalog; selecting
    /// from that catalog against the programming rules in
    /// `docs/superpowers/specs/2026-08-14-workout-programming-design.md` is the
    /// next plan's work. Returning empty is deliberate — a caller gets a visibly
    /// empty plan rather than silently wrong exercises.
    static func build(
        weekdays: [Weekday],
        durationMinutes: Int,
        equipment: Equipment,
        experience: ExperienceLevel
    ) -> PlanBlueprint {
        PlanBlueprint(days: [])
    }

    /// Choose a training split appropriate for how many days per week.
    ///
    /// Not called by `build` yet — `build` returns an empty plan until catalog
    /// selection lands (see its doc comment). Kept because the assembly-rules
    /// work in `docs/superpowers/specs/2026-08-14-workout-programming-design.md`
    /// is exactly what wires this in: choosing which day gets which focus label
    /// is a prerequisite for choosing which exercises fill that day.
    static func splitTemplate(forDayCount count: Int) -> [String] {
        switch count {
        case ...1: return ["Full Body"]
        case 2: return ["Upper Body", "Lower Body"]
        case 3: return ["Push", "Pull", "Legs"]
        case 4: return ["Upper Body", "Lower Body", "Push", "Pull"]
        case 5: return ["Push", "Pull", "Legs", "Upper Body", "Lower Body"]
        default: return ["Push", "Pull", "Legs", "Upper Body", "Lower Body", "Full Body"]
        }
    }
}
