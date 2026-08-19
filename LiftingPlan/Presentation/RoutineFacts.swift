import Foundation
import LiftingKit

/// The shape a routine was given, as stated facts.
///
/// **What it does.** Counts what the plan holds — its blocks, its sessions, how
/// many of them are logged — and states the days and the session length it was
/// written with. Every figure is a count of what the plan says or what the record
/// holds; nothing here concludes anything about how the training is going.
///
/// **A fact the plan did not state is absent rather than zero.** A routine that
/// never said how long a session runs has not said it runs for no time, and a
/// plan with no weekdays has not said it trains on none. An absent row is the
/// only honest answer to a question nobody answered.
///
/// **How it is used.** `RoutineInfoSheet` calls `facts` and draws each through
/// `FactRow`. It lives here rather than in the sheet because a list of counts is
/// worth testing against strings, and because a sheet that imports SwiftUI is
/// not where a count belongs.
///
/// **What it depends on.** `TrainingPlan` and the models under it. It writes
/// nothing.
enum RoutineFacts {

    /// The routine's shape, in reading order: how much of it there is, how much
    /// is done, and what it was written to fit.
    static func facts(of plan: TrainingPlan) -> [StatedFact] {
        var facts: [StatedFact] = []
        let blocks = plan.orderedWeeks
        if !blocks.isEmpty { facts.append(StatedFact(label: "Blocks", value: "\(blocks.count)")) }
        let days = blocks.flatMap(\.orderedDays)
        if !days.isEmpty {
            facts.append(StatedFact(label: "Sessions", value: "\(days.count)"))
            facts.append(
                StatedFact(label: "Logged", value: "\(days.count { $0.completedAt != nil })"))
        }
        let weekdays = plan.orderedWeekdays
        if !weekdays.isEmpty {
            facts.append(StatedFact(
                label: "Training days",
                value: weekdays.map(\.shortName).joined(separator: ", ")))
        }
        if let minutes = plan.durationMinutes {
            facts.append(StatedFact(label: "Session length", value: "\(minutes) min"))
        }
        return facts
    }
}
