#if os(macOS)
import AppKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Applies Rust `darwin_cli` plans. Host ops stay Swift; argv policy is Rust.
enum WawonaDarwinCLI {
    private struct Plan: Decodable {
        let kind: String
        let message: String?
        let exit_code: Int?
        let query: String?
        let recipe: String?
        let headless: Bool?
        let action: String?
        let machine: String?
        let compositor_host: Bool?
        let menubar: Bool?
        let show_settings: Bool?
        let show_about: Bool?
        let settings_section: String?
        let force_gui: Bool?
        let client: String?
        let backend: String?
    }

    /// Side effects for the Regular UI / host after early-exit plans are done.
    struct LaunchHints {
        var autoStartMachineId: String?
        var backend: String?
        var headless: Bool = false
        var showAbout: Bool = false
    }

    private static var hints = LaunchHints()

    static var launchHints: LaunchHints { hints }

    /// Handle informational / Mode B / run / machines. Returns exit code to
    /// terminate the process, or nil to continue into LaunchMode.
    static func dispatchEarlyExit() -> Int32? {
        guard let plan = parsePlan() else {
            return nil
        }
        switch plan.kind {
        case "help":
            printHelp()
            return 0
        case "version":
            WawonaLaunchMode.printVersion()
            return 0
        case "list_clients":
            printListClients()
            return 0
        case "list_machines":
            return printListMachines()
        case "machines_show":
            return printMachineShow(plan.query ?? "")
        case "run":
            return handleRun(recipe: plan.recipe ?? "", headless: plan.headless ?? false)
        case "mode_b":
            return handleModeB(action: plan.action ?? "", machine: plan.machine)
        case "error":
            let msg = plan.message ?? "CLI error"
            if (plan.exit_code ?? 2) == 0 {
                print(msg)
            } else {
                fputs("Wawona: \(msg)\n", stderr)
            }
            return Int32(plan.exit_code ?? 2)
        case "launch":
            applyLaunchHints(plan)
            return nil
        default:
            return nil
        }
    }

    private static func applyLaunchHints(_ plan: Plan) {
        hints.headless = plan.headless ?? false
        hints.showAbout = plan.show_about ?? false
        hints.backend = plan.backend
        if let backend = plan.backend, !backend.isEmpty {
            UserDefaults.standard.set(backend, forKey: "CompositorBackend")
        }
        var machineId = plan.machine
        if let client = plan.client, !client.isEmpty, machineId == nil {
            var err: NSError?
            if let ensured = WWNCLIMachineRecipes.ensureProfile(forRecipe: client, error: &err) {
                machineId = ensured.machineId
                print("Machine \(ensured.name) (\(ensured.machineId)) ready.")
            } else {
                fputs(
                    "Wawona: \(err?.localizedDescription ?? "ensure failed")\n",
                    stderr
                )
            }
        }
        hints.autoStartMachineId = machineId
        if let mid = machineId, !mid.isEmpty {
            setenv("WWN_AUTO_START_MACHINE", mid, 1)
        }
    }

    private static func handleRun(recipe: String, headless: Bool) -> Int32? {
        if recipe == "--help" || recipe == "-h" || recipe.isEmpty {
            WWNCLIMachineRecipes.printRecipeHelp()
            return recipe.isEmpty ? 2 : 0
        }
        var err: NSError?
        guard let ensured = WWNCLIMachineRecipes.ensureProfile(forRecipe: recipe, error: &err) else {
            fputs(
                "Wawona: \(err?.localizedDescription ?? "ensure failed")\n",
                stderr
            )
            return 2
        }
        print("Machine \(ensured.name) (\(ensured.machineId)) ready. Starting…")
        hints.autoStartMachineId = ensured.machineId
        hints.headless = headless
        setenv("WWN_AUTO_START_MACHINE", ensured.machineId, 1)
        if headless {
            // Compositor-host path: Main will see hints.headless.
            return nil
        }
        return nil
    }

    private static func handleModeB(action: String, machine: String?) -> Int32 {
        let ctl = WWNDesktopReplacementController.sharedController
        if let machine, !machine.isEmpty {
            let sel = ctl.cliSelectDesktopMachine(machine)
            if sel != 0 { return sel }
            if action == "select" { return 0 }
        } else if action == "select" {
            fputs("Wawona: --mode-b-machine requires an id/name (or weston)\n", stderr)
            return 2
        }
        switch action {
        case "status": return ctl.cliStatus()
        case "ready": return ctl.cliReady()
        case "prepare": return ctl.cliPrepare()
        case "stage": return ctl.cliStage()
        case "probe": return ctl.cliEngage(keepWindowServer: true)
        case "engage": return ctl.cliEngage(keepWindowServer: false)
        case "disengage": return ctl.cliDisengage()
        default:
            fputs("Wawona: unknown Mode B action '\(action)'\n", stderr)
            return 2
        }
    }

    private static func printHelp() {
        if let text = callNoArg("wawona_darwin_cli_help"), !text.isEmpty {
            print(text, terminator: "")
            return
        }
        WawonaLaunchMode.printHelp()
    }

    private static func printListClients() {
        if let json = callNoArg("wawona_client_catalog_json"),
           let data = json.data(using: .utf8),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            print("Bundled client ids (pass to --client):")
            for row in rows {
                if let id = row["id"] as? String {
                    print("  \(id)")
                }
            }
            return
        }
        print("Bundled client ids (pass to --client):")
        for id in [
            "weston", "niri", "weston-simple-egl", "weston-simple-shm",
            "weston-terminal", "foot", "opengl-cube", "vkcube", "kmscube",
        ] {
            print("  \(id)")
        }
    }

    private static func printListMachines() -> Int32 {
        let profiles = WWNMachineProfileStore.loadProfiles()
        if profiles.isEmpty {
            print("No Machines profiles saved yet.")
            return 0
        }
        print(String(format: "%-28s  %-16s  %@", "MACHINE ID", "TYPE", "NAME"))
        for p in profiles {
            print(String(
                format: "%-28s  %-16s  %@",
                p.machineId, p.type, p.name
            ))
        }
        return 0
    }

    private static func printMachineShow(_ query: String) -> Int32 {
        guard let p = WWNCLIMachineRecipes.profileMatching(idOrName: query) else {
            fputs("Wawona: no machine matching '\(query)'\n", stderr)
            return 1
        }
        print("id:      \(p.machineId)")
        print("name:    \(p.name)")
        print("type:    \(p.type)")
        if let origin = p.runtimeOverrides[kWWNMachineOrigin] as? String {
            print("origin:  \(origin)")
        }
        if let key = p.runtimeOverrides[kWWNCLIRecipeKey] as? String {
            print("recipe:  \(key)")
        }
        if let cmd = p.containerSettings["entryCommand"] as? String, !cmd.isEmpty {
            print("command: \(cmd)")
        }
        return 0
    }

    private static func parsePlan() -> Plan? {
        if let json = callParseArgv(),
           let data = json.data(using: .utf8),
           let plan = try? JSONDecoder().decode(Plan.self, from: data)
        {
            return plan
        }
        return nil
    }

    private static func callParseArgv() -> String? {
        typealias ParseFn = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> UnsafeMutablePointer<CChar>?
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        guard let parseSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_darwin_cli_parse"),
              let freeSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_domain_string_free")
        else {
            return nil
        }
        let parse = unsafeBitCast(parseSym, to: ParseFn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        return CommandLine.unsafeArgv.withMemoryRebound(
            to: UnsafePointer<CChar>?.self,
            capacity: Int(CommandLine.argc)
        ) { ptr in
            guard let raw = parse(CommandLine.argc, ptr) else { return nil }
            defer { freeFn(raw) }
            return String(cString: raw)
        }
    }

    private static func callNoArg(_ name: String) -> String? {
        typealias Fn = @convention(c) () -> UnsafeMutablePointer<CChar>?
        typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name),
              let freeSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "wawona_domain_string_free")
        else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let freeFn = unsafeBitCast(freeSym, to: FreeFn.self)
        guard let raw = fn() else { return nil }
        defer { freeFn(raw) }
        return String(cString: raw)
    }
}
#endif
