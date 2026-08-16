import Foundation
import Testing
@testable import LiftingPlan

/// What the app is called, and what it must go on being called underneath.
///
/// The two halves of this are not the same kind of fact. The name on the Home
/// Screen is provisional — it is Barbell "for now" — and changing it costs
/// nothing but a build setting. The bundle identifier and the iCloud container
/// are the opposite: the app is installed on a real device with a real snapshot
/// already synced into that container, and renaming either would orphan every
/// file in it and every row behind it. Nothing would fail loudly; the phone
/// would simply start again from empty.
///
/// So this suite asserts the *old* name in two places on purpose. A rename that
/// looks tidy in a diff and quietly abandons the user's data is exactly the
/// change these are here to stop.
@Suite("App identity")
struct AppIdentityTests {

    @Test("The name on the Home Screen is Barbell")
    func displayNameIsBarbell() throws {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String

        #expect(displayName == "Barbell")
    }

    @Test("The bundle identifier did not travel with the name")
    func bundleIdentifierIsUnchanged() {
        // Renaming this makes the installed app a different app: a fresh
        // container, a fresh store, and no way back to what is on the device.
        #expect(Bundle.main.bundleIdentifier == "com.jonluongo.LiftingPlan")
    }

    @Test("The iCloud container did not travel with the name")
    func containerIsUnchanged() {
        // The same identifier is written in LiftingPlan.entitlements and derived
        // by the MCP server to find the shared folder. All three have to agree,
        // and the snapshot already sitting in that folder is why.
        #expect(
            ICloudDocumentTransport.defaultContainerIdentifier
                == "iCloud.com.jonluongo.LiftingPlan")
    }
}
