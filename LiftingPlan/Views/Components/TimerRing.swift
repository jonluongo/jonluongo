import SwiftUI

/// A circular countdown ring for the rest timer, with the time in the center.
struct TimerRing: View {
    /// 0...1 elapsed fraction.
    var progress: Double
    var timeText: String
    var isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isRunning ? Color.accentColor : Color.green,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            VStack(spacing: 2) {
                Text(timeText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(isRunning ? "REST" : "READY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
    }
}
