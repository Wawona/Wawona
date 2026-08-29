#if os(watchOS)
import SpriteKit
import SwiftUI
import UIKit

// Track A present path. GPU-composites Wayland SHM frames via SpriteKit.
// Never import Metal. Never SKShader. Clients stay software.

/// One SKScene + SKSpriteNode, reused every frame. Do not wrap this in `.id`
/// per commit; that would rebuild SpriteView.
final class WatchSpritePresentScene: SKScene {
    private let sprite = SKSpriteNode()

    override func sceneDidLoad() {
        super.sceneDidLoad()
        backgroundColor = .black
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        if sprite.parent == nil {
            addChild(sprite)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutSprite()
    }

    func applyFrame(_ image: CGImage) {
        if size.width < 1 || size.height < 1 {
            size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        }
        let uiImage = UIImage(cgImage: image)
        let texture = SKTexture(image: uiImage)
        texture.filteringMode = .linear
        sprite.texture = texture
        layoutSprite()
    }

    private func layoutSprite() {
        guard let texture = sprite.texture else { return }
        let ts = texture.size()
        let ss = size
        guard ts.width > 0, ts.height > 0, ss.width > 0, ss.height > 0 else {
            return
        }
        // OWL Client authority: 1:1 buffer pixels, centered. Never upscale a
        // preferred square (simple-shm 250², flower/smoke 200²). Scale down
        // only when the commit is larger than the watch scene.
        let fit = min(ss.width / ts.width, ss.height / ts.height)
        let scale = min(fit, CGFloat(1))
        sprite.size = CGSize(width: ts.width * scale, height: ts.height * scale)
        sprite.position = .zero
    }
}

final class WatchSpritePresenter: ObservableObject {
    let scene: WatchSpritePresentScene

    init() {
        let scene = WatchSpritePresentScene(size: CGSize(width: 400, height: 400))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .black
        self.scene = scene
    }

    func apply(_ image: CGImage) {
        scene.applyFrame(image)
    }

    func setPaused(_ paused: Bool) {
        scene.isPaused = paused
    }
}

/// SpriteKit host for the mini compositor surface. Accessibility id matches
/// the previous SwiftUI `Image` path.
struct WatchSpritePresentView: View {
    var onFirstFrame: (() -> Void)? = nil
    @StateObject private var presenter = WatchSpritePresenter()
    @State private var hasFrame = false
    @State private var didNotifyFirstFrame = false
    @Environment(\.scenePhase) private var scenePhase

    private var shouldRun: Bool { scenePhase != .background }

    var body: some View {
        ZStack {
            SpriteView(
                scene: presenter.scene,
                isPaused: false,
                preferredFramesPerSecond: 30
            )
            .ignoresSafeArea()
            if !hasFrame && onFirstFrame == nil {
                Text("Waiting for surface…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier("wwn.watch.compositorSurface")
        .accessibilityLabel("Wayland Surface")
        .onAppear {
            presenter.setPaused(!shouldRun)
            applyLatestFrame()
            DispatchQueue.main.async {
                applyLatestFrame()
            }
        }
        .onDisappear {
            presenter.setPaused(true)
        }
        .onChange(of: scenePhase) { _, _ in
            presenter.setPaused(!shouldRun)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WWNWatchCompositorFrameReadyNotification")
        )) { _ in
            applyLatestFrame()
        }
    }

    private func applyLatestFrame() {
        guard let image = WWNWatchCompositorBridge.shared().latestFrame else {
            return
        }
        presenter.apply(image)
        hasFrame = true
        notifyFirstFrameIfNeeded()
    }

    private func notifyFirstFrameIfNeeded() {
        guard !didNotifyFirstFrame else { return }
        didNotifyFirstFrame = true
        onFirstFrame?()
    }
}
#endif
