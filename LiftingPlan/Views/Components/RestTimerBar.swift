import SwiftUI

/// A compact, floating rest-timer bar shown at the bottom while resting.
/// Minimal: a small ring, the context, and ±15 / skip controls.
///
/// It also carries the one thing the timer can fail at: if the screen-locked
/// cue could not be armed, the reason is shown here rather than logged and
/// forgotten. Tapping it dismisses it. An alert would be wrong — this is mid-set
/// and the countdown itself is working fine — but silence would be worse, since
/// the whole point of the notification is that the lifter is not looking.
struct RestTimerBar: View {
    var restTimer: RestTimerModel

    /// How far the bar sits from the edge of the screen.
    private static let barInset = Spacing.standard
    /// How far the bar's contents sit from the edge of the bar.
    private static let contentInset = Spacing.standard

    /// The error label sits above the bar and has to line up with what is
    /// inside it, so its inset is the sum of the two above rather than a
    /// hand-added total. It was written as `26`, which was `12 + 14` worked out
    /// once by hand: changing either of the two paddings moved the ring and
    /// left the label behind, with nothing to catch it.
    private static var errorInset: CGFloat { barInset + contentInset }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            if let errorMessage = restTimer.errorMessage {
                Button { restTimer.dismissError() } label: {
                    Label(errorMessage, systemImage: "bell.slash")
                        .font(.supersetSupport)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Self.errorInset)
            }
            controls
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: Spacing.standard) {
            TimerRing(
                progress: restTimer.progress,
                timeText: restTimer.formattedRemaining,
                isRunning: restTimer.isRunning,
                size: 52,
                lineWidth: 5,
                showsLabel: false,
                // Support rather than Metric: the countdown has to fit inside a
                // 52pt ring, and "59:59" at Metric does not. Raising it is the
                // logging screen's own work, which is where the bar's shape is
                // decided; what matters here is that it is a text style at all,
                // so it grows when the lifter's type does.
                font: .supersetSupport
            )

            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("Resting")
                    .font(.supersetTitle)
                if !restTimer.contextLabel.isEmpty {
                    Text(restTimer.contextLabel)
                        .font(.supersetSupport)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("−15") { restTimer.addTime(-15) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

            Button("+15") { restTimer.addTime(15) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

            Button {
                restTimer.skip()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .font(.supersetSupport)
        .padding(.horizontal, Self.contentInset)
        .padding(.vertical, Spacing.snug)
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, Self.barInset)
        .padding(.bottom, Spacing.tight)
    }
}
