#if os(watchOS)
import SwiftUI

@main
struct WawonaWatch: App {
    @WKExtensionDelegateAdaptor(WawonaWatchExtensionDelegate.self) private var extensionDelegate

    var body: some Scene {
        WindowGroup {
            WawonaWatchRootView()
        }
    }
}
#endif
