#if os(watchOS)
import Foundation
import SpriteKit

/// SpriteKit blit of Wayland SHM frames. Replaces watchOS Metal stub path.
/// No Metal / UIKit. Replaces `WWNIlandPresenterStub.m` for Watch present.
@MainActor
public final class SpritePresenter {
    public let scene: SKScene
    public private(set) var sprite: SKSpriteNode?

    public init(size: CGSize) {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = SKColor.black
    }

    public func present(cgImage: CGImage, size: CGSize) {
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest
        if let sprite {
            sprite.texture = texture
            sprite.size = size
        } else {
            let node = SKSpriteNode(texture: texture, size: size)
            node.position = CGPoint(x: size.width / 2, y: size.height / 2)
            scene.addChild(node)
            sprite = node
        }
    }

    public func resize(_ size: CGSize) {
        scene.size = size
        sprite?.size = size
        sprite?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
}
#else
import Foundation
import CoreGraphics

/// Non-watch stub so shared modules can reference SpritePresenter.
@MainActor
public final class SpritePresenter {
    public init(size: CGSize) { _ = size }
    public func present(cgImage: CGImage, size: CGSize) {
        _ = cgImage
        _ = size
    }
    public func resize(_ size: CGSize) { _ = size }
}
#endif
