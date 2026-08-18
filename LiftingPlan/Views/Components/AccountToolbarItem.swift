import SwiftUI

/// The way to the account record, on the two screens that list things.
///
/// **What it does.** Puts one icon in the top right that opens the record Claude
/// keeps. It is a sheet because the account is a thing looked at and left, not a
/// place in the block's hierarchy.
///
/// **It is not on the session.** The workout screen is what the app is for and
/// carries nothing that is not the workout; the account is something read
/// between sessions.
///
/// **What it depends on.** `AccountView` and `UserProfile`.
struct AccountToolbarItem: ToolbarContent {

    let profile: UserProfile

    @State private var showing = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showing = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Account")
            .sheet(isPresented: $showing) {
                NavigationStack { AccountView(profile: profile) }
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
