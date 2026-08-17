import SwiftUI

/// The section header for one exercise on the logging screen: icon, name, what
/// the plan asked for, and the menu.
///
/// **What it does.** Says which exercise the table below it logs, and states
/// the prescription in one line — a count and a rep target when the sets are
/// alike, and only the count when they are not, since the set rows say the rest.
///
/// **How it is used.** `ActiveWorkoutView` puts one above each exercise's
/// section. The menu holds the three things there are to do to an exercise
/// rather than to a set: read what it is, set its clock, and add a warmup.
/// Rest is also editable by tapping the rest line on the card, which is where
/// a lifter looks for it; the menu item exists because an exercise Claude
/// prescribed no rest for has no such line, and a lifter who wants to time
/// himself on it should not be shut out.
///
/// **What it depends on.** `IconCircleRow` for the shape — the plan screen's
/// day row draws the same one, and the two used to be separate code that had
/// drifted six ways — and `PrescriptionSummary` for the words. It lives beside
/// its twin rather than inside the screen that uses it, which is what makes a
/// future divergence visible.
struct ExerciseHeaderView: View {
    let exercise: PlannedExercise
    var onShowInfo: () -> Void
    var onEditRest: () -> Void
    var onAddWarmup: () -> Void

    private var subtitle: String {
        "\(PrescriptionSummary.text(for: exercise))\(exercise.tempo.map { " · tempo \($0)" } ?? "")"
    }

    var body: some View {
        IconCircleRow(
            systemImage: "dumbbell.fill",
            tint: .accentColor,
            title: exercise.displayName,
            subtitle: subtitle
        ) {
            Menu {
                Button { onShowInfo() } label: {
                    Label("About This Exercise", systemImage: "info.circle")
                }
                Button { onEditRest() } label: {
                    Label("Rest Timer", systemImage: "timer")
                }
                Button { onAddWarmup() } label: {
                    Label("Add Warmup Set", systemImage: "flame")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.barbellBody)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("\(exercise.displayName) options")
        }
    }
}
