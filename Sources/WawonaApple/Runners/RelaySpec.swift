extension WWNRelay {
    static func platformToken() -> String {
        #if os(macOS)
        return "macos"
        #elseif os(iOS)
        return "ios"
        #elseif os(tvOS)
        return "tvos"
        #elseif os(watchOS)
        return "watchos"
        #elseif os(visionOS)
        return "visionos"
        #else
        return "ios"
        #endif
    }

    static func artifactClass() -> String {
        #if WWN_MODE_B
        return "mode_b"
        #else
        return "mode_a"
        #endif
    }

    static func kind(for profile: WWNMachineProfile) -> String? {
        let t = profile.type ?? ""
        if t == "virtual_machine" { return "vm" }
        if t == "container" { return "container" }
        if t == "wasm" { return "wasm" }
        if let bundled = profile.runtimeOverrides["bundledAppID"] as? String {
            if bundled == "wawona-wasm" || bundled == "hello-wasi-gui" { return "wasm" }
        }
        return nil
    }

    static func specJSON(profile: WWNMachineProfile, kind: String) -> String {
        var obj: [String: Any] = [
            "kind": kind,
            "platform": platformToken(),
            "artifact": artifactClass(),
            "image": imageRef(profile: profile, kind: kind),
            "apple_os_major": ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        ]
        if wwn_wasmer_webkit_available() != 0 {
            obj["wasmer_webkit_linked"] = true
        }
        var machineId = profile.machineId
        let vmSettings = profile.vmSettings
        if let configured = vmSettings["vmIdentifier"] as? String, !configured.isEmpty {
            machineId = configured
        }
        if !machineId.isEmpty { obj["machine_id"] = machineId }

        if kind == "vm" || kind == "container" {
            if let guestBlock = guestResources(profile: profile, vmSettings: vmSettings) {
                obj["guest"] = guestBlock.guest
                obj["resources"] = guestBlock.resources
                obj["memory_mb"] = guestBlock.memoryMB
                obj["disk_gib"] = guestBlock.diskGiB
                obj["max_disk_gib"] = guestBlock.maxDiskGiB
                if let gen = guestBlock.nixosGeneration { obj["nixos_generation"] = gen }
                if let dir = guestBlock.resources["guest_directory"] as? String {
                    NSLog("[WWNRelay] guest_directory=%@", dir)
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8)
        else {
            NSLog("[WWNRelay] specJSON: JSONSerialization failed for kind=%@", kind)
            return "{\"kind\":\"\(kind)\",\"platform\":\"\(platformToken())\",\"artifact\":\"\(artifactClass())\"}"
        }
        return json
    }

    static func imageRef(profile: WWNMachineProfile, kind: String) -> String {
        if let img = profile.runtimeOverrides["imageRef"] as? String, !img.isEmpty { return img }
        if kind == "container",
           let cref = profile.containerSettings["containerRef"] as? String { return cref }
        return ""
    }

    struct GuestBlock {
        let guest: Any
        let resources: [String: Any]
        let memoryMB: UInt
        let diskGiB: UInt
        let maxDiskGiB: UInt
        let nixosGeneration: Int?
    }

    /// Resolve the Mode A NixOS guest tree (`Image` + `initrd` + `rootfs.img` +
    /// `manifest.json`). App Store builds ship this inside the `.app` (Guideline
    /// 2.5.2: self-contained; do not download guest kernels/rootfs). Lab/TF may
    /// also stage under Application Support when the IPA omits the multi-gig
    /// tree. `path(forResource:)` alone misses guests ditto'd onto the bundle
    /// root after install — always probe `resourcePath` / `bundlePath` too.
    @objc(resolveGuestDirectoryForVariant:)
    public static func resolveGuestDirectory(variant: String) -> String? {
        var guestVariant = variant
        if guestVariant != "4k", guestVariant != "16k" { guestVariant = "4k" }
        let name = "wawona-nixos-guest-\(guestVariant)"
        let fm = FileManager.default
        let bundle = Bundle.main
        var candidates: [String] = []
        if let viaResource = bundle.path(forResource: name, ofType: nil) {
            candidates.append(viaResource)
        }
        for root in [bundle.resourcePath, bundle.bundlePath].compactMap({ $0 }) {
            candidates.append((root as NSString).appendingPathComponent(name))
        }
        if let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.path {
            candidates.append(support + "/Wawona/guests/\(name)")
        }
        var seen = Set<String>()
        for dir in candidates where seen.insert(dir).inserted {
            let manifest = (dir as NSString).appendingPathComponent("manifest.json")
            if fm.isReadableFile(atPath: manifest) {
                return dir
            }
        }
        return nil
    }

    /// True when a readable guest manifest is available (bundled or staged).
    @objc(hasGuestManifestForVariant:)
    public static func hasGuestManifest(variant: String = "4k") -> Bool {
        resolveGuestDirectory(variant: variant) != nil
    }

    static func guestResources(profile: WWNMachineProfile, vmSettings: [String: Any]) -> GuestBlock? {
        let bundle = Bundle.main
        let resourcesRoot = bundle.resourcePath ?? ""
        #if os(macOS)
        let launcher = (resourcesRoot as NSString).appendingPathComponent("bin/wawona-vz-run")
        #else
        let launcher = ""
        #endif
        var guestVariant = vmSettings["guestVariant"] as? String ?? "4k"
        if guestVariant != "4k", guestVariant != "16k" { guestVariant = "4k" }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let stateDir = (appSupport?.path ?? NSTemporaryDirectory()) + "/Wawona/relay-state"
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        guard let guestDir = resolveGuestDirectory(variant: guestVariant) else {
            return nil
        }
        let manifestPath = (guestDir as NSString).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let memoryMB = unsigned(vmSettings["memoryMB"], default: 2048)
        let diskGiB = unsigned(vmSettings["diskGiB"], default: 8)
        let maxDiskGiB = unsigned(vmSettings["maxDiskGiB"], default: 64)
        var nixGen: Int?
        if let gen = vmSettings["nixosGeneration"] as? NSNumber {
            let n = gen.intValue
            if n > 0, n <= 1_000_000 { nixGen = n }
        }
        let resources: [String: Any] = [
            "launcher": launcher,
            "state_directory": stateDir,
            "guest_directory": guestDir,
            "allow_unsigned_guest": true,
        ]
        return GuestBlock(
            guest: manifest, resources: resources,
            memoryMB: memoryMB, diskGiB: diskGiB, maxDiskGiB: maxDiskGiB,
            nixosGeneration: nixGen
        )
    }

    static func unsigned(_ value: Any?, default def: UInt) -> UInt {
        if let n = value as? NSNumber { return n.uintValue }
        return def
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

