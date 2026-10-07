#if os(watchOS)
import Foundation

extension WWNWatchShellEnvironment {
    static func applyBundleShareEnv() {
        let fm = FileManager.default
        var shareRoot = (Bundle.main.bundlePath as NSString).appendingPathComponent("share")
        if !fm.fileExists(atPath: shareRoot), let res = Bundle.main.resourcePath, !res.isEmpty {
            let alt = (res as NSString).appendingPathComponent("share")
            if fm.fileExists(atPath: alt) { shareRoot = alt }
        }
        if fm.fileExists(atPath: shareRoot), getenv("XDG_DATA_DIRS") == nil {
            shareRoot.withCString { setenv("XDG_DATA_DIRS", $0, 1) }
        }

        let xkbRules = (bundledSharePath("X11/xkb") as NSString).appendingPathComponent("rules/evdev")
        if !xkbRules.isEmpty, fm.fileExists(atPath: xkbRules), getenv("XKB_CONFIG_ROOT") == nil {
            let root = ((xkbRules as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            root.withCString { setenv("XKB_CONFIG_ROOT", $0, 1) }
        }

        let compose = (bundledSharePath("X11/locale") as NSString).appendingPathComponent("compose.dir")
        if !compose.isEmpty, fm.fileExists(atPath: compose), getenv("XLOCALEDIR") == nil {
            let dir = (compose as NSString).deletingLastPathComponent
            dir.withCString { setenv("XLOCALEDIR", $0, 1) }
        }

        let westonData = bundledSharePath("weston")
        if !westonData.isEmpty, fm.fileExists(atPath: westonData) {
            westonData.withCString { setenv("WESTON_DATA_DIR", $0, 1) }
        }
        let cursors = bundledSharePath("icons/Adwaita/cursors")
        if !cursors.isEmpty, fm.fileExists(atPath: cursors) {
            bundledSharePath("icons").withCString { setenv("XCURSOR_PATH", $0, 1) }
            setenv("XCURSOR_THEME", "Adwaita", 1)
        }

        let fontDir = bundledSharePath("fonts")
        if !fontDir.isEmpty, fm.fileExists(atPath: fontDir) {
            let xdg = getenv("XDG_RUNTIME_DIR").map { String(cString: $0) } ?? NSTemporaryDirectory()
            let cacheDir = (xdg as NSString).appendingPathComponent("fontconfig-cache")
            try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            let confPath = (xdg as NSString).appendingPathComponent("fonts.conf")
            let conf = """
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
            <fontconfig>
              <dir>\(fontDir)</dir>
              <cachedir>\(cacheDir)</cachedir>
              <alias><family>monospace</family><prefer><family>DejaVuSansM Nerd Font Mono</family></prefer><prefer><family>DejaVu Sans Mono</family></prefer></alias>
              <alias><family>sans-serif</family><prefer><family>DejaVu Sans</family></prefer></alias>
              <alias><family>sans</family><prefer><family>DejaVu Sans</family></prefer></alias>
              <alias><family>Sans</family><prefer><family>DejaVu Sans</family></prefer></alias>
              <match target="pattern">
                <test name="family"><string>sans-serif</string></test>
                <edit name="family" mode="prepend" binding="strong"><string>DejaVu Sans</string></edit>
              </match>
              <config><rescan><int>30</int></rescan></config>
            </fontconfig>
            """
            if (try? conf.write(toFile: confPath, atomically: true, encoding: .utf8)) != nil {
                confPath.withCString { setenv("FONTCONFIG_FILE", $0, 1) }
                xdg.withCString { setenv("FONTCONFIG_PATH", $0, 1) }
                let mono = firstExistingFont(
                    [
                        "truetype/DejaVuSansMNerdFontMono-Regular.ttf",
                        "truetype/DejaVuSansMono.ttf",
                        "truetype/dejavu/DejaVuSansMono.ttf",
                    ],
                    under: fontDir
                )
                if !mono.isEmpty { mono.withCString { setenv("WAWONA_MONO_FONT", $0, 1) } }
                let sans = firstExistingFont(
                    ["truetype/DejaVuSans.ttf", "truetype/dejavu/DejaVuSans.ttf"],
                    under: fontDir
                )
                if !sans.isEmpty { sans.withCString { setenv("WAWONA_SANS_FONT", $0, 1) } }
            }
        }
    }

    static func bundledSharePath(_ sub: String) -> String {
        let fm = FileManager.default
        let bundle = Bundle.main.bundlePath
        var candidate = ((bundle as NSString).appendingPathComponent("share") as NSString).appendingPathComponent(sub)
        if fm.fileExists(atPath: candidate) { return candidate }
        if let resource = Bundle.main.resourcePath, !resource.isEmpty {
            candidate = (((resource as NSString).appendingPathComponent("share") as NSString).appendingPathComponent(sub))
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return ""
    }

    static func firstExistingFont(_ relPaths: [String], under fontDir: String) -> String {
        let fm = FileManager.default
        for rel in relPaths {
            let path = (fontDir as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: path) { return path }
        }
        guard let leaf = relPaths.first?.split(separator: "/").last.map(String.init), !leaf.isEmpty,
              let en = fm.enumerator(atPath: fontDir)
        else { return "" }
        for case let rel as String in en where (rel as NSString).lastPathComponent == leaf {
            return (fontDir as NSString).appendingPathComponent(rel)
        }
        return ""
    }
}

#endif
