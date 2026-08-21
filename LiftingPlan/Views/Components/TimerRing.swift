import SwiftUI

/// A circular countdown ring for the rest timer, with the time in the center.
///
/// **What it does.** Draws elapsed progress as an arc and the time remaining in
/// the middle of it.
///
/// **How it is used.** Give it a fraction, the text to show, and the size the
/// ring should be at ordinary text size. It draws the figure and the arc; what
/// the rest *is* — *Resting*, the movement, the controls — belongs to the
/// caller, which is why nothing but the time is inside the circle. The countdown's type is the caller's
/// (`font`), because the same ring is a 52pt badge in the rest bar and a
/// full-size ring on its own, and those are not the same piece of type.
///
/// **What it depends on.** SwiftUI only — it holds no timer and knows nothing
/// about rest; `RestTimerModel` does the counting.
///
/// The ring scales with the user's text size. It used to draw its countdown
/// at `.system(size: size * 0.22)`, which at the bar's 52pt ring is 11.4pt,
/// fixed: the one number a user reads from under a loaded bar was the only
/// text in the app that did not answer Dynamic Type, and everything around it
/// grew while it stayed put.
struct TimerRing: View {
    /// 0...1 elapsed fraction.
    var progress: Double
    var timeText: String
    var isRunning: Bool
    /// Whether the rest has run out. **A whole ring reading `0:00`**, rather
    /// than the empty ring a countdown drains to: an empty circle reads as *not
    /// started*, which is the opposite of what has happened. The figure stays a
    /// figure — this is a clock in both states, and a clock that has run out
    /// says zero.
    var isComplete: Bool = false
    /// The ring's diameter at the default text size. It is multiplied by the
    /// user's text scale, so the ring and the time inside it grow together.
    var size: CGFloat = 200
    var lineWidth: CGFloat = 14
    /// The countdown's type role. Metric by default, which is what a ring drawn
    /// at full size shows.
    var font: Font = .supersetMetric

    /// The user's text scale, expressed as a multiplier so the ring's own
    /// geometry can follow the type inside it.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    private var scaledSize: CGFloat { size * textScale }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.rule, lineWidth: lineWidth * textScale)
            // **It drains rather than fills.** `progress` is how much of the
            // rest has gone, so drawing it directly starts the countdown as an
            // empty ring and finishes it whole — fullest at the moment it stops
            // mattering. A rest is a thing running out, and the ring says so.
            Circle()
                .trim(from: 0, to: isComplete ? 1 : 1 - progress)
                .stroke(
                    // Running is the app pointing at something; ready is not,
                    // and a second hue for it would be the only other colour on
                    // the screen saying nothing the word beneath it does not.
                    // Ink when it is running or finished — both are the app
                    // pointing at something. **Not the accent**, which means
                    // *in the record*: a rest that ran out is not a set that
                    // was logged, and one mark meaning two things means neither.
                    isRunning || isComplete ? Palette.ink : Palette.muted,
                    style: StrokeStyle(lineWidth: lineWidth * textScale, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            // **The finished ring reads `0:00`, not a tick.** A check was
            // tried here twice — as an SF Symbol, which no weight could match to
            // a five-point stroke, and then as a path stroked at the ring's own
            // width, which matched exactly and was still the wrong thing. On
            // Jon's call the ring is a clock in both states, and a clock that
            // has run out says zero. `formattedRemaining` already does.
            //
            // The time, and nothing else. It carried a `REST`/`READY` word
            // under the figure behind a `showsLabel` flag that all three call
            // sites passed `false` — the bar says *Resting* in its own words
            // beside the ring, and the sheet has the session behind it. A
            // parameter with one possible value is not a choice, and the word
            // it guarded had not been drawn on a screen in this app for as long
            // as every caller has been passing `false`.
            Text(timeText)
                .font(font)
                .contentTransition(.numericText())
                .lineLimit(1)
                // The ring is a circle: text that outgrows its chord shrinks
                // rather than spilling over the stroke.
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
            size: 52, lineWidth: 5, font: .supersetSupport
        )
        TimerRing(
            progress: 1, timeText: "0:00", isRunning: false, isComplete: true,
            size: 52, lineWidth: 5, font: .supersetSupport
        )
    }
    .padding()
}
