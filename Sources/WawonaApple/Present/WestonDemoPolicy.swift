import Foundation

private func normWestonDemoKey(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "" }
    let lower = value.lowercased()
    let parts = lower.split { $0 == " " || $0 == "_" }
    return parts.filter { !$0.isEmpty }.joined(separator: "-")
}

@_cdecl("WWNWestonDemoPrefersFixedSquare")
public func WWNWestonDemoPrefersFixedSquare(_ clientId: NSString?, _ title: NSString?) -> Bool {
    let idNorm = normWestonDemoKey(clientId as String?)
    if !idNorm.isEmpty {
        let fixed: Set<String> = [
            "weston-smoke", "smoke", "weston-flower", "flower",
            "weston-simple-shm", "simple-shm", "weston-simple-egl", "simple-egl",
            "org.freedesktop.weston.simple-egl", "org.freedesktop.weston.simple-shm",
            "weston-clickdot", "clickdot", "weston-eventdemo", "eventdemo",
        ]
        if fixed.contains(idNorm)
            || idNorm.hasSuffix("simple-egl") || idNorm.hasSuffix("simple-shm")
            || idNorm.hasSuffix("weston-flower") || idNorm.hasSuffix("weston-smoke")
            || idNorm.hasSuffix("weston-clickdot") || idNorm.hasSuffix("weston-eventdemo") {
            return true
        }
    }
    let tNorm = normWestonDemoKey(title as String?)
    if tNorm.isEmpty { return false }
    return tNorm.contains("simple-shm") || tNorm.contains("simple-egl")
        || tNorm.contains("flower") || tNorm.contains("smoke")
        || tNorm.contains("clickdot") || tNorm.contains("eventdemo")
}
