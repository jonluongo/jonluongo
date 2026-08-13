import SwiftUI

/// A circular countdown ring for the rest timer, with the time in the center.
struct TimerRing: View {
    /// 0...1 elapsed fraction.
    var progress: Double
    var timeText: String
    var isRunning: Bool
    var size: CGFloat = 200
    var lineWidth: CGFloat = 14
    var showsLabel: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isRunning ? Color.accentColor : Color.green,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            VStack(spacing: 2) {
                Text(timeText)
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if showsLabel {
                    Text(isRunning ? "REST" : "READY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
