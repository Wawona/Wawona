import Foundation

#if os(macOS)

/// Builds argv for `wwn-containerd run` from per-machine `containerSettings`
/// plus Settings → Containers defaults. macOS Relay container backend is Apple
/// Containerization via `wwn-containerd` (not host Docker, not StaticCpu).
enum WWNContainerBootCommand {
    struct LaunchPlan {
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let desktopSession: Bool
        let readyFile: String
        let doneFile: String
    }

    static func plan(for profile: WWNMachineProfile) throws -> LaunchPlan {
        let machineId = profile.machineId ?? ""
        guard !machineId.isEmpty else {
            throw NSError(
                domain: "WWNContainerRunner", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing machine id."]
            )
        }

        let cs = (profile.containerSettings as? [String: Any]) ?? [:]
        if let script = trimmed(profile.customScript), !script.isEmpty {
            let ready = markerPath(machineId: machineId, kind: "ready")
            let done = markerPath(machineId: machineId, kind: "done")
            return LaunchPlan(
                executable: "/bin/sh",
                arguments: ["-lc", script],
                environment: baseEnvironment(
                    profile: profile, ready: ready, done: done, desktop: wantsDesktop(cs)
                ),
                desktopSession: wantsDesktop(cs),
                readyFile: ready,
                doneFile: done
            )
        }

        let exe = try resolveContainerd()
        let kernel = try resolveKernel(cs: cs)
        var args: [String] = ["run", "--kernel", kernel, "--id", containerId(for: machineId)]

        let memory = firstNonEmpty(string(cs, "memory"), prefsMemory()) ?? ""
        if !memory.isEmpty {
            args += ["--memory", memory]
        }
        if let initfs = string(cs, "initfsPath"), !initfs.isEmpty {
            args += ["--initfs", (initfs as NSString).expandingTildeInPath]
        }
        if bool(cs, "readOnly") { args.append("--read-only") }
        if bool(cs, "initProcess") { args.append("--init") }

        let desktop = wantsDesktop(cs)
        if desktop {
            let port = vsockPort(cs)
            args += ["--wayland-vsock-port", "\(port)"]
            if let guest = findBundledOrPath("waypipe-guest")
                ?? findWaypipeGuestFromRoot() {
                args += ["--waypipe-guest-bin", guest]
            }
            if let root = findWaypipeGuestRoot() {
                // Tip wwn-containerd accepts this; older builds ignore via env
                // WAWONA_WAYPIPE_GUEST_ROOT set below.
                args += ["--waypipe-guest-root", root]
            }
        }

        let ref = firstNonEmpty(string(cs, "containerRef"), prefsImage())
            ?? "docker.io/library/alpine:3.20"
        let normalizedRef = normalizeImageRef(ref)
        if let archive = resolveArchive(cs: cs, ref: normalizedRef) {
            args += ["--image-archive", archive]
        } else {
            args += ["--image", normalizedRef]
        }

        let command = firstNonEmpty(string(cs, "entryCommand"), prefsCommand()) ?? "/bin/sh"
        // wwn-containerd takes guest argv directly (no `--` separator).
        args += ["/bin/sh", "-c", command]

        let ready = markerPath(machineId: machineId, kind: "ready")
        let done = markerPath(machineId: machineId, kind: "done")
        return LaunchPlan(
            executable: exe,
            arguments: args,
            environment: baseEnvironment(
                profile: profile, ready: ready, done: done, desktop: desktop
            ),
            desktopSession: desktop,
            readyFile: ready,
            doneFile: done
        )
    }

    static func markerPath(machineId: String, kind: String) -> String {
        let safe = machineId.replacingOccurrences(of: "/", with: "_")
        return NSTemporaryDirectory() + "wawona-container-\(kind)-\(safe)"
    }

    // MARK: - resolve

    private static func resolveContainerd() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let direct = env["WAWONA_CONTAINERD"], !direct.isEmpty,
           FileManager.default.isExecutableFile(atPath: direct) {
            return direct
        }
        if let bundled = findBundledOrPath("wwn-containerd") {
            return bundled
        }
        // Dev checkout tip (SwiftPM release or nix build .#wwn-containerd).
        let siblings = [
            "/Users/8amps/Wawona/wwn-containers/dependencies/containers/macos/.build/arm64-apple-macosx/release/wwn-containerd",
            NSString(string: "~/Wawona/wwn-containers/result-containerd-tip/bin/wwn-containerd").expandingTildeInPath,
            NSString(string: "~/Wawona/wwn-containers/result-1/bin/wwn-containerd").expandingTildeInPath,
            NSString(string: "~/Wawona/wwn-containers/result/bin/wwn-containerd").expandingTildeInPath,
            "/Users/8amps/Wawona/wwn-containers/result-1/bin/wwn-containerd",
        ]
        for path in siblings where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw NSError(
            domain: "WWNContainerRunner", code: 4,
            userInfo: [NSLocalizedDescriptionKey:
                "wwn-containerd not found. Bundle Resources/bin/wwn-containerd "
                    + "or set WAWONA_CONTAINERD."]
        )
    }

    private static func resolveKernel(cs: [String: Any]) throws -> String {
        if let k = string(cs, "kernelPath"), !k.isEmpty {
            let path = (k as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let prefs = WWNPreferencesManager.sharedManager().containerKernelPath()
        if !prefs.isEmpty {
            let path = (prefs as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        if let env = ProcessInfo.processInfo.environment["WAWONA_VM_KERNEL"], !env.isEmpty,
           FileManager.default.fileExists(atPath: env) {
            return env
        }
        let defaultKernel = NSHomeDirectory()
            + "/Library/Application Support/com.apple.container/kernels/default.kernel-arm64"
        if FileManager.default.fileExists(atPath: defaultKernel) {
            return defaultKernel
        }
        throw NSError(
            domain: "WWNContainerRunner", code: 5,
            userInfo: [NSLocalizedDescriptionKey:
                "Linux kernel missing. Install Apple container kernels or set "
                    + "Settings → Containers → Kernel Path / WAWONA_VM_KERNEL."]
        )
    }

    private static func resolveArchive(cs: [String: Any], ref: String) -> String? {
        if let archive = string(cs, "imageArchivePath"), !archive.isEmpty {
            let path = (archive as NSString).expandingTildeInPath
            let index = (path as NSString).appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: index) { return path }
        }
        if ref.contains("wawona-container-desktop") {
            return CLIMachineRecipeSpecs.importedDesktopArchive()
                ?? CLIMachineRecipeSpecs.bundledDesktopArchive()
        }
        return nil
    }

    private static func findWaypipeGuestRoot() -> String? {
        if let env = ProcessInfo.processInfo.environment["WAWONA_WAYPIPE_GUEST_ROOT"],
           !env.isEmpty,
           FileManager.default.isExecutableFile(
               atPath: (env as NSString).appendingPathComponent("bin/waypipe")
           ) {
            return env
        }
        if let guest = findBundledOrPath("waypipe-guest") {
            let root = ((guest as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("waypipe-guest-root")
            if FileManager.default.isExecutableFile(
                atPath: (root as NSString).appendingPathComponent("bin/waypipe")
            ) {
                return root
            }
        }
        // Dev result symlinks when Resources/bin is empty.
        let candidates = [
            NSString(string: "~/Wawona/wwn-containers/result-waypipe-guest-root").expandingTildeInPath,
            "/tmp/wawona-waypipe-guest-root",
            "/Users/8amps/Wawona/wwn-containers/result-1",
        ]
        for root in candidates {
            let bin = (root as NSString).appendingPathComponent("bin/waypipe")
            if FileManager.default.isExecutableFile(atPath: bin) {
                return root
            }
        }
        return nil
    }

    private static func findWaypipeGuestFromRoot() -> String? {
        guard let root = findWaypipeGuestRoot() else { return nil }
        let bin = (root as NSString).appendingPathComponent("bin/waypipe")
        return FileManager.default.isExecutableFile(atPath: bin) ? bin : nil
    }

    static func findBundledOrPath(_ name: String) -> String? {
        let bundle = Bundle.main
        let candidates = [
            bundle.resourcePath.map { $0 + "/bin/\(name)" },
            bundle.bundlePath + "/Contents/Resources/bin/\(name)",
            bundle.bundlePath + "/Contents/MacOS/\(name)",
        ].compactMap { $0 }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func optionalExecutable(_ path: String) -> String? {
        FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - env / prefs

    private static func baseEnvironment(
        profile: WWNMachineProfile,
        ready: String,
        done: String,
        desktop: Bool
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let runtime = WWNPreferencesManager.preferredSharedRuntimeDir()
        env["WAWONA_RUNTIME"] = runtime
        env["XDG_RUNTIME_DIR"] = runtime
        env["WAYLAND_DISPLAY"] = "wayland-0"
        env["WAWONA_CONTAINER_BACKEND"] = "containerization"
        env["WAWONA_CONTAINER_READY_FILE"] = ready
        env["WAWONA_CONTAINER_DONE_FILE"] = done

        if let resourcesBin = Bundle.main.resourcePath.map({ $0 + "/bin" }),
           FileManager.default.fileExists(atPath: resourcesBin) {
            let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "\(resourcesBin):\(existing)"
        }

        let store = UserDefaults.standard.string(forKey: kWWNPrefsMachineContainerImageStore) ?? ""
        if !store.isEmpty {
            env["WWN_OCI_ROOT"] = (store as NSString).expandingTildeInPath
        } else if env["WWN_OCI_ROOT"] == nil {
            env["WWN_OCI_ROOT"] = NSHomeDirectory() + "/.local/share/wwn-oci"
        }

        let kernelPref = WWNPreferencesManager.sharedManager().containerKernelPath()
        if !kernelPref.isEmpty {
            env["WAWONA_VM_KERNEL"] = (kernelPref as NSString).expandingTildeInPath
        }
        let initfsPref = WWNPreferencesManager.sharedManager().containerInitfsPath()
        if !initfsPref.isEmpty {
            env["WAWONA_VM_INITFS"] = (initfsPref as NSString).expandingTildeInPath
        }

        if desktop {
            if let host = findBundledOrPath("waypipe-fds")
                ?? findBundledOrPath("waypipe")
                ?? optionalExecutable("/tmp/wawona-waypipe-splitfd/bin/waypipe")
                ?? optionalExecutable(
                    NSString(string: "~/Wawona/wwn-containers/result-waypipe-splitfd/bin/waypipe")
                        .expandingTildeInPath
                ) {
                env["WWNP_WAYPIPE_BIN"] = host
            }
            if let root = findWaypipeGuestRoot() {
                env["WAWONA_WAYPIPE_GUEST_ROOT"] = root
                env["WAWONA_WAYPIPE_GUEST"] =
                    (root as NSString).appendingPathComponent("bin/waypipe")
            }
            env.removeValue(forKey: "WAWONA_WAYPIPE_NO_GPU")
            let disableGpu = WWNMachineProfileStore.resolvedWaypipeDisableGpu(for: profile)
            if disableGpu {
                env["WAWONA_WAYPIPE_NO_GPU"] = "1"
            }
        }
        return env
    }

    private static func prefsImage() -> String? {
        trimmed(WWNPreferencesManager.sharedManager().containerDefaultImage())
    }

    private static func prefsCommand() -> String? {
        trimmed(WWNPreferencesManager.sharedManager().containerDefaultCommand())
    }

    private static func prefsMemory() -> String? {
        trimmed(WWNPreferencesManager.sharedManager().containerMemory())
    }

    private static func vsockPort(_ cs: [String: Any]) -> Int {
        if let n = number(cs, "vsockPort"), n > 0 { return n }
        let pref = Int(WWNPreferencesManager.sharedManager().containerVsockPort()) ?? 0
        return pref > 0 ? pref : 1042
    }

    private static func wantsDesktop(_ cs: [String: Any]) -> Bool {
        if cs["desktopSession"] == nil { return true }
        return bool(cs, "desktopSession")
    }

    private static func containerId(for machineId: String) -> String {
        "wawona-" + machineId.replacingOccurrences(of: "/", with: "_")
    }

    private static func normalizeImageRef(_ ref: String) -> String {
        if ref.contains("/") { return ref }
        // Short names like alpine:3.20 → docker.io/library/alpine:3.20
        return "docker.io/library/\(ref)"
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool {
        if let b = dict[key] as? Bool { return b }
        if let n = dict[key] as? NSNumber { return n.boolValue }
        if let s = dict[key] as? String {
            return s == "1" || s.lowercased() == "true"
        }
        return false
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Int? {
        if let n = dict[key] as? Int { return n }
        if let n = dict[key] as? NSNumber { return n.intValue }
        if let s = dict[key] as? String, let v = Int(s) { return v }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for v in values {
            if let t = trimmed(v) { return t }
        }
        return nil
    }
}

#endif
