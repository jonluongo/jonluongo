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
