#if os(iOS)
import SwiftUI
import UIKit

/// iPhone iOS 26 search placement.
///
/// `DefaultToolbarItem(kind: .search)` inside `NavigationSplitView` vends
/// `searchBarPlacementBarButtonItem` from a bridge `UINavigationItem`. UIKit
/// ignores that button when it does not match the visible controller's
/// navigation item, then SwiftUI inserts a `UIKitToolbar` under
/// `UIHostingController.view` at full width and zero height.
///
/// The system button has to come from the visible controller's own
/// `navigationItem` and live in that controller's `toolbarItems`.
@available(iOS 26.0, *)
struct WWNPhoneIntegratedSearchToolbar: UIViewRepresentable {
    enum Placement {
        case bottomBar(showsCompose: Bool)
        case navigationBarStacked
    }

    var placement: Placement
    var onCompose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompose: onCompose)
    }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: Anchor, context: Context) {
        context.coordinator.placement = placement
        context.coordinator.onCompose = onCompose
        uiView.coordinator = context.coordinator
        context.coordinator.repair(from: uiView)
    }

    static func dismantleUIView(_ uiView: Anchor, coordinator: Coordinator) {
        coordinator.releaseToolbar(from: uiView)
    }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.repair(from: self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            coordinator?.repair(from: self)
        }
    }

    final class Coordinator: NSObject {
        var placement: Placement = .bottomBar(showsCompose: true)
        var onCompose: () -> Void
        private let composeItem: UIBarButtonItem
        private let flexibleSpace = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )
        private weak var cachedController: UISearchController?
        private var cachedPlacementButton: UIBarButtonItem?
        private weak var installedOwner: UIViewController?

        init(onCompose: @escaping () -> Void) {
            self.onCompose = onCompose
            let item = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .prominent,
                target: nil,
                action: nil
            )
            item.accessibilityLabel = "Add Machine"
            item.accessibilityIdentifier = WWNA11y.machinesAdd
            composeItem = item
            super.init()
            item.target = self
            item.action = #selector(composeTapped)
        }

        @objc private func composeTapped() {
            onCompose()
        }

        func repair(from anchor: Anchor) {
            stripRejectedToolbars(from: anchor)
            guard let owner = searchOwner(from: anchor) else { return }
            let item = owner.navigationItem
            switch placement {
            case .navigationBarStacked:
                if item.preferredSearchBarPlacement != .stacked {
                    item.preferredSearchBarPlacement = .stacked
                }
                if item.searchBarPlacementAllowsToolbarIntegration {
                    item.searchBarPlacementAllowsToolbarIntegration = false
                }
                if owner.toolbarItems?.isEmpty == false {
                    owner.toolbarItems = []
                }
                owner.navigationController?.setToolbarHidden(true, animated: false)
                installedOwner = nil
            case .bottomBar(let showsCompose):
                if item.preferredSearchBarPlacement != .integrated {
                    item.preferredSearchBarPlacement = .integrated
                }
                if !item.searchBarPlacementAllowsToolbarIntegration {
                    item.searchBarPlacementAllowsToolbarIntegration = true
                }
                guard let controller = item.searchController else { return }
                if cachedController !== controller {
                    cachedController = controller
                    cachedPlacementButton = item.searchBarPlacementBarButtonItem
                }
                guard let placementButton = cachedPlacementButton else { return }
                let desired: [UIBarButtonItem]
                if showsCompose {
                    desired = [placementButton, flexibleSpace, composeItem]
                } else {
                    desired = [placementButton]
                }
                if !sameItems(owner.toolbarItems, desired) {
                    owner.toolbarItems = desired
                }
                if owner.navigationController?.isToolbarHidden != false {
                    owner.navigationController?.setToolbarHidden(false, animated: false)
                }
                installedOwner = owner
            }
        }

        func releaseToolbar(from anchor: Anchor) {
            let owner = installedOwner ?? searchOwner(from: anchor)
            guard let owner else { return }
            guard ownsToolbar(owner.toolbarItems) else { return }
            owner.toolbarItems = []
            owner.navigationController?.setToolbarHidden(true, animated: false)
            installedOwner = nil
        }

        private func ownsToolbar(_ items: [UIBarButtonItem]?) -> Bool {
            guard let items, !items.isEmpty else { return false }
            return items.allSatisfy { item in
                item === composeItem || item === flexibleSpace || item === cachedPlacementButton
            }
        }

        private func sameItems(_ current: [UIBarButtonItem]?, _ desired: [UIBarButtonItem]) -> Bool {
            guard let current, current.count == desired.count else { return false }
            return zip(current, desired).allSatisfy { $0 === $1 }
        }

        private func searchOwner(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let next = responder?.next {
                if let controller = next as? UIViewController,
                   controller.navigationItem.searchController != nil {
                    return controller
                }
                responder = next
            }
            return nil
        }

        private func stripRejectedToolbars(from anchor: UIView) {
            guard let host = hostingView(from: anchor) else { return }
            for subview in host.subviews {
                let name = NSStringFromClass(type(of: subview))
                let rejectedName = name.contains("UIKitToolbar")
                let flatBar = subview is UIToolbar && subview.bounds.height < 1
                if rejectedName || flatBar {
                    subview.removeFromSuperview()
                }
            }
        }

        private func hostingView(from view: UIView) -> UIView? {
            var responder: UIResponder? = view
            var host: UIView?
            while let next = responder?.next {
                if let controller = next as? UIViewController {
                    let name = NSStringFromClass(type(of: controller))
                    if name.contains("UIHostingController") {
                        host = controller.view
                    }
                }
                responder = next
            }
            return host
        }
    }
}
#endif
