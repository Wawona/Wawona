#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  SystemShiftReader.swift
//  Wawona
//
//  Reads the system keyboard's live Shift state so on-screen toolbar keys
//  (Tab, arrows, symbols) can honor it, matching what the user sees latched
//  on the software keyboard or held on a hardware keyboard.
//  Ported 1:1 from rootshell.
//

import UIKit
import GameController
import os

@MainActor
public final class SystemShiftReader {
    public static let shared = SystemShiftReader()

    private nonisolated static let logger = Logger(subsystem: "io.wawona.Wawona", category: "SystemShift")

    public enum Reading: Sendable {
        case shifted
        case notShifted
        case unknown
    }

    // MARK: - Touch event flags (strategy 2)

    private var lastTouchModifierFlags: UIKeyModifierFlags = []
    private var lastTouchNoteTime: CFAbsoluteTime = 0
    private static let touchFlagsTTL: CFAbsoluteTime = 10

    // MARK: - Keyplane cache (strategy 3)

    private weak var cachedKeyplaneView: UIView?
    private var needsDiagnosticDump = true
    private var isSoftwareKeyboardVisible = false

    private let trackedKeyboardWindows = NSHashTable<UIWindow>.weakObjects()

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(invalidateCache),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible(_:)),
            name: UIWindow.didBecomeVisibleNotification,
            object: nil
        )
    }

    public func activate() {}

    @objc private func invalidateCache() {
        cachedKeyplaneView = nil
    }

    @objc private func keyboardDidHide() {
        isSoftwareKeyboardVisible = false
        cachedKeyplaneView = nil
    }

    @objc private func keyboardDidShow() {
        isSoftwareKeyboardVisible = true
        cachedKeyplaneView = nil
        needsDiagnosticDump = true
    }

    @objc private func windowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? UIWindow else { return }
        if Self.isKeyboardWindowClassName(NSStringFromClass(type(of: window))) {
            trackedKeyboardWindows.add(window)
            cachedKeyplaneView = nil
        }
    }

    private static func isKeyboardWindowClassName(_ name: String) -> Bool {
        name.contains("Keyboard") || name.contains("TextEffects") || name.contains("InputSet")
    }

    // MARK: - Public API

    public func noteTouchEvent(_ event: UIEvent?) {
        guard let event else { return }
        noteModifierFlags(event.modifierFlags)
    }

    public func noteModifierFlags(_ flags: UIKeyModifierFlags) {
        lastTouchModifierFlags = flags
        lastTouchNoteTime = CFAbsoluteTimeGetCurrent()
    }

    public func currentShift(near hint: UIView? = nil) -> Reading {
        let hardwareShift = hardwareShiftPressed()
        let flags = freshTouchFlags()
        let softwareReading: Reading = isSoftwareKeyboardVisible ? softwareShiftReading(hint: hint) : .unknown

        let result: Reading
        if hardwareShift == true {
            result = .shifted
        } else if flags.contains(.shift) || flags.contains(.alphaShift) {
            result = .shifted
        } else {
            result = softwareReading
        }

        let hardwareText = hardwareShift.map(String.init) ?? "n/a"
        let flagsRaw = flags.rawValue
        let softwareText = String(describing: softwareReading)
        let resultText = String(describing: result)
        Self.logger.debug("SystemShift: hw=\(hardwareText, privacy: .public) touchFlags=\(flagsRaw) swVisible=\(self.isSoftwareKeyboardVisible) sw=\(softwareText, privacy: .public) → \(resultText, privacy: .public)")

        return result
    }

    // MARK: - Strategy 1: GCKeyboard

    private func hardwareShiftPressed() -> Bool? {
        #if os(visionOS)
        return nil
        #else
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return nil }
        let left = input.button(forKeyCode: .leftShift)?.isPressed ?? false
        let right = input.button(forKeyCode: .rightShift)?.isPressed ?? false
        return left || right
        #endif
    }

    // MARK: - Strategy 2: touch flags

    private func freshTouchFlags() -> UIKeyModifierFlags {
        guard CFAbsoluteTimeGetCurrent() - lastTouchNoteTime < Self.touchFlagsTTL else { return [] }
        return lastTouchModifierFlags
    }

    // MARK: - Strategy 3: keyplane readout

    private func softwareShiftReading(hint: UIView?) -> Reading {
        #if os(visionOS)
        return .unknown
        #else
        if let cached = cachedKeyplaneView, cached.window != nil {
            return shiftState(fromKeyplane: cached)
        }
        cachedKeyplaneView = nil

        let windows = candidateKeyboardWindows(hint: hint)
        dumpDiagnosticsIfNeeded(windows: windows)

        for window in windows {
            if let keyplane = findKeyplaneView(in: window, depth: 0) {
                cachedKeyplaneView = keyplane
                return shiftState(fromKeyplane: keyplane)
            }
        }
        return .unknown
        #endif
    }

    private func shiftState(fromKeyplane view: UIView) -> Reading {
        let description = String(describing: view)
        guard let nameRange = description.range(of: "name = "),
              let end = description[nameRange.upperBound...].firstIndex(of: ";") else {
            return .unknown
        }
        let name = description[nameRange.upperBound..<end]
        return name.contains("Capital-Letter") ? .shifted : .notShifted
    }

    private func findKeyplaneView(in view: UIView, depth: Int) -> UIView? {
        guard depth <= 24 else { return nil }
        if NSStringFromClass(type(of: view)).contains("KeyplaneView") { return view }
        for subview in view.subviews {
            if let found = findKeyplaneView(in: subview, depth: depth + 1) { return found }
        }
        return nil
    }

    private func candidateKeyboardWindows(hint: UIView?) -> [UIWindow] {
        var result: [UIWindow] = []
        var seen = Set<ObjectIdentifier>()

        func add(_ window: UIWindow?) {
            guard let window, seen.insert(ObjectIdentifier(window)).inserted else { return }
            result.append(window)
        }

        if let hintWindow = hint?.window,
           Self.isKeyboardWindowClassName(NSStringFromClass(type(of: hintWindow))) {
            add(hintWindow)
        }
        for window in trackedKeyboardWindows.allObjects where window.isHidden == false {
            add(window)
        }
        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in sceneWindows
        where Self.isKeyboardWindowClassName(NSStringFromClass(type(of: window))) {
            add(window)
        }
        return result
    }

    private func dumpDiagnosticsIfNeeded(windows: [UIWindow]) {
        #if DEBUG
        guard needsDiagnosticDump else { return }
        needsDiagnosticDump = false

        let candidateClasses = windows.map { NSStringFromClass(type(of: $0)) }.joined(separator: ", ")
        let trackedCount = trackedKeyboardWindows.allObjects.count
        Self.logger.notice("SystemShift dump: candidates = [\(candidateClasses, privacy: .public)] tracked=\(trackedCount)")
        #endif
    }
}
#endif
