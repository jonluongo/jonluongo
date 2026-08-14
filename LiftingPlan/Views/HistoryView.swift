import SwiftUI
import SwiftData
import Charts

/// Progress over time: every exercise you've logged, with a strength trend and
/// a "pushing" indicator so you can see intensity climbing.
///
/// Trends are keyed by `exerciseID`, never by name — the same identity rule
/// `PerformanceHistory` enforces, so a renamed or re-generated exercise doesn't
/// silently fragment its own history. Weights are shown in `profile.displayUnit`.
struct HistoryView: View {
    let profile: UserProfile

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    private var trends: [ExerciseTrend] { ExerciseTrend.build(from: plans) }

    var body: some View {
        Group {
            if trends.isEmpty {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Log some sets in a workout and your progress shows up here.")
                }
            } else {
                List {
                    Section("Exercises") {
                        ForEach(trends) { trend in
                            NavigationLink {
                                ExerciseTrendDetailView(trend: trend, unit: profile.displayUnit)
                            } label: {
                                TrendRow(trend: trend, unit: profile.displayUnit)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }
}

private struct TrendRow: View {
    let trend: ExerciseTrend
    let unit: MassUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trend.displayName).font(.headline)
                Text("\(trend.points.count) session\(trend.points.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let latest = trend.latestLoad {
                    let converted = latest.converted(to: unit)
                    Text("\(ProgressionEngine.formatted(converted.value)) \(unit.rawValue)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if trend.isImproving {
                    Label("up", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Chart + session list for a single exercise.
struct ExerciseTrendDetailView: View {
    let trend: ExerciseTrend
    let unit: MassUnit

    var body: some View {
        List {
            if trend.points.count >= 2 {
                Section("Estimated 1-rep max") {
                    Chart(trend.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Est. 1RM", displayEstimate(point))
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Est. 1RM", displayEstimate(point))
                        )
                    }
                    .frame(height: 200)
                    .padding(.vertical, 8)
                }
            }

            Section("Sessions") {
                ForEach(trend.points.reversed()) { point in
                    HStack {
                        Text(point.date, format: .dateTime.month().day())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let load = point.topLoad {
                            let converted = load.converted(to: unit)
                            Text("\(ProgressionEngine.formatted(converted.value)) \(unit.rawValue) × \(point.topReps)")
                                .monospacedDigit()
                        } else {
                            Text("\(point.topReps) reps").monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle(trend.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Estimated 1RM, converted from its stable kilogram basis into the
    /// display unit for the chart's Y axis.
    private func displayEstimate(_ point: TrendPoint) -> Double {
        guard let kilograms = point.estimatedOneRepMaxKilograms else { return 0 }
        return Mass(value: kilograms, unit: .kilograms).converted(to: unit).value
    }
}

// MARK: - Trend model

/// One session's top-set result for an exercise.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let topLoad: Mass?
    let topReps: Int
    /// Kept in kilograms (the Epley formula's stable comparison basis) rather
    /// than a display unit, so callers convert once at the point of display.
    let estimatedOneRepMaxKilograms: Double?
}

/// All logged sessions for one exercise, oldest → newest.
struct ExerciseTrend: Identifiable {
    var id: ExerciseID { exerciseID }
    let exerciseID: ExerciseID
    /// For display only — never compared or used as a key.
    let displayName: String
    let points: [TrendPoint]

    var latestLoad: Mass? { points.last?.topLoad }

    /// True if the most recent estimated 1RM beats the first recorded one.
    var isImproving: Bool {
        guard let first = points.first?.estimatedOneRepMaxKilograms,
              let last = points.last?.estimatedOneRepMaxKilograms else { return false }
        return last > first
    }

    /// Build one trend per exercise id across all plans.
    static func build(from plans: [TrainingPlan]) -> [ExerciseTrend] {
        let loggedExercises = plans
            .flatMap(\.orderedWeeks)
            .flatMap(\.orderedDays)
            .flatMap(\.orderedExercises)
            .filter { !$0.completedWorkingSets.isEmpty }

        var byID: [ExerciseID: (displayName: String, points: [TrendPoint])] = [:]
        for exercise in loggedExercises {
            let logs = exercise.completedWorkingSets
            let date = logs.map(\.completedAt).max() ?? Date()
            // The "top set" is the heaviest; ties fall back to most reps.
            let topSet = logs.max { lhs, rhs in
                (lhs.load?.kilograms ?? 0, lhs.reps) < (rhs.load?.kilograms ?? 0, rhs.reps)
            }
            let est = logs.compactMap(\.estimatedOneRepMaxKilograms).max()
            let point = TrendPoint(
                date: date,
                topLoad: topSet?.load,
                topReps: topSet?.reps ?? 0,
                estimatedOneRepMaxKilograms: est
            )
            byID[exercise.exerciseID, default: (exercise.displayName, [])].points.append(point)
        }

        return byID
            .map { id, entry in
                ExerciseTrend(
                    exerciseID: id, displayName: entry.displayName,
                    points: entry.points.sorted { $0.date < $1.date }
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}
