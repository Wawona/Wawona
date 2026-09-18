#if canImport(UIKit) && (os(iOS) || os(tvOS) || os(visionOS))
//
//  KeyboardWritingAssistanceButton.swift
//  Wawona
//
//  A native primary-action menu inside the toolbar's standard-sized key.
//  Ported 1:1 from rootshell.
//

import UIKit
import Combine

final class KeyboardWritingAssistanceButton: KeyboardSymbolButton {
    private let menuButton = UIButton(type: .system)
    private var observation: AnyCancellable?
    private static let storageKey = "wwn_terminal_writing_assistance_mode"

    public static let writingAssistanceDidChangeNotification = Notification.Name("WWNWritingAssistanceDidChangeNotification")

    init(sizes: KeyboardSizes) {
        super.init(key: "__writingAssistance__", display: .icon(TerminalWritingAssistanceMode.toolbarIcon), sizes: sizes)
        isAccessibilityElement = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = String(localized: "Writing Assistance")
        addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let observer = NotificationCenter.default.addObserver(forName: Self.writingAssistanceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observation = AnyCancellable { NotificationCenter.default.removeObserver(observer) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func currentMode() -> TerminalWritingAssistanceMode {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let mode = TerminalWritingAssistanceMode(rawValue: raw) {
            return mode
        }
        return .off
    }

    private func refresh() {
        let mode = currentMode()
        menuButton.accessibilityValue = mode.title
        menuButton.menu = UIMenu(children: TerminalWritingAssistanceMode.allCases.map { choice in
            UIAction(title: choice.title, image: UIImage(systemName: choice.icon),
                     state: choice == mode ? .on : .off) { _ in
                UserDefaults.standard.set(choice.rawValue, forKey: Self.storageKey)
                NotificationCenter.default.post(name: Self.writingAssistanceDidChangeNotification, object: nil)
            }
        })
    }
}
#endif
