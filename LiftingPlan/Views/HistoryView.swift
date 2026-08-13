import SwiftUI
import SwiftData
import Charts

/// Progress over time: every exercise you've logged, with a strength trend and
/// a "pushing" indicator so you can see intensity climbing.
struct HistoryView: View {
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

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
                                ExerciseTrendDetailView(trend: trend)
                            } label: {
                                TrendRow(trend: trend)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trend.name).font(.headline)
                Text("\(trend.points.count) session\(trend.points.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let latest = trend.latestWeight {
                    Text("\(ProgressionEngine.formatted(latest)) lb")
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

    var body: some View {
        List {
            if trend.points.count >= 2 {
                Section("Estimated 1-rep max") {
                    Chart(trend.points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Est. 1RM", point.estimatedOneRepMax ?? 0)
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Est. 1RM", point.estimatedOneRepMax ?? 0)
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
                        if let weight = point.topWeight {
                            Text("\(ProgressionEngine.formatted(weight)) lb × \(point.topReps)")
                                .monospacedDigit()
                        } else {
                            Text("\(point.topReps) reps").monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle(trend.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Trend model

/// One session's top-set result for an exercise.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let topWeight: Double?
    let topReps: Int
    let estimatedOneRepMax: Double?
}

/// All logged sessions for one exercise name, oldest → newest.
struct ExerciseTrend: Identifiable {
    var id: String { name }
    let name: String
    let points: [TrendPoint]

    var latestWeight: Double? { points.last?.topWeight }

    /// True if the most recent estimated 1RM beats the first recorded one.
    var isImproving: Bool {
        guard let first = points.first?.estimatedOneRepMax,
              let last = points.last?.estimatedOneRepMax else { return false }
        return last > first
    }

    /// Build one trend per exercise name across all plans.
    static func build(from plans: [WorkoutPlan]) -> [ExerciseTrend] {
        let loggedExercises = plans
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .filter { !$0.completedWorkingSets.isEmpty }

        var byName: [String: [TrendPoint]] = [:]
        for exercise in loggedExercises {
            let logs = exercise.completedWorkingSets
            let date = logs.map(\.completedAt).max() ?? Date()
            // The "top set" is the heaviest; ties fall back to most reps.
            let topSet = logs.max { lhs, rhs in
                (lhs.weight ?? 0, lhs.reps) < (rhs.weight ?? 0, rhs.reps)
            }
            let est = logs.compactMap(\.estimatedOneRepMax).max()
            let point = TrendPoint(
                date: date,
                topWeight: topSet?.weight,
                topReps: topSet?.reps ?? 0,
                estimatedOneRepMax: est
            )
            byName[exercise.name, default: []].append(point)
        }

        return byName
            .map { name, points in
                ExerciseTrend(name: name, points: points.sorted { $0.date < $1.date })
            }
            .sorted { $0.name < $1.name }
    }
}
