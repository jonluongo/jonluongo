import SwiftUI
import SwiftData
import Charts
import LiftingKit

/// One exercise, whole: what the movement is, and what has been lifted on it.
///
/// **What it does.** Draws the catalog's description of the movement — the
/// space its demonstration will occupy, the muscles it trains, what it is
/// performed with, and how to perform it where the catalog says — and then the
/// record: the heaviest set of each session, newest first, and the line those
/// sessions draw. It shows what happened and says nothing about it: there is no
/// arrow and no estimated one-rep max, because which formula turns a set into
/// an estimate is a training opinion and this app holds none.
///
/// **It is one screen and not two.** Information about an exercise and the
/// record of it are the same exercise, and splitting them would give the app two
/// destinations each showing half of one — which is what a session-detail screen
/// and a History tab were doing when both were deleted. What the movement is comes
/// first because it answers the question the name raises; the record follows,
/// and is the longer scroll.
///
/// **How it is used.** Presented as a sheet from an exercise's menu on the
/// logging screen, which is the only way in. It was reached from three places
/// on two screens that no longer exist — this said so for as long as they have
/// been gone, which is what a *how it is used* line costs when nothing checks
/// it.
///
/// **It shares its chrome with the block's information sheet.** Both are an
/// `InfoSheet`: the same surface, the same inline title, the same grabber, and
/// both reached by the same `info` mark. A block and a movement are the same
/// kind of question — *tell me about this* — and were two designs answering it.
///
/// **What it depends on.** `InfoSheet` for that chrome, `ExerciseAboutSections`
/// for the catalog half,
/// `ExerciseTrend` from Services, `TrainingPlan` from Store, `ExerciseID` and
/// `Mass` from Domain, and the injected catalog. It reads and writes nothing.
///
/// The trend is looked up by `exerciseID`, never by name — the same identity
/// rule `PerformanceHistory` enforces, so a renamed or re-generated exercise
/// does not fragment its own history. The catalog entry is looked up by the same
/// id, which is why the demonstration a MoveKit file will fill has a home
/// already.
struct ExerciseDetailView: View {

    let exerciseID: ExerciseID
    /// What to call it at the top. Display only; the record is keyed by id.
    let displayName: String
    /// The user's display unit, so a logged load reads in the unit he reads

    @Environment(\.exerciseCatalog) private var catalog
    /// Every performance there has ever been, newest last.
    ///
    /// **Queried by movement rather than assembled from plans.** It used to walk
    /// every routine collecting sets and regroup them by date, because nothing in
    /// the store sat at the grain the question is asked at. A performance *is*
    /// that grain, so this is a filter — and it reaches a stated baseline too,
    /// which the old path could not, since a baseline was a different table.
    @Query(sort: \PerformedExercise.occurredAt) private var performances: [PerformedExercise]

    /// This movement's history, or empty when it has never been trained.
    private var history: [PerformedExercise] {
        performances.filter { $0.exerciseID == exerciseID }
    }

    var body: some View {
        InfoSheet(displayName) {
            ExerciseAboutSections(entry: catalog.exercise(id: exerciseID))
            if !history.isEmpty {
                chart(history)
                sessions(history)
            } else {
                // A sentence rather than the whole screen: the movement above
                // it is still worth reading on the day nothing has been logged,
                // which is exactly the day someone looks it up.
                Section {
                    SectionHeading("Sessions")
                    Text("Nothing logged yet. Sets you log against this exercise show up here.")
                        .font(.supersetBody)
                        .foregroundStyle(Palette.muted)
                        .panelRow()
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// The line, drawn only where there is a line to draw.
    ///
    /// **One session is not a trend.** A single point plotted on its own axis
    /// reads as a flat line at whatever height it happens to sit, which is the
    /// chart claiming a shape the record does not have. Absence stays absence.
    @ViewBuilder
    private func chart(_ history: [PerformedExercise]) -> some View {
        let points = loads(history)
        if points.count >= 2 {
            Section {
                SectionHeading("Heaviest set")
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
                    // Ink, stated rather than inherited. Unstyled marks take
                    // the app's tint asset, which is near-black in light and
                    // the theme in dark — so the one line on the page changed
                    // what it meant with the appearance. The theme is a fill
                    // and never a line; a plotted series is a line.
                    .foregroundStyle(Palette.ink)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Heaviest set", point.value)
                    )
                    .foregroundStyle(Palette.ink)
                }
                .frame(height: 200)
                .panelRow()
                .listRowSeparator(.hidden)
                .padding(.vertical, Spacing.snug)
            }
        }
    }

    private func sessions(_ history: [PerformedExercise]) -> some View {
        Section {
            SectionHeading("Sessions")
            Panel {
                ForEach(history.reversed(), id: \.persistentModelID) { performed in
                    HStack {
                        Text(performed.occurredAt, format: .dateTime.month().day())
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        // What the set actually was: `185 lb × 8`, `70 lb ×
                        // 40 m`, `45 s`. It read `× 0` for a carry and `0 reps`
                        // for a hold, because reps was the only measure this
                        // row knew how to say.
                        if let top = heaviest(of: performed),
                            let line = LoggedWorkSummary.text(top)
                        {
                            Text(line).foregroundStyle(Palette.ink)
                        }
                    }
                    .font(.supersetSupport)
                }
            }
        }
    }

    /// The heaviest working set of one performance, as a plain value.
    ///
    /// Heaviest rather than last: it is the one figure a user looks for, and
    /// the order sets were performed in does not say which that is. A
    /// performance with no load at all has none, which is an absence and not a
    /// zero.
    private func heaviest(of performed: PerformedExercise) -> SnapshotPerformedSet? {
        PerformanceHistory.value(of: performed).sets
            .filter { !$0.isWarmup }
            .max { ($0.load?.value ?? 0) < ($1.load?.value ?? 0) }
    }

    /// Only the sessions that carried a load, converted into the display unit,
    /// each tagged with the unbroken run it belongs to.
    ///
    /// This is what was lifted, not what it implies. Sessions with no load —
    /// bodyweight work, a set logged without one — produce no entry at all and
    /// increment `run`, so the chart shows a gap where there is no answer
    /// instead of drawing one.
    private func loads(_ history: [PerformedExercise]) -> [ChartPoint] {
        var result: [ChartPoint] = []
        var run = 0
        var previousWasLoaded = false
        for performed in history {
            guard let load = heaviest(of: performed)?.load else {
                previousWasLoaded = false
                continue
            }
            if !previousWasLoaded && !result.isEmpty { run += 1 }
            previousWasLoaded = true
            result.append(ChartPoint(
                date: performed.occurredAt,
                value: load.value,
                run: run
            ))
        }
        return result
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
