#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted by `WWNShakeWindow` / compositor host when the device shakes.
    static let wwnDeviceDidShake = Notification.Name("WWNDeviceDidShakeNotification")
    /// Append a line to the Start / client Terminal sheet.
    static let wwnClientLaunchLog = Notification.Name("WWNClientLaunchLogNotification")
}

/// Edge swipe from the leading edge opens the Machines sidebar while a
/// Wayland session fills the detail. Shake parks when enabled.
struct WWNSessionSurfaceGestureModifier: ViewModifier {
    @Binding var showSidebar: Bool
    let sessionVisible: Bool
    let onShakePark: () -> Void

    func body(content: Content) -> some View {
        // ZStack (not overlay(alignment:)) for iOS 13 floor.
        ZStack(alignment: .leading) {
            content
            if sessionVisible {
                Color.clear
                    .frame(width: 28)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = abs(value.translation.height)
                                // Leading-edge swipe toward center (finger moves right).
                                if dx > 48, dx > dy * 1.15 {
                                    withAnimation {
                                        showSidebar = true
                                    }
                                }
                            }
                    )
                    .accessibility(hidden: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wwnDeviceDidShake)) { _ in
            guard sessionVisible else { return }
            guard WWNMachineProfileStore.resolvedShakeToCloseActive() else { return }
            onShakePark()
        }
    }
}

/// Safe-area policy for the in-window Metal host.
struct WWNSessionSafeAreaModifier: ViewModifier {
    let respectSafeArea: Bool
    let sessionVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if sessionVisible, !respectSafeArea {
            if #available(iOS 14.0, visionOS 1.0, *) {
                content.ignoresSafeArea(.container, edges: .all)
            } else {
                content.edgesIgnoringSafeArea(.all)
            }
        } else {
            content
        }
    }
}

/// Hide NavigationSplitView / detail toolbar while Wayland fills the phone.
struct WWNSessionHideToolbarWhenVisible: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            if #available(iOS 17.0, *) {
                content
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(removing: .sidebarToggle)
            } else if #available(iOS 16.0, *) {
                content.toolbar(.hidden, for: .navigationBar)
            } else {
                content.navigationBarHidden(true)
            }
        } else {
            content
        }
    }
}

/// Status bar: hide when compositor is fullscreen (Respect Safe Area off).
struct WWNSessionStatusBarModifier: ViewModifier {
    let hideStatusBar: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 14.0, *) {
            content.statusBarHidden(hideStatusBar)
        } else {
            content
        }
    }
}
#endif
