import SwiftUI
import LiftingKit

/// A group as it reads before it is trained: what it is, how long to rest after
/// each round, and the movements it holds, each opening its own record.
///
/// **What it does.** States the plan for a superset, a tri-set or a giant set
/// and nothing else. The heading says which group it is and how many rounds it
/// runs, the rest line says what follows each round — absent when the plan
/// prescribed none, since a group that asks for no rest shows none rather than
/// `0s` — and then the movements, prefixed `A1`, `A2`, exactly as they read on a
/// written program.
///
/// **How it is used.** The Today session and a week inside Plan draw one per
/// grouped entry, where they draw an `ExerciseDetailLink` per ungrouped one. It
/// is rows rather than a container so it sits inside the same `Section` those
/// screens already build, and so each movement is still its own list row with
/// its own tap target.
///
/// **What it depends on.** `ExerciseGroup` from Services, `ExerciseDetailLink`
/// for the movements — the same row the ungrouped case pushes — and
/// `RestPrescription` for the rest. It writes nothing.
struct PrescribedGroupRows: View {

    let group: ExerciseGroup
    /// The lifter's display unit, carried down to the prescriptions.
    let unit: MassUnit

    private var shape: String {
        let rounds = group.prescribedRounds
        let rest = group.restSeconds.map { " · \(RestPrescription.durationText($0)) after each round" }
        return "\(rounds) round\(rounds == 1 ? "" : "s")\(rest ?? "")"
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(group.title)
                    .font(.barbellTitle)
                Text(shape)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.tight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.title), \(shape)")

            ForEach(group.members) { member in
                ExerciseDetailLink(
                    exercise: member, unit: unit, notation: group.notation(for: member))
            }
        }
    }
}

