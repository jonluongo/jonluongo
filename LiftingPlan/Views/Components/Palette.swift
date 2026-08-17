import SwiftUI
import UIKit

/// Every colour this app draws, named by the job it does.
///
/// **What it does.** Replaces the system's grouped-list greys — which are what
/// every stock SwiftUI app is made of — with a cool neutral scale of its own,
/// plus the one accent and the one mark that says a set happened. Seven names,
/// and a view asks for the job rather than for a shade.
///
/// **Why cool and not warm.** The app is a record kept precisely: it makes no
/// training decisions, states only what was prescribed and what was performed,
/// and refuses to invent a figure. Warm paper neutrals would dress that up as a
/// notebook, which is a friendlier object than this actually is. The greys here
/// are slightly blue, the way a measuring instrument's are, so the one warm
/// thing on the screen is the accent — and the accent only ever marks something
/// the lifter can act on.
///
/// **How it is used.** `Palette.ink`, `Palette.rule`, and so on. Each resolves
/// against the trait collection, so dark mode is the same seven jobs in darker
/// paint rather than a second design.
///
/// **What it depends on.** SwiftUI and `UIColor`'s dynamic provider. It reads no
/// state and no asset except the accent, which stays in the asset catalog
/// because the system draws it in places this app does not control.
enum Palette {

    /// Behind everything.
    static let surface = dynamic(light: 0xF2F3F5, dark: 0x0F1012)

    /// The ground a table of sets is written on.
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x17181C)

    /// Hairlines. The instrument's ruling — it separates columns and rows
    /// without boxing them, which is what a card does.
    static let rule = dynamic(light: 0xD8DADF, dark: 0x2A2C32)

    /// Text and, above all, numbers.
    static let ink = dynamic(light: 0x15171A, dark: 0xF1F2F4)

    /// Anything qualifying something else: column names, units, the last
    /// session's figures.
    static let muted = dynamic(light: 0x6C7076, dark: 0x8A8F96)

    /// The one thing on screen that is not a neutral. It marks what can be
    /// acted on, and nothing else — see `PrimaryActionButton`.
    static let accent = Color.accentColor

    /// The mark that something is in the record: a ticked set, a logged
    /// session. Cool and dark enough to sit with the neutrals rather than
    /// shouting beside the accent, which is the mistake a full-width slab of
    /// system green made.
    static let recorded = dynamic(light: 0x1F7A4D, dark: 0x35C57F)

    /// The width of a hairline.
    ///
    /// A third of a point, which is one device pixel on the 3× screens this
    /// ships to and sub-pixel on nothing it runs on. It is stated rather than
    /// read from the screen: `UIScreen.main` is deprecated and main-actor bound,
    /// and a rule that has to touch the actor to know its own width is a rule
    /// that cannot be drawn from a `let`.
    static let hairline: CGFloat = 1.0 / 3.0

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {

    /// A colour from `0xRRGGBB`. Confined to `Palette`, which is the only place
    /// in the app allowed to name one.
    fileprivate convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
