import AVFoundation
import Darwin
import Foundation
import ImageIO
import CoreGraphics
import os.log
import Security

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

func wwnInstallDarwinHostB() {
  wwn_darwin_cli_set_open_file { path in
    #if os(iOS)
    let url = URL(fileURLWithPath: wwnCStr(path))
    var presented = false
    wwnOnMain {
      let ctl = UIDocumentInteractionController(url: url)
      if let root = wwnTopController() {
        presented = ctl.presentOpenInMenu(from: root.view.bounds, in: root.view, animated: true)
          || ctl.presentPreview(animated: true)
      }
    }
    return presented ? 0 : 1
    #else
    fputs("open: not available\n", stderr)
    return 1
    #endif
  }
  wwn_darwin_cli_set_sips_info { path, fmt, fmtLen, w, h in
    let url = URL(fileURLWithPath: wwnCStr(path)) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
      return 1
    }
    let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.int32Value ?? 0
    let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.int32Value ?? 0
    w?.pointee = width
    h?.pointee = height
    let uti = CGImageSourceGetType(src) as String? ?? "public.png"
    if let fmt = fmt {
      strncpy(fmt, uti, fmtLen)
    }
    return 0
  }
  wwn_darwin_cli_set_sips_write { src, dst, format, rh, rw in
    let srcURL = URL(fileURLWithPath: wwnCStr(src)) as CFURL
    guard let source = CGImageSourceCreateWithURL(srcURL, nil),
          var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return 1
    }
    if rh > 0 && rw > 0 {
      let cs = CGColorSpaceCreateDeviceRGB()
      if let ctx = CGContext(
        data: nil, width: Int(rw), height: Int(rh), bitsPerComponent: 8,
        bytesPerRow: Int(rw) * 4, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) {
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(rw), height: CGFloat(rh)))
        if let scaled = ctx.makeImage() {
          image = scaled
        }
      }
    }
    let fmt = wwnCStr(format).lowercased()
    let uti: CFString
    switch fmt {
    case "jpeg", "jpg": uti = "public.jpeg" as CFString
    case "tiff", "tif": uti = "public.tiff" as CFString
    case "gif": uti = "com.compuserve.gif" as CFString
    case "bmp": uti = "com.microsoft.bmp" as CFString
    default: uti = "public.png" as CFString
    }
    let destURL = URL(fileURLWithPath: wwnCStr(dst)) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(destURL, uti, 1, nil) else { return 1 }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest) ? 0 : 1
  }
  wwn_darwin_cli_set_product_version { buf, n in
    guard let buf = buf, n > 0 else { return 1 }
    #if os(watchOS)
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let s = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    #elseif os(iOS) || os(tvOS) || os(visionOS)
    let s = UIDevice.current.systemVersion
    #else
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let s = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    #endif
    strncpy(buf, s, n)
    return 0
  }
  wwn_darwin_cli_set_idle_prevent { seconds in
    #if os(iOS) || os(tvOS) || os(visionOS)
    wwnOnMain {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    if seconds > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds)) {
        UIApplication.shared.isIdleTimerDisabled = false
      }
    }
    return 0
    #else
    let _ = seconds
    return 1
    #endif
  }
  wwn_darwin_cli_set_plist_read_json { path, out in
    let url = URL(fileURLWithPath: wwnCStr(path))
    guard let data = try? Data(contentsOf: url) else { return 1 }
    var fmt = PropertyListSerialization.PropertyListFormat.xml
    guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: &fmt),
          JSONSerialization.isValidJSONObject(obj),
          let json = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
          let s = String(data: json, encoding: .utf8) else {
      if let s = String(data: data, encoding: .utf8),
         let jsonData = try? JSONSerialization.jsonObject(with: data),
         JSONSerialization.isValidJSONObject(jsonData),
         let outData = try? JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted]),
         let text = String(data: outData, encoding: .utf8) {
        out?.pointee = wwnDup(text)
        return 0
      }
      return 1
    }
    out?.pointee = wwnDup(s)
    return 0
  }
  wwn_darwin_cli_set_plist_write { path, json, format in
    let dest = URL(fileURLWithPath: wwnCStr(path))
    let fmtName = wwnCStr(format)
    guard let jsonData = wwnCStr(json).data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: jsonData) else {
      return 1
    }
    if fmtName == "json" {
      guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else {
        return 1
      }
      return (try? data.write(to: dest, options: .atomic)).map { _ in 0 } ?? 1
    }
    let fmt: PropertyListSerialization.PropertyListFormat = fmtName == "binary1" ? .binary : .xml
    guard let data = try? PropertyListSerialization.data(fromPropertyList: obj, format: fmt, options: 0) else {
      return 1
    }
    try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    return (try? data.write(to: dest, options: .atomic)).map { _ in 0 } ?? 1
  }
  wwn_darwin_cli_set_copy_item { src, dst in
    let from = URL(fileURLWithPath: wwnCStr(src))
    let to = URL(fileURLWithPath: wwnCStr(dst))
    do {
      try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
      }
      try FileManager.default.copyItem(at: from, to: to)
      return 0
    } catch {
      return 1
    }
  }
  wwn_darwin_cli_set_keychain_dump { out in
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    var text = "keychain (this app only)\n"
    if status == errSecSuccess, let items = result as? [[String: Any]] {
      for item in items {
        if let acct = item[kSecAttrAccount as String] as? String {
          text += "account: \(acct)\n"
        }
      }
    } else {
      text += "no items or not accessible\n"
    }
    out?.pointee = wwnDup(text)
    return 0
  }
  wwn_darwin_cli_set_oslog { msg in
    let log = OSLog(subsystem: "com.aspauldingcode.Wawona", category: "darwin-cli")
    os_log("%{public}s", log: log, wwnCStr(msg))
    return 0
  }
  wwn_darwin_cli_set_path_status { out in
    out?.pointee = wwnDup("Network path: public subset")
    return 0
  }
}
