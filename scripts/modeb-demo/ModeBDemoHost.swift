import UIKit
import QuartzCore

/// Thin UIKit host for Mode B tipa demo. Paint/JIT live in modeb_demo_support.c.
@objc(ModeBDemoAppDelegate)
final class ModeBDemoAppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var label: UILabel?
  private var displayLink: CADisplayLink?
  private var requestedMagnifier = false

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = (application, launchOptions)
    let win = UIWindow(frame: UIScreen.main.bounds)
    win.backgroundColor = .black
    let root = UIViewController()
    root.view.backgroundColor = .black

    let hud = UILabel(frame: root.view.bounds.insetBy(dx: 16, dy: 48))
    hud.textColor = .white
    hud.numberOfLines = 0
    hud.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
    hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hud.text = "Wawona Mode B Demo\nstarting…"
    root.view.addSubview(hud)
    label = hud

    win.rootViewController = root
    win.makeKeyAndVisible()
    window = win

    modeb_demo_fb_start()
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    return true
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    _ = application
    modeb_demo_probe_jit_and_fb()
    if !modeb_demo_cs_debugged(), !requestedMagnifier {
      requestedMagnifier = true
      if let url = URL(string: "apple-magnifier://enable-jit?bundle-id=com.aspauldingcode.wawona.modeb.demo") {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    }
  }

  @objc private func tick(_ link: CADisplayLink) {
    _ = link
    modeb_demo_fb_tick()
    if let cstr = modeb_demo_hud_text() {
      label?.text = String(cString: cstr)
    }
  }
}
