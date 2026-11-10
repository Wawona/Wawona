import SwiftUI
import WawonaModel
#if os(macOS)
import AppKit
#endif

/// After the first-launch welcome Continue on macOS, offer Login Item +
/// compositor/menubar Launch Agents once. Settings → Permissions remains the
/// durable control plane.
struct WelcomeAgentsOfferModifier: ViewModifier {
    @ObservedObject var preferences: WawonaPreferences
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.alert(isPresented: $isPresented) {
            Alert(
                title: Text("Background services"),
                message: Text(
                    "Install the compositor host and menubar agents, and open "
                        + "Wawona at login? You can change this later in "
                        + "Settings → Permissions."
                ),
                primaryButton: .default(Text("Enable")) {
                    var err: NSError?
                    _ = WWNLaunchAgentManager.sharedManager
                        .ensureCompositorAndMenuAgents(&err)
                    _ = WWNLaunchAgentManager.sharedManager.enableAppLaunchAtLogin()
                    markOffered()
                    isPresented = false
                },
                secondaryButton: .cancel(Text("Not Now")) {
                    markOffered()
                    isPresented = false
                }
            )
        }
        #else
        content
        #endif
    }

    private func markOffered() {
        UserDefaults.standard.set(true, forKey: "HasOfferedLaunchAgents")
        preferences.save()
    }
}

extension View {
    func wawonaWelcomeAgentsOffer(
        preferences: WawonaPreferences,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(WelcomeAgentsOfferModifier(
            preferences: preferences,
            isPresented: isPresented
        ))
    }
}
