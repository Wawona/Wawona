import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@objc(WWNSettingItem)
public final class WWNSettingItem: NSObject {
    @objc public var title: String = ""
    @objc public var key: String = ""
    @objc public var type: WWNSettingType = .WSettingSwitch
    @objc public var defaultValue: Any?
    @objc public var desc: String = ""
    @objc public var options: [String] = []
    @objc public var optionValues: [String] = []
    @objc public var interactive: Bool = true
    @objc public var urlString: String = ""
    @objc public var buttonTitle: String = ""
    @objc public var iconURL: String = ""
    @objc public var accessibilityIdentifier: String = ""
    /// Optional button action (Settings action rows).
    public var actionBlock: (() -> Void)?

    @objc(itemWithTitle:key:type:default:desc:)
    public static func item(
        title: String,
        key: String,
        type: WWNSettingType,
        default defaultValue: Any?,
        desc: String
    ) -> WWNSettingItem {
        let item = WWNSettingItem()
        item.title = title
        item.key = key
        item.type = type
        item.defaultValue = defaultValue
        item.desc = desc
        item.interactive = true
        if !key.isEmpty {
            item.accessibilityIdentifier = "wwn.settings.\(key)"
        }
        return item
    }
}

@objc(WWNPreferencesSection)
public final class WWNPreferencesSection: NSObject {
    @objc public var title: String = ""
    @objc public var accessibilityIdentifier: String = ""
    @objc public var icon: String = ""
    #if os(macOS)
    @objc public var iconColor: NSColor = .systemBlue
    #else
    @objc public var iconColor: UIColor = .systemBlue
    #endif
    @objc public var items: [WWNSettingItem] = []
}
