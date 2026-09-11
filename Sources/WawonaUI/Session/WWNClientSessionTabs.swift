#if !SWIFT_PACKAGE && (os(iOS) || os(tvOS) || os(visionOS))
import SwiftUI
import UIKit

/// One Wayland toplevel shown as a Safari-style tab card.
@objc(WWNClientTabItem)
public final class WWNClientTabItem: NSObject, Identifiable {
    @objc public var id: UInt64
    @objc public var title: String
    @objc public var preview: UIImage?

    @objc public init(id: UInt64, title: String, preview: UIImage? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
    }
}

final class WWNClientTabChromeModel: ObservableObject {
    @Published var tabs: [WWNClientTabItem] = []
    @Published var selectedId: UInt64 = 0
    @Published var overviewOpen = false
    var onSelect: ((UInt64) -> Void)?
    var onClose: ((UInt64) -> Void)?

    func select(_ id: UInt64) {
        selectedId = id
        overviewOpen = false
        onSelect?(id)
    }

    func close(_ id: UInt64) {
        onClose?(id)
    }
}

/// Pass-through plate: empty areas return nil so Mode B HID / compositor get
/// the hit. Interactive SwiftUI controls still receive taps.
final class WWNClientTabPassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else {
            return nil
        }
        return hit === self ? nil : hit
    }
}

/// Full-screen host: only interactive descendants take hits. The compositor
/// / Mode B HID overlay keep the rest (doc: pass-through overlay).
final class WWNClientTabHostingController: UIHostingController<WWNClientSessionTabBar> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }
}

/// Safari-style tab overview: `square.on.square`, client previews, swipe up
/// to close. Phone + tvOS in-window only. iPad / visionOS keep dedicated scenes.
struct WWNClientSessionTabBar: View {
    @ObservedObject var model: WWNClientTabChromeModel

    var body: some View {
        // Phone soft-key accessory owns bottomTrailing. Put the Safari tab
        // control at topTrailing so two live clients always expose a switcher.
        // tvOS keeps bottomTrailing (no soft-key row).
        ZStack(alignment: tabButtonAlignment) {
            Color.clear
                .allowsHitTesting(false)
            if model.overviewOpen {
                overview
            }
            // Only meaningful with 2+ clients (SceneDelegate hides otherwise).
            if model.tabs.count >= 2 {
                safariTabButton
                    .padding(.trailing, 16)
                    .padding(tabButtonEdgePadding, 18)
#if !os(tvOS)
                    .safeAreaPadding(.top, 8)
#else
                    .padding(.top, tabButtonExtraTop)
#endif
            }
        }
        .accessibilityIdentifier("wwn.client.tabs")
    }

    private var tabButtonExtraTop: CGFloat {
#if os(tvOS)
        0
#else
        4
#endif
    }

    private var tabButtonAlignment: Alignment {
#if os(tvOS)
        .bottomTrailing
#else
        .topTrailing
#endif
    }

    private var tabButtonEdgePadding: Edge.Set {
#if os(tvOS)
        .bottom
#else
        .top
#endif
    }

    private var safariTabButton: some View {
        Button {
            withAnimation(.snappy) {
                model.overviewOpen.toggle()
            }
        } label: {
            ZStack {
                Image(systemName: "square.on.square")
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tabCountLabel)
                    .font(.caption2.weight(.bold))
                    .offset(y: 1)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .accessibilityLabel("Tabs, \(model.tabs.count)")
        .accessibilityIdentifier("wwn.client.tabs.overview")
        .modifier(WWNClientTabGlassButton())
    }

    private var tabCountLabel: String {
        model.tabs.count > 99 ? "99+" : "\(model.tabs.count)"
    }

    private var overview: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.snappy) {
                        model.overviewOpen = false
                    }
                }
            VStack(spacing: 12) {
                HStack {
                    Text("Tabs")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        withAnimation(.snappy) {
                            model.overviewOpen = false
                        }
                    }
                    .modifier(WWNClientTabGlassButton())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.tabs) { tab in
                            WWNClientSafariTabCard(
                                tab: tab,
                                selected: tab.id == model.selectedId,
                                onSelect: { model.select(tab.id) },
                                onClose: { model.close(tab.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88)
                }
            }
        }
        .transition(.opacity)
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }
}

private struct WWNClientSafariTabCard: View {
    let tab: WWNClientTabItem
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var dragY: CGFloat = 0
    @State private var closing = false

    private var title: String {
        tab.title.isEmpty ? "Untitled" : tab.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                preview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button(action: closeNow) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .modifier(WWNClientTabGlassButton())
                .padding(8)
                .accessibilityLabel("Close \(title)")
                .accessibilityIdentifier("wwn.client.tab.close.\(tab.id)")
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .padding(8)
        .modifier(WWNClientTabCardChrome(selected: selected))
        .offset(y: dragY)
        .opacity(closing ? 0 : max(0.25, 1 + dragY / 220))
        .scaleEffect(closing ? 0.86 : 1)
        .gesture(swipeToClose)
        .onTapGesture(perform: onSelect)
        .accessibilityIdentifier("wwn.client.tab.\(tab.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        if let preview = tab.preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: "macwindow")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var swipeToClose: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if value.translation.height < 0 {
                    dragY = value.translation.height
                }
            }
            .onEnded { value in
                let shouldClose =
                    value.translation.height < -80 || value.predictedEndTranslation.height < -140
                if shouldClose {
                    closeNow()
                } else {
                    withAnimation(.spring(duration: 0.28)) {
                        dragY = 0
                    }
                }
            }
    }

    private func closeNow() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: 0.18)) {
            dragY = -260
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            onClose()
        }
    }
}

private struct WWNClientTabCardChrome: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.tint, lineWidth: 2)
                    }
                }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.tint, lineWidth: 2)
                    }
                }
        }
    }
}

private struct WWNClientTabGlassButton: ViewModifier {
    func body(content: Content) -> some View {
#if os(visionOS)
        content.buttonStyle(.bordered)
#else
        if #available(iOS 26.0, tvOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
#endif
    }
}

/// ObjC host for SceneDelegate. Full-screen pass-through; button + overview
/// receive hits. Compositor keeps the rest.
@objc(WWNClientTabChromeController)
public final class WWNClientTabChromeController: NSObject {
    private let model = WWNClientTabChromeModel()
    private var host: WWNClientTabHostingController?
    private var passThrough: WWNClientTabPassThroughView?

    @objc public var onSelectId: ((UInt64) -> Void)?
    @objc public var onCloseId: ((UInt64) -> Void)?

    @objc public var hostView: UIView? { passThrough ?? host?.view }

    @objc public func attach(to parentView: UIView) {
        if let existing = passThrough {
            if existing.superview !== parentView {
                existing.removeFromSuperview()
                parentView.addSubview(existing)
                NSLayoutConstraint.activate([
                    existing.topAnchor.constraint(equalTo: parentView.topAnchor),
                    existing.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                    existing.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                    existing.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
                ])
            }
            parentView.bringSubviewToFront(existing)
            return
        }
        model.onSelect = { [weak self] id in self?.onSelectId?(id) }
        model.onClose = { [weak self] id in self?.onCloseId?(id) }
        let hc = WWNClientTabHostingController(rootView: WWNClientSessionTabBar(model: model))
        hc.view.backgroundColor = .clear
        hc.view.isOpaque = false
        hc.view.clipsToBounds = false
        hc.view.isUserInteractionEnabled = true
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        let plate = WWNClientTabPassThroughView()
        plate.backgroundColor = .clear
        plate.isOpaque = false
        plate.clipsToBounds = false
        plate.isUserInteractionEnabled = true
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: plate.topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: plate.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            hc.view.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])
        parentView.addSubview(plate)
        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: parentView.topAnchor),
            plate.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
            plate.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
        ])
        host = hc
        passThrough = plate
    }

    @objc public func setHidden(_ hidden: Bool) {
        if hidden {
            model.overviewOpen = false
        }
        passThrough?.isHidden = hidden
        host?.view.isHidden = hidden
    }

    @objc public var isAttached: Bool { passThrough != nil || host != nil }

    @objc public var selectedId: UInt64 { model.selectedId }

    @objc public func reload(
        ids: [NSNumber],
        titles: [String],
        selectedId: NSNumber
    ) {
        reload(ids: ids, titles: titles, selectedId: selectedId, previewImages: [:])
    }

    @objc public func reload(
        ids: [NSNumber],
        titles: [String],
        selectedId: NSNumber,
        previewImages: [NSNumber: UIImage]
    ) {
        var previous: [UInt64: UIImage] = [:]
        for tab in model.tabs {
            if let img = tab.preview {
                previous[tab.id] = img
            }
        }
        var items: [WWNClientTabItem] = []
        items.reserveCapacity(ids.count)
        for (index, idNum) in ids.enumerated() {
            let title = index < titles.count ? titles[index] : "Untitled"
            let preview = previewImages[idNum] ?? previous[idNum.uint64Value]
            items.append(WWNClientTabItem(id: idNum.uint64Value, title: title, preview: preview))
        }
        model.tabs = items
        model.selectedId = selectedId.uint64Value
        if items.isEmpty {
            model.overviewOpen = false
        }
        if let plate = passThrough {
            plate.superview?.bringSubviewToFront(plate)
        } else {
            host?.view.superview?.bringSubviewToFront(host!.view)
        }
    }
}
#endif
