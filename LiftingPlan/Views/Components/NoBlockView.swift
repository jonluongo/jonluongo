import SwiftUI

/// What both block-shaped screens show when there is no block.
///
/// **What it does.** States the absence and who fills it. The app never writes a
/// plan for itself, so the only true next step is asking the coach for one.
///
/// **How it is used.** Today draws it when nothing can be placed against a
/// calendar; the Plans tab draws it when the record holds no plan at all. It is one view
/// rather than two so the two tabs cannot come to describe the same absence
/// differently.
///
/// **What it depends on.** Nothing but SwiftUI.
struct NoBlockView: View {

    var body: some View {
        ContentUnavailableView {
            Label("No block yet", systemImage: "dumbbell")
        } description: {
            Text("Ask Claude for one.")
        }
    }
}

#Preview("No block") {
    NoBlockView()
}
