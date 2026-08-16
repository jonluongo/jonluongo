import SwiftUI
import SwiftData
import Charts
import LiftingKit

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
                    Text("\(converted.value.compactString) \(unit.rawValue)")
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

/// One plottable estimate: a session that had an estimable 1-rep max, in the
/// display unit, and which unbroken run of such sessions it belongs to.
private struct ChartEstimate: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    /// Sessions separated by one with no estimate get different runs, which is
    /// what makes the line break rather than span the gap.
    let run: Int
}

/// Chart + session list for a single exercise.
struct ExerciseTrendDetailView: View {
    let trend: ExerciseTrend
    let unit: MassUnit

    var body: some View {
        List {
            if estimates.count >= 2 {
                Section("Estimated 1-rep max") {
                    Chart(estimates) { estimate in
                        // `run` breaks the line wherever a session had nothing
                        // to estimate from: each unbroken stretch is its own
                        // series, so absence reads as a gap. It used to plot as
                        // 0, which drew a collapse in strength that never
                        // happened.
                        LineMark(
                            x: .value("Date", estimate.date),
                            y: .value("Est. 1RM", estimate.value),
                            series: .value("Run", estimate.run)
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", estimate.date),
                            y: .value("Est. 1RM", estimate.value)
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
                            Text("\(converted.value.compactString) \(unit.rawValue) × \(point.topReps)")
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

    /// Only the sessions there is an estimate for, converted from the stable
    /// kilogram basis into the display unit, each tagged with the unbroken run
    /// it belongs to.
    ///
    /// Sessions with no estimable 1-rep max — bodyweight work, a set logged
    /// with no load — produce no entry at all and increment `run`, so the
    /// chart shows a gap where there is no answer instead of drawing one.
    private var estimates: [ChartEstimate] {
        var result: [ChartEstimate] = []
        var run = 0
        var previousWasEstimable = false
        for point in trend.points {
            guard let kilograms = point.estimatedOneRepMaxKilograms else {
                previousWasEstimable = false
                continue
            }
            if !previousWasEstimable && !result.isEmpty { run += 1 }
            previousWasEstimable = true
            result.append(ChartEstimate(
                date: point.date,
                value: Mass(value: kilograms, unit: .kilograms).converted(to: unit).value,
                run: run
            ))
        }
        return result
    }
}
