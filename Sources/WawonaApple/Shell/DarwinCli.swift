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
#if os(macOS)
import AppKit
#endif

@_silgen_name("wwn_darwin_cli_run")
func wwn_darwin_cli_run(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

@_silgen_name("wwn_darwin_cli_set_pasteboard_copy")
func wwn_darwin_cli_set_pasteboard_copy(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_pasteboard_paste")
func wwn_darwin_cli_set_pasteboard_paste(_ fn: (@convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_speak")
func wwn_darwin_cli_set_speak(_ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, Float) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_list_voices")
func wwn_darwin_cli_set_list_voices(_ fn: (@convention(c) () -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_open_url")
func wwn_darwin_cli_set_open_url(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_open_directory")
func wwn_darwin_cli_set_open_directory(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_open_file")
func wwn_darwin_cli_set_open_file(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_sips_info")
func wwn_darwin_cli_set_sips_info(
  _ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_sips_write")
func wwn_darwin_cli_set_sips_write(
  _ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, Int32) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_product_version")
func wwn_darwin_cli_set_product_version(_ fn: (@convention(c) (UnsafeMutablePointer<CChar>?, Int) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_idle_prevent")
func wwn_darwin_cli_set_idle_prevent(_ fn: (@convention(c) (Int32) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_plist_read_json")
func wwn_darwin_cli_set_plist_read_json(
  _ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_plist_write")
func wwn_darwin_cli_set_plist_write(
  _ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_copy_item")
func wwn_darwin_cli_set_copy_item(_ fn: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_keychain_dump")
func wwn_darwin_cli_set_keychain_dump(_ fn: (@convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_oslog")
func wwn_darwin_cli_set_oslog(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_path_status")
func wwn_darwin_cli_set_path_status(_ fn: (@convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32)?)

@_silgen_name("wwn_darwin_cli_set_host_flag")
func wwn_darwin_cli_set_host_flag(_ fn: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?)

func wwnOnMain(_ block: () -> Void) {
  if Thread.isMainThread {
    block()
  } else {
    DispatchQueue.main.sync(execute: block)
  }
}

func wwnDup(_ s: String) -> UnsafeMutablePointer<CChar>? {
  strdup(s)
}

func wwnCStr(_ p: UnsafePointer<CChar>?) -> String {
  guard let p = p else { return "" }
  return String(cString: p)
}

private let wwnDarwinHostOnce: Void = {
  wwn_darwin_cli_set_host_flag { name in
    let n = wwnCStr(name)
    #if os(tvOS) || os(watchOS)
    if n == "pasteboard" || n == "files" { return 0 }
    #endif
    #if os(watchOS)
    if n == "open" { return 0 }
    #endif
    return 1
  }
  wwn_darwin_cli_set_pasteboard_copy { text in
    #if os(iOS) || os(visionOS)
    var ok: Int32 = 0
    wwnOnMain {
      UIPasteboard.general.string = wwnCStr(text)
      ok = 0
    }
    return ok
    #else
    fputs("pbcopy: not available\n", stderr)
    return 1
    #endif
  }
  wwn_darwin_cli_set_pasteboard_paste { out in
    #if os(iOS) || os(visionOS)
    var result: String?
    wwnOnMain {
      result = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
    }
    guard let out = out else { return 1 }
    out.pointee = wwnDup(result ?? "")
    return 0
    #else
    fputs("pbpaste: not available\n", stderr)
    return 1
    #endif
  }
  wwn_darwin_cli_set_list_voices {
    for v in AVSpeechSynthesisVoice.speechVoices() {
      print(String(format: "%-20@ %@", v.name, v.language))
    }
    return 0
  }
  wwn_darwin_cli_set_speak { text, voice, rate in
    let body = wwnCStr(text)
    let voiceName = wwnCStr(voice)
    let utterance = AVSpeechUtterance(string: body)
    if rate >= 0 {
      utterance.rate = rate
    }
    if !voiceName.isEmpty {
      utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
        $0.name.lowercased().hasPrefix(voiceName.lowercased())
      }
      if utterance.voice == nil {
        fputs("say: voice not found: \(voiceName)\n", stderr)
        return 1
      }
    }
    let wait = WWNSayWait()
    let synth = AVSpeechSynthesizer()
    synth.delegate = wait
    wwnOnMain {
      synth.speak(utterance)
    }
    _ = wait.sema.wait(timeout: .now() + 120)
    return 0
  }
  wwn_darwin_cli_set_open_url { url in
    #if os(watchOS)
    fputs("open: not available\n", stderr)
    return 1
    #elseif os(iOS) || os(tvOS) || os(visionOS)
    guard let u = URL(string: wwnCStr(url)) else { return 1 }
    var ok = false
    var finished = false
    wwnOnMain {
      UIApplication.shared.open(u, options: [:]) { success in
        ok = success
        finished = true
      }
    }
    let deadline = Date().addingTimeInterval(3)
    while !finished && Date() < deadline {
      if Thread.isMainThread {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
      } else {
        usleep(20000)
      }
    }
    return (finished ? ok : true) ? 0 : 1
    #elseif os(macOS)
    guard let u = URL(string: wwnCStr(url)) else { return 1 }
    return NSWorkspace.shared.open(u) ? 0 : 1
    #else
    fputs("open: not available\n", stderr)
    return 1
    #endif
  }
  wwn_darwin_cli_set_open_directory { path in
    #if os(iOS) || os(visionOS)
    let fileURL = URL(fileURLWithPath: wwnCStr(path))
    var abs = fileURL.absoluteString
    if abs.hasPrefix("file://") {
      abs = "shareddocuments://" + String(abs.dropFirst("file://".count))
    }
    guard let u = URL(string: abs) else { return 1 }
    var ok = false
    var finished = false
    wwnOnMain {
      UIApplication.shared.open(u, options: [:]) { success in
        ok = success
        finished = true
      }
    }
    let deadline = Date().addingTimeInterval(3)
    while !finished && Date() < deadline {
      if Thread.isMainThread {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
      } else {
        usleep(20000)
      }
    }
    return (finished ? ok : true) ? 0 : 1
    #else
    fputs("open: not available\n", stderr)
    return 1
    #endif
  }
  wwnInstallDarwinHostB()
}()

#if os(iOS)
func wwnTopController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.flatMap { $0.windows }.first
  var ctl = window?.rootViewController
  while let presented = ctl?.presentedViewController {
    ctl = presented
  }
  return ctl
}
#endif

private final class WWNSayWait: NSObject, AVSpeechSynthesizerDelegate {
  let sema = DispatchSemaphore(value: 0)
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    sema.signal()
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    sema.signal()
  }
}

@used
@_cdecl("wawona_darwin_cli_main")
public func wawona_darwin_cli_main(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
  _ = wwnDarwinHostOnce
  return wwn_darwin_cli_run(argc, argv)
}
