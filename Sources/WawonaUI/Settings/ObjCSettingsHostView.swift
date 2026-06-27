import SwiftUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

struct ObjCSettingsHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let prefs = WWNPreferences()
        return UINavigationController(rootViewController: prefs)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#elseif os(macOS)
import AppKit

struct ObjCSettingsHostView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Settings open in native Preferences window.")
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                WWNPreferences.shared().show(NSApp)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            WWNPreferences.shared().show(NSApp)
        }
    }
}

#else
struct ObjCSettingsHostView: View {
    var body: some View {
        Text("Settings unavailable on this platform.")
            .foregroundStyle(.secondary)
    }
}
#endif
