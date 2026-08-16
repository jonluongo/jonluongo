import SwiftUI
import SwiftData
import Charts
import LiftingKit

/// Every exercise you have logged, and what you actually lifted each session.
///
/// Trends are keyed by `exerciseID`, never by name — the same identity rule
/// `PerformanceHistory` enforces, so a renamed or re-generated exercise doesn't
/// silently fragment its own history. Weights are shown in `profile.displayUnit`.
///
/// It shows what happened and says nothing about it. There is no green arrow
/// here now: the arrow was drawn from one formula's estimate of a one-rep max,
/// which was this app telling the lifter he was getting stronger on the strength
/// of a training opinion it had no business holding.
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
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(trend.displayName).font(.barbellTitle)
                Text("\(trend.points.count) session\(trend.points.count == 1 ? "" : "s")")
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.tight) {
                if let latest = trend.latestLoad {
                    let converted = latest.converted(to: unit)
                    Text("\(converted.value.compactString) \(unit.rawValue)")
                        .font(.barbellSupport)
                }
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}

/// One plottable session: the heaviest load it was logged with, in the display
/// unit, and which unbroken run of loaded sessions it belongs to.
private struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    /// Sessions separated by one carrying no load get different runs, which is
    /// what makes the line break rather than span the gap.
    let run: Int
}

/// Chart + session list for a single exercise.
struct ExerciseTrendDetailView: View {
    let trend: ExerciseTrend
    let unit: MassUnit

    var body: some View {
        List {
            if loads.count >= 2 {
                Section("Heaviest set (\(unit.rawValue))") {
                    Chart(loads) { point in
                        // `run` breaks the line wherever a session carried no
                        // load at all: each unbroken stretch is its own series,
                        // so absence reads as a gap. It used to plot as 0, which
                        // drew a collapse in strength that never happened.
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Heaviest set", point.value),
                            series: .value("Run", point.run)
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Heaviest set", point.value)
                        )
                    }
                    .frame(height: 200)
                    .padding(.vertical, Spacing.snug)
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
                        } else {
                            Text("\(point.topReps) reps")
                        }
                    }
                    .font(.barbellSupport)
                }
            }
        }
        .navigationTitle(trend.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Only the sessions that carried a load, converted into the display unit,
    /// each tagged with the unbroken run it belongs to.
    ///
    /// This is what was lifted, not what it implies. Sessions with no load —
    /// bodyweight work, a set logged without one — produce no entry at all and
    /// increment `run`, so the chart shows a gap where there is no answer
    /// instead of drawing one.
    private var loads: [ChartPoint] {
        var result: [ChartPoint] = []
        var run = 0
        var previousWasLoaded = false
        for point in trend.points {
            guard let load = point.topLoad else {
                previousWasLoaded = false
                continue
            }
            if !previousWasLoaded && !result.isEmpty { run += 1 }
            previousWasLoaded = true
            result.append(ChartPoint(
                date: point.date,
                value: load.converted(to: unit).value,
                run: run
            ))
        }
        return result
    }
}
