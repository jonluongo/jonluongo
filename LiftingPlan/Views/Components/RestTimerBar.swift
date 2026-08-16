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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = restTimer.errorMessage {
                Button { restTimer.dismissError() } label: {
                    Label(errorMessage, systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)
            }
            controls
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: 14) {
            TimerRing(
                progress: restTimer.progress,
                timeText: restTimer.formattedRemaining,
                isRunning: restTimer.isRunning,
                size: 52,
                lineWidth: 5,
                showsLabel: false
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Resting")
                    .font(.subheadline.weight(.semibold))
                if !restTimer.contextLabel.isEmpty {
                    Text(restTimer.contextLabel)
                        .font(.caption)
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
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}
