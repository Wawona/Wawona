//
// WawonaLinuxVZ.swift
//
// Native Apple Virtualization.framework launcher for the Wawona "NixOS VM"
// machine type (plan phase p26-vm-nixos). This is the macOS-native replacement
// for the QEMU-cocoa `wawona-linux-vm` path: it boots a prebuilt NixOS guest
// via direct-kernel boot (VZLinuxBootLoader) and bridges the guest's Wayland
// session into Wawona over virtio-vsock + waypipe — the same model OrbStack
// uses (Virtualization.framework + vsock transport) rather than WSLg's RDP.
//
// Design notes:
//   * Direct kernel boot needs an *uncompressed* arm64 `Image` (compressed
//     kernels hang under Virtualization.framework on Apple Silicon).
//   * Guest↔host communication is virtio-vsock (guest CID 3). We expose a
//     bidirectional bridge so `waypipe --vsock` in the guest reaches Wawona's
//     Wayland socket on the host without any TCP/RDP stack.
//   * The binary must be signed with `com.apple.security.virtualization`
//     (handled by vz-launcher.nix at first run).
//
// This file is compiled on demand by dependencies/wawona/vz-launcher.nix using
// the host Xcode toolchain (keeps the Nix build pure), mirroring the other
// runtime-`xcrun` wrappers in the flake.
//

import Darwin
import Foundation
import Virtualization

// MARK: - Logging

@inline(__always)
func log(_ message: String) {
    FileHandle.standardError.write(Data(("[wawona-vz] " + message + "\n").utf8))
}

func die(_ message: String) -> Never {
    log("FATAL: " + message)
    exit(1)
}

// MARK: - CLI options

struct Options {
    var kernel: String?
    var initrd: String?
    var disks: [String] = []
    var cmdline = "console=hvc0 root=/dev/vda rw quiet"
    var cpus = 4
    var memoryMiB: UInt64 = 4096
    var shareDir: String?
    var shareTag = "wawona"
    var rosetta = false
    var readonlyDisk = false
    // vsock bridge (listener mode): host listens on this guest vsock port; each
    // guest-initiated connection is forwarded to `forwardUnix`.
    var vsockListenPort: UInt32?
    var forwardUnix: String?
    // vsock bridge (connect mode): host listens on the `listenUnix` socket and,
    // for each local connection, dials the guest on `vsockConnectPort`.
    var vsockConnectPort: UInt32?
    var listenUnix: String?
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    func next(_ flag: String) -> String {
        guard let v = it.next() else { die("\(flag) requires a value") }
        return v
    }
    while let arg = it.next() {
        switch arg {
        case "--kernel": o.kernel = next(arg)
        case "--initrd": o.initrd = next(arg)
        case "--disk": o.disks.append(next(arg))
        case "--cmdline": o.cmdline = next(arg)
        case "--cpus": o.cpus = Int(next(arg)) ?? o.cpus
        case "--memory-mib": o.memoryMiB = UInt64(next(arg)) ?? o.memoryMiB
        case "--share-dir": o.shareDir = next(arg)
        case "--share-tag": o.shareTag = next(arg)
        case "--rosetta": o.rosetta = true
        case "--readonly-disk": o.readonlyDisk = true
        case "--vsock-listen": o.vsockListenPort = UInt32(next(arg))
        case "--forward-unix": o.forwardUnix = next(arg)
        case "--vsock-connect": o.vsockConnectPort = UInt32(next(arg))
        case "--listen-unix": o.listenUnix = next(arg)
        case "-h", "--help":
            print("""
            wawona-vz — boot a NixOS guest under Virtualization.framework and
            bridge its Wayland session into Wawona over vsock+waypipe.

            Required:
              --kernel PATH        uncompressed arm64 kernel Image
              --initrd PATH        initrd/initramfs
              --disk PATH          raw/ext4 root disk (repeatable)

            Common:
              --cmdline STR        kernel command line (default: console=hvc0 root=/dev/vda rw quiet)
              --cpus N             vCPU count (default 4)
              --memory-mib N       guest RAM in MiB (default 4096)
              --share-dir PATH     virtiofs-share a host dir (tag: --share-tag, default "wawona")
              --rosetta            expose Rosetta x86_64 translation to the guest

            Wayland bridge (pick one direction):
              --vsock-listen PORT --forward-unix PATH
                  host accepts guest vsock connections on PORT and forwards each
                  to the host unix socket PATH (e.g. Wawona's wayland-0).
              --vsock-connect PORT --listen-unix PATH
                  host listens on unix socket PATH and dials the guest on PORT.
            """)
            exit(0)
        default:
            die("unknown argument: \(arg)")
        }
    }
    return o
}

// MARK: - Raw fd <-> fd bidirectional pump

/// Copies bytes in both directions between two file descriptors until either
/// side closes, then closes both. Each direction runs on its own thread with a
/// blocking read/write loop (simple and robust for the low-throughput control
/// path; waypipe does its own batching/compression above this).
final class Bridge {
    static func start(_ a: Int32, _ b: Int32, label: String) {
        let closedOnce = ClosedFlag(a: a, b: b)
        pump(from: a, to: b, closer: closedOnce, label: "\(label)/a→b")
        pump(from: b, to: a, closer: closedOnce, label: "\(label)/b→a")
    }

    private final class ClosedFlag {
        private let lock = NSLock()
        private var done = false
        let a: Int32
        let b: Int32
        init(a: Int32, b: Int32) { self.a = a; self.b = b }
        func closeBoth() {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            close(a)
            close(b)
        }
    }

    private static func pump(from src: Int32, to dst: Int32, closer: ClosedFlag, label: String) {
        let t = Thread {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = buf.withUnsafeMutableBytes { read(src, $0.baseAddress, $0.count) }
                if n <= 0 { break }
                var off = 0
                var failed = false
                while off < n {
                    let w = buf.withUnsafeBytes { write(dst, $0.baseAddress!.advanced(by: off), n - off) }
                    if w <= 0 { failed = true; break }
                    off += w
                }
                if failed { break }
            }
            closer.closeBoth()
        }
        t.name = label
        t.stackSize = 512 * 1024
        t.start()
    }
}

// MARK: - Unix socket helpers

/// Writes `path` into `addr.sun_path` in a single exclusive access (avoids the
/// Swift exclusivity violation from nesting a mutable-pointer access inside a
/// `withCString` closure that also captures `addr`).
private func setSunPath(_ addr: inout sockaddr_un, _ path: String) -> Bool {
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    let bytes = Array(path.utf8)
    if bytes.count >= cap { return false }
    withUnsafeMutablePointer(to: &addr.sun_path) { p in
        p.withMemoryRebound(to: UInt8.self, capacity: cap) { dst in
            for i in 0..<bytes.count { dst[i] = bytes[i] }
            dst[bytes.count] = 0
        }
    }
    return true
}

func connectUnixSocket(_ path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    if !setSunPath(&addr, path) { close(fd); return -1 }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    if rc != 0 { close(fd); return -1 }
    return fd
}

func listenUnixSocket(_ path: String) -> Int32 {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    if !setSunPath(&addr, path) { close(fd); return -1 }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
    }
    if rc != 0 { close(fd); return -1 }
    if listen(fd, 16) != 0 { close(fd); return -1 }
    return fd
}

// MARK: - VM delegate + vsock listener

@available(macOS 13.0, *)
final class VZDelegate: NSObject, VZVirtualMachineDelegate, VZVirtioSocketListenerDelegate {
    let forwardUnix: String?

    init(forwardUnix: String?) {
        self.forwardUnix = forwardUnix
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        log("guest stopped cleanly")
        exit(0)
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        log("guest stopped with error: \(error.localizedDescription)")
        exit(1)
    }

    // Listener mode: forward each guest-initiated vsock connection to the host
    // unix socket (Wawona's Wayland socket / a waypipe endpoint).
    func listener(_ listener: VZVirtioSocketListener,
                  shouldAcceptNewConnection connection: VZVirtioSocketConnection,
                  from socketDevice: VZVirtioSocketDevice) -> Bool {
        guard let unixPath = forwardUnix else {
            log("vsock connection but no --forward-unix set; rejecting")
            return false
        }
        let ufd = connectUnixSocket(unixPath)
        if ufd < 0 {
            log("failed to connect host unix socket \(unixPath); rejecting vsock conn")
            return false
        }
        log("bridging guest vsock port \(connection.destinationPort) ↔ \(unixPath)")
        Bridge.start(connection.fileDescriptor, ufd, label: "vsock-in")
        return true
    }
}

// MARK: - Configuration

@available(macOS 13.0, *)
func buildConfiguration(_ o: Options) throws -> VZVirtualMachineConfiguration {
    guard let kernel = o.kernel else { die("--kernel is required") }
    guard let initrd = o.initrd else { die("--initrd is required") }

    let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: kernel))
    bootLoader.initialRamdiskURL = URL(fileURLWithPath: initrd)
    bootLoader.commandLine = o.cmdline

    let config = VZVirtualMachineConfiguration()
    config.bootLoader = bootLoader
    config.cpuCount = max(1, o.cpus)
    config.memorySize = o.memoryMiB * 1024 * 1024

    // Console on hvc0 → our stdio, so guest boot logs stream to the terminal.
    let console = VZVirtioConsoleDeviceSerialPortConfiguration()
    console.attachment = VZFileHandleSerialPortAttachment(
        fileHandleForReading: FileHandle.standardInput,
        fileHandleForWriting: FileHandle.standardOutput)
    config.serialPorts = [console]

    // Root + extra disks.
    var storage: [VZStorageDeviceConfiguration] = []
    for disk in o.disks {
        let attachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: disk), readOnly: o.readonlyDisk)
        storage.append(VZVirtioBlockDeviceConfiguration(attachment: attachment))
    }
    config.storageDevices = storage

    config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

    // vsock — the Wayland transport.
    config.socketDevices = [VZVirtioSocketDeviceConfiguration()]

    // Optional virtiofs share (host dir → guest), plus Rosetta for x86_64.
    var fsDevices: [VZDirectorySharingDeviceConfiguration] = []
    if let shareDir = o.shareDir {
        let dev = VZVirtioFileSystemDeviceConfiguration(tag: o.shareTag)
        let shared = VZSharedDirectory(url: URL(fileURLWithPath: shareDir), readOnly: false)
        dev.share = VZSingleDirectoryShare(directory: shared)
        fsDevices.append(dev)
    }
    if o.rosetta {
        switch VZLinuxRosettaDirectoryShare.availability {
        case .installed:
            let rosetta = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
            rosetta.share = try VZLinuxRosettaDirectoryShare()
            fsDevices.append(rosetta)
        case .notInstalled:
            log("Rosetta requested but not installed; run `softwareupdate --install-rosetta`. Continuing without it.")
        case .notSupported:
            log("Rosetta not supported on this host; continuing without it.")
        @unknown default:
            break
        }
    }
    config.directorySharingDevices = fsDevices

    try config.validate()
    return config
}

// MARK: - Main

func run() {
    let o = parseArgs()

    guard #available(macOS 13.0, *) else {
        die("Virtualization requires macOS 13+ (Apple Silicon). This host is too old.")
    }

    let delegate = VZDelegate(forwardUnix: o.forwardUnix)
    let queue = DispatchQueue(label: "com.aspauldingcode.Wawona.vz")

    var vmRef: VZVirtualMachine?

    queue.sync {
        do {
            let config = try buildConfiguration(o)
            let vm = VZVirtualMachine(configuration: config, queue: queue)
            vm.delegate = delegate
            vmRef = vm
        } catch {
            die("configuration error: \(error.localizedDescription)")
        }
    }

    guard let vm = vmRef else { die("failed to construct VM") }

    queue.async {
        vm.start { result in
            switch result {
            case .success:
                log("guest started (cpus=\(o.cpus), mem=\(o.memoryMiB)MiB)")
                configureVsockBridge(vm: vm, options: o, delegate: delegate, queue: queue)
            case let .failure(error):
                die("failed to start guest: \(error.localizedDescription)")
            }
        }
    }

    // VZ drives callbacks on the main run loop.
    dispatchMain()
}

@available(macOS 13.0, *)
func configureVsockBridge(vm: VZVirtualMachine, options o: Options,
                          delegate: VZDelegate, queue: DispatchQueue) {
    guard let socketDevice = vm.socketDevices.first as? VZVirtioSocketDevice else {
        log("no vsock device present; Wayland bridge disabled")
        return
    }

    // Listener mode: guest dials out; host forwards to a unix socket.
    if let port = o.vsockListenPort {
        let listener = VZVirtioSocketListener()
        listener.delegate = delegate
        socketDevice.setSocketListener(listener, forPort: port)
        log("listening for guest vsock connections on port \(port) → \(o.forwardUnix ?? "(unset)")")
    }

    // Connect mode: host listens on a unix socket; each local client triggers a
    // dial to the guest vsock port.
    if let port = o.vsockConnectPort, let unixPath = o.listenUnix {
        let lfd = listenUnixSocket(unixPath)
        if lfd < 0 {
            log("failed to listen on unix socket \(unixPath); connect-mode bridge disabled")
        } else {
            log("listening on unix \(unixPath) → guest vsock port \(port)")
            let t = Thread {
                while true {
                    let cfd = accept(lfd, nil, nil)
                    if cfd < 0 { break }
                    queue.async {
                        socketDevice.connect(toPort: port) { result in
                            switch result {
                            case let .success(conn):
                                Bridge.start(cfd, conn.fileDescriptor, label: "vsock-out")
                            case let .failure(err):
                                log("guest vsock connect failed: \(err.localizedDescription)")
                                close(cfd)
                            }
                        }
                    }
                }
            }
            t.name = "unix-accept"
            t.start()
        }
    }
}

run()
