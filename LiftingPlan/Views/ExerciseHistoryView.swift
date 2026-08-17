import SwiftUI
import SwiftData
import Charts
import LiftingKit

/// One exercise's record: every session it has been logged in, and the line
/// those sessions draw.
///
/// **What it does.** Shows what was actually lifted — the heaviest set of each
/// session, newest first, and a chart of the same over time. It shows what
/// happened and says nothing about it: there is no arrow and no estimated
/// one-rep max, because which formula turns a set into an estimate is a training
/// opinion and this app holds none.
///
/// **How it is used.** Pushed from a prescribed exercise row, on Today and on a
/// week inside the Plan tab. It replaced a History tab that listed every logged
/// exercise and then made you tap one: a lifter reading *Barbell Bench Press*
/// and wondering what he benched last month is already looking at the row that
/// answers him, so the answer moved onto the row and the filing cabinet went.
///
/// **What it depends on.** `ExerciseTrend` from Services, `TrainingPlan` from
/// Store, `ExerciseID` and `Mass` from Domain. It reads the store and writes
/// nothing.
///
/// The trend is looked up by `exerciseID`, never by name — the same identity
/// rule `PerformanceHistory` enforces, so a renamed or re-generated exercise
/// does not fragment its own history.
struct ExerciseHistoryView: View {

    let exerciseID: ExerciseID
    /// What to call it at the top. Display only; the record is keyed by id.
    let displayName: String
    /// The lifter's display unit, so a logged load reads in the unit he reads
    /// everything else in.
    let unit: MassUnit

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// This exercise's sessions, or `nil` when nothing has been logged against
    /// it. Built from every plan rather than the one it was opened from: the
    /// record is the lift's, not the block's.
    private var trend: ExerciseTrend? {
        ExerciseTrend.build(from: plans).first { $0.exerciseID == exerciseID }
    }

    var body: some View {
        Group {
            if let trend {
                List {
                    chart(trend)
                    sessions(trend)
                }
            } else {
                ContentUnavailableView {
                    Label("Nothing logged yet", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Sets you log against this exercise show up here.")
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The line, drawn only where there is a line to draw.
    ///
    /// **One session is not a trend.** A single point plotted on its own axis
    /// reads as a flat line at whatever height it happens to sit, which is the
    /// chart claiming a shape the record does not have. Absence stays absence.
    @ViewBuilder
    private func chart(_ trend: ExerciseTrend) -> some View {
        let points = loads(trend)
        if points.count >= 2 {
            Section("Heaviest set (\(unit.rawValue))") {
                Chart(points) { point in
                    // `run` breaks the line wherever a session carried no load
                    // at all: each unbroken stretch is its own series, so
                    // absence reads as a gap. It used to plot as 0, which drew
                    // a collapse in strength that never happened.
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
    }

    private func sessions(_ trend: ExerciseTrend) -> some View {
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

    /// Only the sessions that carried a load, converted into the display unit,
    /// each tagged with the unbroken run it belongs to.
    ///
    /// This is what was lifted, not what it implies. Sessions with no load —
    /// bodyweight work, a set logged without one — produce no entry at all and
    /// increment `run`, so the chart shows a gap where there is no answer
    /// instead of drawing one.
    private func loads(_ trend: ExerciseTrend) -> [ChartPoint] {
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

/// A prescribed exercise, and the way into what it has been lifted with.
///
/// **What it does.** Draws `PrescribedExerciseRow` and pushes
/// `ExerciseHistoryView` when it is tapped. It exists so the two screens that
/// list prescribed exercises — Today's session and a week inside Plan — open
/// the record the same way and say the same thing about it to VoiceOver.
///
/// **What it depends on.** `PrescribedExerciseRow`, `PlannedExercise` from
/// Store, `MassUnit` from Domain. It must be inside a `NavigationStack`.
struct ExerciseHistoryLink: View {

    let exercise: PlannedExercise
    let unit: MassUnit

    var body: some View {
        NavigationLink {
            ExerciseHistoryView(
                exerciseID: exercise.exerciseID,
                displayName: exercise.displayName,
                unit: unit
            )
        } label: {
            PrescribedExerciseRow(exercise: exercise, unit: unit)
        }
        .accessibilityHint("Shows what you have lifted on this exercise")
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
