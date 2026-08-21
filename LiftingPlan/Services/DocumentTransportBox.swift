import Foundation
import LiftingKit

/// The app's transport, in the environment.
///
/// **What it does.** Nothing but hold the one `DocumentTransport` the app was
/// built with, so a screen that has to write a file can reach it.
///
/// **Why a box.** `@Observable` and SwiftUI's environment want a concrete type,
/// and the transport is a protocol existential chosen at launch — the real one
/// on a phone, a folder in a test. Wrapping it is the smallest thing that lets
/// the seam stay a protocol; the alternative is an environment key per method,
/// or a screen holding the concrete `ICloudDocumentTransport`, which would put
/// iCloud in a view.
///
/// **It holds no state and observes nothing**, which is why it is a box rather
/// than a model. `@Observable` is here for the environment's sake alone.
///
/// **What it depends on.** `DocumentTransport` from LiftingKit.
@MainActor
@Observable
final class DocumentTransportBox {

    let value: any DocumentTransport

    init(_ value: any DocumentTransport) {
        self.value = value
    }
}
