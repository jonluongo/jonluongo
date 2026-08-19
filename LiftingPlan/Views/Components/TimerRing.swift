import SwiftUI

/// A circular countdown ring for the rest timer, with the time in the center.
///
/// **What it does.** Draws elapsed progress as an arc and the time remaining in
/// the middle of it.
///
/// **How it is used.** Give it a fraction, the text to show, and the size the
/// ring should be at ordinary text size. The countdown's type is the caller's
/// (`font`), because the same ring is a 52pt badge in the rest bar and a
/// full-size ring on its own, and those are not the same piece of type.
///
/// **What it depends on.** SwiftUI only — it holds no timer and knows nothing
/// about rest; `RestTimerModel` does the counting.
///
/// The ring scales with the lifter's text size. It used to draw its countdown
/// at `.system(size: size * 0.22)`, which at the bar's 52pt ring is 11.4pt,
/// fixed: the one number a lifter reads from under a loaded bar was the only
/// text in the app that did not answer Dynamic Type, and everything around it
/// grew while it stayed put.
struct TimerRing: View {
    /// 0...1 elapsed fraction.
    var progress: Double
    var timeText: String
    var isRunning: Bool
    /// The ring's diameter at the default text size. It is multiplied by the
    /// lifter's text scale, so the ring and the time inside it grow together.
    var size: CGFloat = 200
    var lineWidth: CGFloat = 14
    var showsLabel: Bool = true
    /// The countdown's type role. Metric by default, which is what a ring drawn
    /// at full size shows.
    var font: Font = .supersetMetric

    /// The lifter's text scale, expressed as a multiplier so the ring's own
    /// geometry can follow the type inside it.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    private var scaledSize: CGFloat { size * textScale }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth * textScale)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isRunning ? Color.accentColor : Color.green,
                    style: StrokeStyle(lineWidth: lineWidth * textScale, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            VStack(spacing: Spacing.tight) {
                Text(timeText)
                    .font(font)
                    .contentTransition(.numericText())
                if showsLabel {
                    Text(isRunning ? "REST" : "READY")
                        .font(.supersetLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            // The ring is a circle: text that outgrows its chord shrinks rather
            // than spilling over the stroke.
            .minimumScaleFactor(0.6)
            .padding(.horizontal, lineWidth * textScale)
        }
        .frame(width: scaledSize, height: scaledSize)
    }
}

#Preview("Timer ring") {
    VStack(spacing: Spacing.major) {
        TimerRing(progress: 0.4, timeText: "2:30", isRunning: true)
        TimerRing(
            progress: 0.4, timeText: "59:59", isRunning: true,
            size: 52, lineWidth: 5, showsLabel: false, font: .supersetSupport
        )
    }
    .padding()
}
