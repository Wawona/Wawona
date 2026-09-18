import Foundation

// MARK: - Override action

/// Persisted env override: set a value or force-unset.
public struct EnvironmentOverride: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Hashable, Sendable {
        case set
        case unset
    }

    public var action: Action
    public var value: String?

    public init(action: Action, value: String? = nil) {
        self.action = action
        self.value = value
    }

    public static func set(_ value: String) -> EnvironmentOverride {
        EnvironmentOverride(action: .set, value: value)
    }

    public static var unset: EnvironmentOverride {
        EnvironmentOverride(action: .unset, value: nil)
    }
}

public typealias EnvironmentOverrideMap = [String: EnvironmentOverride]

// MARK: - Catalog

public enum EnvironmentMutability: String, Codable, Hashable, Sendable, CaseIterable {
    case computed
    case managed
    case defaulted
    case user
    case secret
}

public enum EnvironmentCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case session
    case graphics
    case shell
    case xdg
    case fonts
    case input
    case debug
    case secrets
    case user
}

public struct EnvironmentCatalogEntry: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var category: EnvironmentCategory
    public var mutability: EnvironmentMutability
    public var ownedBy: String?
    /// Literal default, or a resolver token (e.g. `waylandDisplay`, `term`).
    public var defaultToken: String
    public var resettable: Bool
    public var help: String?

    public init(
        name: String,
        category: EnvironmentCategory,
        mutability: EnvironmentMutability,
        ownedBy: String? = nil,
        defaultToken: String = "",
        resettable: Bool = true,
        help: String? = nil
    ) {
        self.name = name
        self.category = category
        self.mutability = mutability
        self.ownedBy = ownedBy
        self.defaultToken = defaultToken
        self.resettable = resettable
        self.help = help
    }

    public var documentation: EnvironmentVariableDoc {
        EnvironmentCatalog.documentation(for: name)
    }
}

// MARK: - Documentation Catalog

/// Structured documentation for an environment variable.
public struct EnvironmentVariableDoc: Sendable, Hashable, Codable {
    public var summary: String
    /// Comprehensive description explaining exactly what the variable does.
    public var details: String
    /// Typical default value.
    public var typicalDefault: String
    /// Realistic override examples.
    public var examples: [String]

    public init(
        summary: String,
        details: String,
        typicalDefault: String,
        examples: [String] = []
    ) {
        self.summary = summary
        self.details = details
        self.typicalDefault = typicalDefault
        self.examples = examples
    }
}

/// Keep in sync with `contracts/environment-catalog.yaml` (#157 / #158).
public enum EnvironmentCatalog {
    public static let storageKey = "wawona.pref.environment.v1"

    public static let entries: [EnvironmentCatalogEntry] = [
        // Session
        .init(name: "XDG_RUNTIME_DIR", category: .session, mutability: .computed, defaultToken: "xdgRuntimeDir", help: "Runtime directory for the Wayland socket."),
        .init(name: "WAYLAND_DISPLAY", category: .session, mutability: .managed, ownedBy: "waylandDisplay", defaultToken: "waylandDisplay", help: "Socket name clients connect to."),
        .init(name: "WAYLAND_SOCKET", category: .session, mutability: .computed, defaultToken: "", help: "Inherited fd socket; usually cleared for multi-client launches."),
        .init(name: "WAWONA_NESTED_WAYLAND_DISPLAY", category: .session, mutability: .computed, defaultToken: "nestedWaylandDisplay"),
        .init(name: "WAWONA_NESTED_WAYLAND", category: .session, mutability: .computed, defaultToken: "1", help: "Nested weston sizes from xdg_toplevel instead of parent wl_output.mode."),
        .init(name: "WAWONA_OUTPUT_SCALE", category: .session, mutability: .computed, defaultToken: "outputScale"),
        .init(name: "NIRI_BACKEND", category: .session, mutability: .managed, ownedBy: "compositorBackend", defaultToken: "niriBackend", help: "Mapped from Display Backend."),
        .init(name: "NIRI_CONFIG", category: .session, mutability: .computed, defaultToken: "niriConfig"),
        .init(name: "WESTON_CONFIG_FILE", category: .session, mutability: .computed, defaultToken: "westonConfigFile"),
        .init(name: "WESTON_DATA_DIR", category: .session, mutability: .computed, defaultToken: "westonDataDir"),
        .init(name: "WESTON_MODULE_DIR", category: .session, mutability: .computed, defaultToken: "westonModuleDir"),
        .init(name: "WESTON_BACKEND_DIR", category: .session, mutability: .computed, defaultToken: "westonBackendDir"),
        // Graphics
        .init(name: "VK_DRIVER_FILES", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanIcd"),
        .init(name: "VK_ICD_FILENAMES", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanIcd"),
        .init(name: "WWN_VULKAN_LIBRARY", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanLibrary"),
        .init(name: "WWN_VULKAN_LIBRARY_FALLBACKS", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanFallbacks"),
        .init(name: "WWN_VULKAN_DRIVER", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "vulkanDriver"),
        .init(name: "WWN_OPENGL_DRIVER", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: "openGLDriver"),
        .init(name: "WWN_DISABLE_VULKAN", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: ""),
        .init(name: "WWN_DISABLE_EGL", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: ""),
        .init(name: "ANGLE_DEFAULT_PLATFORM", category: .graphics, mutability: .managed, ownedBy: "openGLDriver", defaultToken: "anglePlatform"),
        .init(name: "WWN_SWIFTSHADER_LIBRARY", category: .graphics, mutability: .managed, ownedBy: "vulkanDriver", defaultToken: "swiftshaderLibrary"),
        // Shell
        .init(name: "HOME", category: .shell, mutability: .computed, defaultToken: "home"),
        .init(name: "USER", category: .shell, mutability: .defaulted, defaultToken: "mobile"),
        .init(name: "LOGNAME", category: .shell, mutability: .defaulted, defaultToken: "mobile"),
        .init(name: "SHELL", category: .shell, mutability: .computed, defaultToken: "shell"),
        .init(name: "WAWONA_SHELL", category: .shell, mutability: .computed, defaultToken: "shell"),
        .init(name: "WAWONA_ZSH_IN_PROCESS", category: .shell, mutability: .defaulted, defaultToken: "1"),
        .init(name: "TERM", category: .shell, mutability: .defaulted, defaultToken: "xterm-256color", help: "Terminal type for PTY / weston-terminal."),
        .init(name: "PATH", category: .shell, mutability: .computed, defaultToken: "path"),
        .init(name: "ZDOTDIR", category: .shell, mutability: .computed, defaultToken: "home"),
        .init(name: "WAWONA_ROOTFS", category: .shell, mutability: .computed, defaultToken: "rootfs"),
        .init(name: "WAWONA_BUNDLE_ROOTFS", category: .shell, mutability: .computed, defaultToken: "bundleRootfs"),
        .init(name: "WAWONA_FILES_DIR", category: .shell, mutability: .computed, defaultToken: "filesDir"),
        .init(name: "PROMPT", category: .shell, mutability: .defaulted, defaultToken: "%F{cyan}%~%f %# "),
        .init(name: "PS1", category: .shell, mutability: .defaulted, defaultToken: "%F{cyan}%~%f %# "),
        // XDG
        .init(name: "XDG_CONFIG_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgConfigHome"),
        .init(name: "XDG_CACHE_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgCacheHome"),
        .init(name: "XDG_DATA_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgDataHome"),
        .init(name: "XDG_STATE_HOME", category: .xdg, mutability: .computed, defaultToken: "xdgStateHome"),
        .init(name: "XDG_DATA_DIRS", category: .xdg, mutability: .computed, defaultToken: "xdgDataDirs"),
        // Fonts / input
        .init(name: "FONTCONFIG_FILE", category: .fonts, mutability: .computed, defaultToken: "fontconfigFile"),
        .init(name: "FONTCONFIG_PATH", category: .fonts, mutability: .computed, defaultToken: "fontconfigPath"),
        .init(name: "WAWONA_MONO_FONT", category: .fonts, mutability: .computed, defaultToken: "monoFont"),
        .init(name: "WAWONA_SANS_FONT", category: .fonts, mutability: .computed, defaultToken: "sansFont"),
        .init(name: "WAWONA_TERMINAL_FONT_SIZE", category: .fonts, mutability: .defaulted, defaultToken: "12"),
        .init(name: "XKB_CONFIG_ROOT", category: .input, mutability: .computed, defaultToken: "xkbConfigRoot"),
        .init(name: "XKB_DEFAULT_LAYOUT", category: .input, mutability: .defaulted, defaultToken: "us"),
        .init(name: "XKB_DEFAULT_VARIANT", category: .input, mutability: .defaulted, defaultToken: ""),
        .init(name: "XCURSOR_PATH", category: .fonts, mutability: .computed, defaultToken: "xcursorPath"),
        .init(name: "XCURSOR_THEME", category: .fonts, mutability: .defaulted, defaultToken: "Adwaita"),
        // Debug
        .init(name: "RUST_LOG", category: .debug, mutability: .managed, ownedBy: "logLevel", defaultToken: "rustLog", help: "Mapped from Log Level."),
        .init(name: "RUST_BACKTRACE", category: .debug, mutability: .defaulted, defaultToken: "1"),
        .init(name: "WAWONA_AUTO_CMD", category: .debug, mutability: .computed, defaultToken: ""),
        // Secrets
        .init(name: "SSHPASS", category: .secrets, mutability: .secret, ownedBy: "sshPassword", defaultToken: "", resettable: false),
        .init(name: "WAYPIPE_SSH_PASSWORD", category: .secrets, mutability: .secret, ownedBy: "sshPassword", defaultToken: "", resettable: false),
    ]

    public static var byName: [String: EnvironmentCatalogEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    public static var catalogNames: Set<String> {
        Set(entries.map(\.name))
    }

    public static var uiEntries: [EnvironmentCatalogEntry] {
        entries.filter { $0.mutability != .secret }
    }

    /// Comprehensive documentation catalog. Contains zero emdashes.
    public static func documentation(for name: String) -> EnvironmentVariableDoc {
        if let doc = documentedEntries[name] {
            return doc
        }
        return EnvironmentVariableDoc(
            summary: "Custom user-defined environment variable.",
            details: "Custom environment variable configured by the user. Passed directly to launched Wayland clients, compositor instances, and shell environments.",
            typicalDefault: "(none, user defined)",
            examples: ["1", "true", "/custom/path", "debug"]
        )
    }

    private static let documentedEntries: [String: EnvironmentVariableDoc] = [
        // MARK: Session / Compositor
        "XDG_RUNTIME_DIR": EnvironmentVariableDoc(
            summary: "Runtime directory for Wayland sockets and IPC.",
            details: "Base directory path where user-specific runtime files, UNIX domain sockets, and IPC endpoints reside. Wayland compositors such as Wawona, Weston, and Niri bind their listening sockets in this directory. Client applications inspect this variable to discover and connect to the active Wayland compositor socket.",
            typicalDefault: "App sandboxed temporary directory (for example /tmp or container tmp)",
            examples: ["/tmp", "/var/run/user/501", "/tmp/wawona-runtime"]
        ),
        "WAYLAND_DISPLAY": EnvironmentVariableDoc(
            summary: "Wayland compositor socket filename.",
            details: "Name of the Wayland socket file that client applications connect to inside XDG_RUNTIME_DIR. When a Wayland client initializes its display connection, it connects to XDG_RUNTIME_DIR/WAYLAND_DISPLAY. If multiple compositors run concurrently, each uses a distinct socket name.",
            typicalDefault: "wayland-0",
            examples: ["wayland-0", "wayland-1", "wayland-wawona"]
        ),
        "WAYLAND_SOCKET": EnvironmentVariableDoc(
            summary: "Pre-opened file descriptor for inherited Wayland connections.",
            details: "File descriptor number representing an existing open Wayland connection passed directly from a parent process. When present, Wayland clients connect over this file descriptor instead of looking up WAYLAND_DISPLAY in XDG_RUNTIME_DIR. Wawona clears this variable by default when launching independent multi-client sessions.",
            typicalDefault: "(unset)",
            examples: ["3", "4", "5"]
        ),
        "WAWONA_NESTED_WAYLAND_DISPLAY": EnvironmentVariableDoc(
            summary: "Socket name for nested compositor instances.",
            details: "Designates the Wayland socket name created and managed by an inner nested compositor instance (such as nested Weston or Niri) running inside Wawona. Applications targeted to run within the nested workspace connect to this socket.",
            typicalDefault: "wayland-1",
            examples: ["wayland-1", "wayland-nested", "wayland-2"]
        ),
        "WAWONA_NESTED_WAYLAND": EnvironmentVariableDoc(
            summary: "Enables nested Wayland geometry negotiation.",
            details: "Boolean flag enabling nested Wayland mode. When set to 1, nested Weston computes its surface sizing from the parent xdg_toplevel geometry rather than the raw physical wl_output display mode, preventing incorrect display scaling in nested windows.",
            typicalDefault: "1",
            examples: ["1", "0"]
        ),
        "WAWONA_OUTPUT_SCALE": EnvironmentVariableDoc(
            summary: "Display scale factor for Wayland clients.",
            details: "Integer or fractional scale factor advertised to Wayland client surfaces through wl_output events. A value of 1 corresponds to standard 72/96 DPI rendering, while 2 or 3 enables high-DPI Retina and Super Retina rendering for sharp text and UI assets.",
            typicalDefault: "1 (or matching host display scale, such as 2 or 3)",
            examples: ["1", "2", "3", "1.5"]
        ),
        "NIRI_BACKEND": EnvironmentVariableDoc(
            summary: "Hardware and display backend for Niri.",
            details: "Selects the rendering and input backend for the Niri scrollable-tiling Wayland compositor. Mapped from the Wawona Display Backend setting. Use 'nested' when Niri runs inside an existing window, or 'tty' when running under userspace DRM/KMS.",
            typicalDefault: "nested (or tty for DRM mode)",
            examples: ["nested", "tty", "drm"]
        ),
        "NIRI_CONFIG": EnvironmentVariableDoc(
            summary: "Filesystem path to Niri configuration file.",
            details: "Path to the configuration file (config.kdl) read by the Niri compositor on startup. Controls workspace keybindings, layout dimensions, border colors, window animations, and touch gestures.",
            typicalDefault: "Generated path in Application Support or bundle",
            examples: ["/path/to/custom-config.kdl", "$XDG_CONFIG_HOME/niri/config.kdl"]
        ),
        "WESTON_CONFIG_FILE": EnvironmentVariableDoc(
            summary: "Filesystem path to Weston configuration file.",
            details: "Path to the configuration file (weston.ini) loaded by the Weston compositor. Configures desktop panels, taskbar launchers, keyboard repeat rates, background color, shell plugins, and idle timeout periods.",
            typicalDefault: "Generated weston.ini in Application Support or bundle",
            examples: ["/path/to/weston.ini", "$HOME/.config/weston.ini"]
        ),
        "WESTON_DATA_DIR": EnvironmentVariableDoc(
            summary: "Directory path for Weston static assets.",
            details: "Path where Weston looks for shared assets, including icon images, sound themes, default wallpapers, and pattern files used by the desktop shell.",
            typicalDefault: "App bundle share/weston directory",
            examples: ["/usr/share/weston", "/var/containers/Bundle/.../share/weston"]
        ),
        "WESTON_MODULE_DIR": EnvironmentVariableDoc(
            summary: "Directory path for Weston plugin modules.",
            details: "Path where Weston looks for installable shell and extension modules, such as desktop-shell.so, fullscreen-shell.so, and color management dynamic libraries.",
            typicalDefault: "App bundle lib/weston directory",
            examples: ["/usr/lib/weston", "/var/containers/Bundle/.../lib/weston"]
        ),
        "WESTON_BACKEND_DIR": EnvironmentVariableDoc(
            summary: "Directory path for Weston backend dynamic libraries.",
            details: "Path where Weston loads output rendering backend plugins, such as wayland-backend.so, drm-backend.so, and headless-backend.so.",
            typicalDefault: "App bundle lib/weston directory",
            examples: ["/usr/lib/weston", "/var/containers/Bundle/.../lib/weston"]
        ),

        // MARK: Graphics / Drivers
        "VK_DRIVER_FILES": EnvironmentVariableDoc(
            summary: "Manifest paths for the Vulkan loader.",
            details: "Colon-separated list of JSON manifest file paths used by modern Vulkan loaders to discover and initialize Installable Client Drivers (ICD), such as MoltenVK or SwiftShader.",
            typicalDefault: "Path to bundled MoltenVK ICD manifest",
            examples: ["/path/to/MoltenVK_icd.json", "/usr/share/vulkan/icd.d/moltenvk.json"]
        ),
        "VK_ICD_FILENAMES": EnvironmentVariableDoc(
            summary: "Legacy Vulkan ICD manifest paths.",
            details: "Legacy environment variable used by older versions of the Khronos Vulkan loader to locate ICD manifest files. Maintained alongside VK_DRIVER_FILES for backward compatibility with older client builds.",
            typicalDefault: "Path to bundled MoltenVK ICD manifest",
            examples: ["/path/to/MoltenVK_icd.json"]
        ),
        "WWN_VULKAN_LIBRARY": EnvironmentVariableDoc(
            summary: "Primary Vulkan implementation library path.",
            details: "Absolute path to the active Vulkan dynamic library (such as libMoltenVK.dylib or libvulkan.so) loaded directly by in-process graphics clients in Wawona.",
            typicalDefault: "App bundle lib/libMoltenVK.dylib",
            examples: ["/path/to/libMoltenVK.dylib", "/path/to/libvk_swiftshader.dylib"]
        ),
        "WWN_VULKAN_LIBRARY_FALLBACKS": EnvironmentVariableDoc(
            summary: "Fallback Vulkan library search paths.",
            details: "Colon-separated list of alternative Vulkan dynamic library paths attempted if WWN_VULKAN_LIBRARY fails to load or does not export required symbols.",
            typicalDefault: "Fallback paths in app bundle lib directory",
            examples: ["/path/to/fallback1.dylib:/path/to/fallback2.dylib"]
        ),
        "WWN_VULKAN_DRIVER": EnvironmentVariableDoc(
            summary: "Active Vulkan driver identifier token.",
            details: "Specifies which Vulkan driver pipeline is selected. Owned and synchronized by the Wawona Vulkan Driver setting in preferences.",
            typicalDefault: "moltenvk",
            examples: ["moltenvk", "swiftshader", "none"]
        ),
        "WWN_OPENGL_DRIVER": EnvironmentVariableDoc(
            summary: "Active OpenGL/GLES driver identifier token.",
            details: "Specifies which OpenGL ES implementation is used for client surfaces and compositor rendering. Owned and synchronized by the Wawona OpenGL Driver setting in preferences.",
            typicalDefault: "angle",
            examples: ["angle", "mesa", "none"]
        ),
        "WWN_DISABLE_VULKAN": EnvironmentVariableDoc(
            summary: "Force disable Vulkan graphics pipeline.",
            details: "When set to 1, completely disables Vulkan loader initialization and driver queries across Wawona and child clients, forcing fallbacks to OpenGL ES or software rasterization.",
            typicalDefault: "(unset)",
            examples: ["1", "0"]
        ),
        "WWN_DISABLE_EGL": EnvironmentVariableDoc(
            summary: "Force disable EGL graphics pipeline.",
            details: "When set to 1, prevents EGL display initialization and context creation, forcing applications to rely on pure software rendering or alternative display protocols.",
            typicalDefault: "(unset)",
            examples: ["1", "0"]
        ),
        "ANGLE_DEFAULT_PLATFORM": EnvironmentVariableDoc(
            summary: "Underlying rendering backend for ANGLE.",
            details: "Controls which native hardware API the Google ANGLE library uses to translate OpenGL ES commands into hardware draw calls. Typically uses Metal on Apple platforms and Vulkan on Android or Linux.",
            typicalDefault: "metal (on Apple) or vulkan (on Android/Linux)",
            examples: ["metal", "vulkan", "opengl", "swiftshader"]
        ),
        "WWN_SWIFTSHADER_LIBRARY": EnvironmentVariableDoc(
            summary: "Path to Google SwiftShader software rasterizer.",
            details: "Filesystem path to the Google SwiftShader CPU software rasterizer library, used when hardware GPU acceleration is unavailable or intentionally bypassed for debugging.",
            typicalDefault: "App bundle lib/libvk_swiftshader.dylib (if bundled)",
            examples: ["/path/to/libvk_swiftshader.dylib", "/path/to/libvk_swiftshader.so"]
        ),

        // MARK: Shell / Runtime Environment
        "HOME": EnvironmentVariableDoc(
            summary: "User home directory path.",
            details: "Standard UNIX home directory for user accounts. Shell configuration files (.zshrc, .profile), dotfiles, application cache directories, and personal documents are located relative to this path.",
            typicalDefault: "App sandbox Documents or user home directory",
            examples: ["/var/mobile/Containers/Data/Application/.../Documents", "/Users/username", "/home/mobile"]
        ),
        "USER": EnvironmentVariableDoc(
            summary: "Current UNIX username.",
            details: "Username of the active user account for shell sessions, process credentials, file ownership checks, and command prompt expansions.",
            typicalDefault: "mobile",
            examples: ["mobile", "root", "wawona", "user"]
        ),
        "LOGNAME": EnvironmentVariableDoc(
            summary: "Login name of the active user.",
            details: "System login name recorded for accounting, session managers, and logging utilities. Generally matches the value of USER.",
            typicalDefault: "mobile",
            examples: ["mobile", "root", "user"]
        ),
        "SHELL": EnvironmentVariableDoc(
            summary: "Default interactive command shell binary.",
            details: "Path to the preferred interactive command interpreter executed when launching terminal windows, subshells, or automated scripts.",
            typicalDefault: "/bin/zsh (or bundled zsh binary)",
            examples: ["/bin/zsh", "/bin/bash", "/bin/sh"]
        ),
        "WAWONA_SHELL": EnvironmentVariableDoc(
            summary: "Executable path for Wawona built-in shell.",
            details: "Direct filesystem path to the shell binary selected to run inside Wawona terminal emulators and embedded machine consoles.",
            typicalDefault: "Bundled zsh or sh executable",
            examples: ["/bin/zsh", "/var/containers/Bundle/.../bin/zsh"]
        ),
        "WAWONA_ZSH_IN_PROCESS": EnvironmentVariableDoc(
            summary: "Controls whether Zsh runs in-process.",
            details: "Boolean flag enabling in-process Zsh execution. Essential on iOS and sandboxed environments where posix_spawn and fork are restricted by system sandbox policies.",
            typicalDefault: "1",
            examples: ["1", "0"]
        ),
        "TERM": EnvironmentVariableDoc(
            summary: "Terminal capabilities identifier string.",
            details: "Identifies the terminal emulation standard and capability entry in the terminfo database. Informs text editors, pagers, and ncurses applications about color depth, cursor movement, and key escape sequences.",
            typicalDefault: "xterm-256color",
            examples: ["xterm-256color", "xterm-color", "vt100", "screen-256color"]
        ),
        "PATH": EnvironmentVariableDoc(
            summary: "Search path list for executable binaries.",
            details: "Colon-separated list of directory paths that the shell searches in order when a command is executed without an explicit directory path prefix.",
            typicalDefault: "/usr/bin:/bin:/usr/sbin:/sbin (including bundled tool paths)",
            examples: ["/usr/local/bin:/usr/bin:/bin", "/bin:/usr/bin:$HOME/bin"]
        ),
        "ZDOTDIR": EnvironmentVariableDoc(
            summary: "Zsh configuration directory path.",
            details: "Directory where Zsh searches for startup scripts (.zshenv, .zprofile, .zshrc, .zlogin, .zlogout) instead of defaulting to HOME.",
            typicalDefault: "Same as HOME",
            examples: ["$HOME", "$HOME/.config/zsh", "/etc/zsh"]
        ),
        "WAWONA_ROOTFS": EnvironmentVariableDoc(
            summary: "Active writable root filesystem path.",
            details: "Root directory path of the active machine container or sandbox, containing the Linux or UNIX directory tree hierarchy (bin, etc, lib, usr, var).",
            typicalDefault: "App sandboxed writable rootfs directory",
            examples: ["/var/mobile/Containers/Data/.../Documents/rootfs", "/tmp/rootfs"]
        ),
        "WAWONA_BUNDLE_ROOTFS": EnvironmentVariableDoc(
            summary: "Bundled read-only rootfs template path.",
            details: "Path to the read-only template root filesystem included inside the Wawona application bundle, used to populate new machine environments.",
            typicalDefault: "App bundle rootfs directory",
            examples: ["/var/containers/Bundle/.../Wawona.app/rootfs"]
        ),
        "WAWONA_FILES_DIR": EnvironmentVariableDoc(
            summary: "Internal data storage directory path.",
            details: "Internal files directory on Android and embedded platforms where Wawona stores persistent database files, machine state, and dynamic assets.",
            typicalDefault: "Android app internal files directory",
            examples: ["/data/user/0/io.wawona.app/files"]
        ),
        "PROMPT": EnvironmentVariableDoc(
            summary: "Primary prompt string format for Zsh.",
            details: "Formatted string defining the prompt displayed by Zsh before each interactive command entry. Supports color codes, current directory (%~), and privilege markers (%#).",
            typicalDefault: "%F{cyan}%~%f %# ",
            examples: ["%F{cyan}%~%f %# ", "%n@%m %~ %# ", "> "]
        ),
        "PS1": EnvironmentVariableDoc(
            summary: "POSIX standard primary prompt string.",
            details: "Standard command prompt format used by Bourne-compatible shells like sh and bash, as well as fallback prompt for Zsh sessions.",
            typicalDefault: "%F{cyan}%~%f %# ",
            examples: ["\\u@\\h:\\w$ ", "$ ", "%F{green}%n%f$ "]
        ),

        // MARK: XDG Base Directories
        "XDG_CONFIG_HOME": EnvironmentVariableDoc(
            summary: "User configuration files base directory.",
            details: "Defines the base directory relative to which user-specific configuration files are written and loaded, following the XDG Base Directory Specification.",
            typicalDefault: "$HOME/.config",
            examples: ["$HOME/.config", "/tmp/config"]
        ),
        "XDG_CACHE_HOME": EnvironmentVariableDoc(
            summary: "User non-essential cache base directory.",
            details: "Defines the base directory for non-essential user-specific cache data files that can be recreated or deleted without loss of essential state.",
            typicalDefault: "$HOME/.cache",
            examples: ["$HOME/.cache", "/tmp/cache"]
        ),
        "XDG_DATA_HOME": EnvironmentVariableDoc(
            summary: "User data files base directory.",
            details: "Defines the base directory for user-specific data files such as locally installed plugins, themes, and application state databases.",
            typicalDefault: "$HOME/.local/share",
            examples: ["$HOME/.local/share", "/tmp/share"]
        ),
        "XDG_STATE_HOME": EnvironmentVariableDoc(
            summary: "User state files base directory.",
            details: "Defines the base directory for state data that should persist across restarts (such as application window geometry, command history, and session logs).",
            typicalDefault: "$HOME/.local/state",
            examples: ["$HOME/.local/state", "/tmp/state"]
        ),
        "XDG_DATA_DIRS": EnvironmentVariableDoc(
            summary: "System data search paths.",
            details: "Colon-separated list of system directories searched in order for shared desktop entries, mime definitions, application icons, and sound files.",
            typicalDefault: "App bundle share directory (for example /usr/local/share:/usr/share)",
            examples: ["/usr/local/share:/usr/share", "$HOME/.local/share:/usr/share"]
        ),

        // MARK: Fonts and Input
        "FONTCONFIG_FILE": EnvironmentVariableDoc(
            summary: "Main Fontconfig configuration file path.",
            details: "Direct filesystem path to the XML configuration file (fonts.conf) loaded by fontconfig. Governs font matching algorithms, aliases, antialiasing rules, and hinting parameters.",
            typicalDefault: "App bundle share/fontconfig/fonts.conf",
            examples: ["/etc/fonts/fonts.conf", "/path/to/custom-fonts.conf"]
        ),
        "FONTCONFIG_PATH": EnvironmentVariableDoc(
            summary: "Fontconfig configuration search directory.",
            details: "Directory path where fontconfig searches for configuration files and modular rule directories (such as conf.d).",
            typicalDefault: "App bundle share/fontconfig",
            examples: ["/etc/fonts", "/usr/share/fontconfig"]
        ),
        "WAWONA_MONO_FONT": EnvironmentVariableDoc(
            summary: "Default monospaced font family or PostScript name.",
            details: "Font name used when rendering monospaced text in terminal emulators, code viewers, and status displays.",
            typicalDefault: "SF Mono (or bundled monospaced font like Menlo / DejaVu Sans Mono)",
            examples: ["SF Mono", "Menlo", "Courier New", "DejaVu Sans Mono"]
        ),
        "WAWONA_SANS_FONT": EnvironmentVariableDoc(
            summary: "Default sans-serif font family or PostScript name.",
            details: "Font name used for proportional text in menus, buttons, title bars, and user interface dialogs.",
            typicalDefault: "System Sans font (for example SF Pro Text / Helvetica / DejaVu Sans)",
            examples: ["SF Pro", "Helvetica", "Arial", "DejaVu Sans"]
        ),
        "WAWONA_TERMINAL_FONT_SIZE": EnvironmentVariableDoc(
            summary: "Terminal font size in points.",
            details: "Point size used by the terminal emulator font rasterizer for cell dimensions and character glyph rendering.",
            typicalDefault: "12",
            examples: ["10", "12", "14", "16"]
        ),
        "XKB_CONFIG_ROOT": EnvironmentVariableDoc(
            summary: "XKB keyboard rules and keymap root directory.",
            details: "Root directory path containing XKB configuration databases, including symbols, rules, types, and geometry descriptions used by xkbcommon to translate raw scan codes into characters.",
            typicalDefault: "App bundle share/X11/xkb directory",
            examples: ["/usr/share/X11/xkb", "/var/containers/Bundle/.../share/X11/xkb"]
        ),
        "XKB_DEFAULT_LAYOUT": EnvironmentVariableDoc(
            summary: "Default keyboard layout code.",
            details: "Standard two-letter country or layout code (such as us, gb, de, fr, es, jp) used to configure the default keyboard keymap.",
            typicalDefault: "us",
            examples: ["us", "gb", "de", "fr", "es", "jp"]
        ),
        "XKB_DEFAULT_VARIANT": EnvironmentVariableDoc(
            summary: "Default keyboard layout variant.",
            details: "Sub-variant modifier for the active keyboard layout (such as dvorak, colemak, or altgr-intl).",
            typicalDefault: "(empty / standard)",
            examples: ["dvorak", "colemak", "intl", "altgr-intl"]
        ),
        "XCURSOR_PATH": EnvironmentVariableDoc(
            summary: "Cursor theme directory search paths.",
            details: "Colon-separated list of directories searched by libwayland-cursor and X11 libraries when loading mouse cursor graphics.",
            typicalDefault: "App bundle share/icons directory",
            examples: ["/usr/share/icons:~/.icons", "$HOME/.icons:/usr/share/icons"]
        ),
        "XCURSOR_THEME": EnvironmentVariableDoc(
            summary: "Active cursor theme name.",
            details: "Name of the cursor icon set used for pointer rendering (such as Adwaita, default, or breeze_cursors).",
            typicalDefault: "Adwaita",
            examples: ["Adwaita", "default", "breeze_cursors"]
        ),

        // MARK: Debug and Diagnostics
        "RUST_LOG": EnvironmentVariableDoc(
            summary: "Logging filter for Rust components.",
            details: "Directs log output filtering for compiled Rust modules in Wawona, Niri, Relay, and Smithay. Supports log levels (error, warn, info, debug, trace) as well as per-module target filters. Synchronized with the Wawona Log Level setting unless overridden.",
            typicalDefault: "info",
            examples: ["debug", "trace", "warn", "error", "wawona=debug,smithay=info"]
        ),
        "RUST_BACKTRACE": EnvironmentVariableDoc(
            summary: "Rust panic backtrace verbosity.",
            details: "Controls whether Rust runtime panics generate detailed call stack traces in log output. Set to 1 for standard backtraces or 'full' for verbose symbol details.",
            typicalDefault: "1",
            examples: ["1", "full", "0"]
        ),
        "WAWONA_AUTO_CMD": EnvironmentVariableDoc(
            summary: "Automatic command executed on shell startup.",
            details: "Command string or script automatically sent to the shell session or terminal immediately upon startup (for example launching phoon, htop, or neofetch).",
            typicalDefault: "(unset)",
            examples: ["phoon", "neofetch", "htop", "uname -a"]
        ),

        // MARK: Secrets
        "SSHPASS": EnvironmentVariableDoc(
            summary: "SSH password for non-interactive logins.",
            details: "Password stored in memory for non-interactive SSH authentication with sshpass. Managed by Machine SSH Settings and hidden in the user interface for privacy.",
            typicalDefault: "(set by Machine SSH Settings)",
            examples: ["(configured via Machine Settings -> SSH)"]
        ),
        "WAYPIPE_SSH_PASSWORD": EnvironmentVariableDoc(
            summary: "SSH password for Waypipe remote sessions.",
            details: "Password passed to waypipe when initiating remote Wayland display forwarding over SSH. Managed by Machine SSH Settings and hidden in the user interface for privacy.",
            typicalDefault: "(set by Machine SSH Settings)",
            examples: ["(configured via Machine Settings -> SSH)"]
        ),
    ]
}

// MARK: - Resolved row

public enum EnvironmentValueSource: String, Hashable, Sendable {
    case catalogDefault = "Wawona default"
    case firstClassSetting = "Settings"
    case globalOverride = "Global"
    case machineOverride = "This machine"
    case session = "Session"
    case host = "Host"
    case userExtra = "User"
}

public struct ResolvedEnvironmentEntry: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var value: String?
    /// True when the resolved action is unset (variable should not be present).
    public var isUnset: Bool
    public var source: EnvironmentValueSource
    public var mutability: EnvironmentMutability
    public var category: EnvironmentCategory
    public var ownedBy: String?
    public var help: String?
    public var isOverridden: Bool
    public var isSecret: Bool

    public init(
        name: String,
        value: String?,
        isUnset: Bool = false,
        source: EnvironmentValueSource,
        mutability: EnvironmentMutability,
        category: EnvironmentCategory,
        ownedBy: String? = nil,
        help: String? = nil,
        isOverridden: Bool = false,
        isSecret: Bool = false
    ) {
        self.name = name
        self.value = value
        self.isUnset = isUnset
        self.source = source
        self.mutability = mutability
        self.category = category
        self.ownedBy = ownedBy
        self.help = help
        self.isOverridden = isOverridden
        self.isSecret = isSecret
    }

    /// Display value for UI (secrets never show real content).
    public var displayValue: String {
        if isSecret { return "(set by SSH Settings)" }
        if isUnset { return "(unset)" }
        return value ?? ""
    }

    public var documentation: EnvironmentVariableDoc {
        EnvironmentCatalog.documentation(for: name)
    }
}

// MARK: - Session context (computed / managed defaults)

/// Values the platform fills at resolve time (socket paths, drivers, rootfs, …).
public struct EnvironmentSessionContext: Hashable, Sendable {
    public var waylandDisplay: String
    public var xdgRuntimeDir: String
    public var nestedWaylandDisplay: String
    public var outputScale: String
    public var niriBackend: String
    public var niriConfig: String
    public var westonConfigFile: String
    public var westonDataDir: String
    public var westonModuleDir: String
    public var westonBackendDir: String
    public var vulkanIcd: String
    public var vulkanLibrary: String
    public var vulkanFallbacks: String
    public var vulkanDriver: String
    public var openGLDriver: String
    public var anglePlatform: String
    public var swiftshaderLibrary: String
    public var disableVulkan: Bool
    public var disableEGL: Bool
    public var home: String
    public var shell: String
    public var path: String
    public var rootfs: String
    public var bundleRootfs: String
    public var filesDir: String
    public var xdgConfigHome: String
    public var xdgCacheHome: String
    public var xdgDataHome: String
    public var xdgStateHome: String
    public var xdgDataDirs: String
    public var fontconfigFile: String
    public var fontconfigPath: String
    public var monoFont: String
    public var sansFont: String
    public var xkbConfigRoot: String
    public var xcursorPath: String
    public var rustLog: String
    public var userName: String

    public init(
        waylandDisplay: String = "wayland-0",
        xdgRuntimeDir: String = "",
        nestedWaylandDisplay: String = "",
        outputScale: String = "1",
        niriBackend: String = "nested",
        niriConfig: String = "",
        westonConfigFile: String = "",
        westonDataDir: String = "",
        westonModuleDir: String = "",
        westonBackendDir: String = "",
        vulkanIcd: String = "",
        vulkanLibrary: String = "",
        vulkanFallbacks: String = "",
        vulkanDriver: String = "moltenvk",
        openGLDriver: String = "angle",
        anglePlatform: String = "metal",
        swiftshaderLibrary: String = "",
        disableVulkan: Bool = false,
        disableEGL: Bool = false,
        home: String = "",
        shell: String = "/usr/bin/zsh",
        path: String = "/usr/bin:/bin",
        rootfs: String = "",
        bundleRootfs: String = "",
        filesDir: String = "",
        xdgConfigHome: String = "",
        xdgCacheHome: String = "",
        xdgDataHome: String = "",
        xdgStateHome: String = "",
        xdgDataDirs: String = "",
        fontconfigFile: String = "",
        fontconfigPath: String = "",
        monoFont: String = "",
        sansFont: String = "",
        xkbConfigRoot: String = "",
        xcursorPath: String = "",
        rustLog: String = "info",
        userName: String = "mobile"
    ) {
        self.waylandDisplay = waylandDisplay
        self.xdgRuntimeDir = xdgRuntimeDir
        self.nestedWaylandDisplay = nestedWaylandDisplay
        self.outputScale = outputScale
        self.niriBackend = niriBackend
        self.niriConfig = niriConfig
        self.westonConfigFile = westonConfigFile
        self.westonDataDir = westonDataDir
        self.westonModuleDir = westonModuleDir
        self.westonBackendDir = westonBackendDir
        self.vulkanIcd = vulkanIcd
        self.vulkanLibrary = vulkanLibrary
        self.vulkanFallbacks = vulkanFallbacks
        self.vulkanDriver = vulkanDriver
        self.openGLDriver = openGLDriver
        self.anglePlatform = anglePlatform
        self.swiftshaderLibrary = swiftshaderLibrary
        self.disableVulkan = disableVulkan
        self.disableEGL = disableEGL
        self.home = home
        self.shell = shell
        self.path = path
        self.rootfs = rootfs
        self.bundleRootfs = bundleRootfs
        self.filesDir = filesDir
        self.xdgConfigHome = xdgConfigHome
        self.xdgCacheHome = xdgCacheHome
        self.xdgDataHome = xdgDataHome
        self.xdgStateHome = xdgStateHome
        self.xdgDataDirs = xdgDataDirs
        self.fontconfigFile = fontconfigFile
        self.fontconfigPath = fontconfigPath
        self.monoFont = monoFont
        self.sansFont = sansFont
        self.xkbConfigRoot = xkbConfigRoot
        self.xcursorPath = xcursorPath
        self.rustLog = rustLog
        self.userName = userName
    }

    public func resolveToken(_ token: String) -> String? {
        switch token {
        case "", "empty": return ""
        case "waylandDisplay": return waylandDisplay
        case "xdgRuntimeDir": return xdgRuntimeDir
        case "nestedWaylandDisplay": return nestedWaylandDisplay
        case "outputScale": return outputScale
        case "niriBackend": return niriBackend
        case "niriConfig": return niriConfig
        case "westonConfigFile": return westonConfigFile
        case "westonDataDir": return westonDataDir
        case "westonModuleDir": return westonModuleDir
        case "westonBackendDir": return westonBackendDir
        case "vulkanIcd": return vulkanIcd
        case "vulkanLibrary": return vulkanLibrary
        case "vulkanFallbacks": return vulkanFallbacks
        case "vulkanDriver": return vulkanDriver
        case "openGLDriver": return openGLDriver
        case "anglePlatform": return anglePlatform
        case "swiftshaderLibrary": return swiftshaderLibrary
        case "home": return home
        case "shell": return shell
        case "path": return path
        case "rootfs": return rootfs
        case "bundleRootfs": return bundleRootfs
        case "filesDir": return filesDir
        case "xdgConfigHome": return xdgConfigHome
        case "xdgCacheHome": return xdgCacheHome
        case "xdgDataHome": return xdgDataHome
        case "xdgStateHome": return xdgStateHome
        case "xdgDataDirs": return xdgDataDirs
        case "fontconfigFile": return fontconfigFile
        case "fontconfigPath": return fontconfigPath
        case "monoFont": return monoFont
        case "sansFont": return sansFont
        case "xkbConfigRoot": return xkbConfigRoot
        case "xcursorPath": return xcursorPath
        case "rustLog": return rustLog
        case "mobile": return userName
        default:
            // Literal default stored as the token itself (e.g. xterm-256color).
            return token
        }
    }
}

// MARK: - Merge / reset

public enum EnvironmentResolver {
    /// Banned on Apple-mobile local shell spawn even if user extras set them.
    public static let strippedLocalShellPrefixes = ["DYLD_", "LD_"]

    public static func isBannedLocalShellKey(_ name: String) -> Bool {
        strippedLocalShellPrefixes.contains { name.hasPrefix($0) }
    }

    public static func decodeMap(from data: Data?) -> EnvironmentOverrideMap {
        guard let data, !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode(EnvironmentOverrideMap.self, from: data)) ?? [:]
    }

    public static func encodeMap(_ map: EnvironmentOverrideMap) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    /// Reset one key (delete override → inherit).
    public static func resetOne(_ map: inout EnvironmentOverrideMap, name: String) {
        map.removeValue(forKey: name)
    }

    /// Drop overrides for catalog names; keep user extras.
    public static func resetWawonaManaged(_ map: inout EnvironmentOverrideMap) {
        let catalog = EnvironmentCatalog.catalogNames
        map = map.filter { !catalog.contains($0.key) }
    }

    public static func resetAll(_ map: inout EnvironmentOverrideMap) {
        map.removeAll()
    }

    /// Merge precedence: machine > global > first-class/session defaults.
    public static func resolve(
        globalOverrides: EnvironmentOverrideMap,
        machineOverrides: EnvironmentOverrideMap,
        session: EnvironmentSessionContext,
        includeSecrets: Bool = false,
        stripBannedLocalShellKeys: Bool = false
    ) -> [ResolvedEnvironmentEntry] {
        var rows: [ResolvedEnvironmentEntry] = []
        var seen = Set<String>()

        for entry in EnvironmentCatalog.entries {
            if entry.mutability == .secret && !includeSecrets {
                rows.append(ResolvedEnvironmentEntry(
                    name: entry.name,
                    value: nil,
                    isUnset: false,
                    source: .firstClassSetting,
                    mutability: .secret,
                    category: entry.category,
                    ownedBy: entry.ownedBy,
                    help: entry.help,
                    isOverridden: false,
                    isSecret: true
                ))
                seen.insert(entry.name)
                continue
            }

            let resolved = resolveOne(
                name: entry.name,
                catalog: entry,
                globalOverrides: globalOverrides,
                machineOverrides: machineOverrides,
                session: session
            )
            rows.append(resolved)
            seen.insert(entry.name)
        }

        // User extras not in catalog.
        let extraKeys = Set(globalOverrides.keys).union(machineOverrides.keys).subtracting(seen)
        for name in extraKeys.sorted() {
            if stripBannedLocalShellKeys && isBannedLocalShellKey(name) { continue }
            let resolved = resolveOne(
                name: name,
                catalog: EnvironmentCatalogEntry(
                    name: name,
                    category: .user,
                    mutability: .user,
                    defaultToken: ""
                ),
                globalOverrides: globalOverrides,
                machineOverrides: machineOverrides,
                session: session
            )
            rows.append(resolved)
        }

        if stripBannedLocalShellKeys {
            rows = rows.filter { !isBannedLocalShellKey($0.name) }
        }

        return rows.sorted { $0.name < $1.name }
    }

    /// Flat name → value for spawn/setenv (omits unset and secrets unless requested).
    public static func applyMap(
        from rows: [ResolvedEnvironmentEntry],
        includeSecrets: Bool = false
    ) -> [String: String] {
        var out: [String: String] = [:]
        for row in rows {
            if row.isSecret && !includeSecrets { continue }
            if row.isUnset { continue }
            if let value = row.value {
                out[row.name] = value
            }
        }
        return out
    }

    /// Names that should be unsetenv'd.
    public static func unsetNames(from rows: [ResolvedEnvironmentEntry]) -> [String] {
        rows.filter(\.isUnset).map(\.name)
    }

    private static func resolveOne(
        name: String,
        catalog: EnvironmentCatalogEntry,
        globalOverrides: EnvironmentOverrideMap,
        machineOverrides: EnvironmentOverrideMap,
        session: EnvironmentSessionContext
    ) -> ResolvedEnvironmentEntry {
        if let machine = machineOverrides[name] {
            return entry(from: machine, name: name, catalog: catalog, source: .machineOverride, overridden: true)
        }
        if let global = globalOverrides[name] {
            return entry(from: global, name: name, catalog: catalog, source: .globalOverride, overridden: true)
        }

        // First-class / computed defaults from session.
        let (value, source) = catalogDefault(catalog: catalog, session: session)
        return ResolvedEnvironmentEntry(
            name: name,
            value: value,
            isUnset: false,
            source: source,
            mutability: catalog.mutability,
            category: catalog.category,
            ownedBy: catalog.ownedBy,
            help: catalog.help,
            isOverridden: false,
            isSecret: catalog.mutability == .secret
        )
    }

    private static func entry(
        from override: EnvironmentOverride,
        name: String,
        catalog: EnvironmentCatalogEntry,
        source: EnvironmentValueSource,
        overridden: Bool
    ) -> ResolvedEnvironmentEntry {
        switch override.action {
        case .unset:
            return ResolvedEnvironmentEntry(
                name: name,
                value: nil,
                isUnset: true,
                source: source,
                mutability: catalog.mutability,
                category: catalog.category,
                ownedBy: catalog.ownedBy,
                help: catalog.help,
                isOverridden: overridden,
                isSecret: catalog.mutability == .secret
            )
        case .set:
            return ResolvedEnvironmentEntry(
                name: name,
                value: override.value ?? "",
                isUnset: false,
                source: source,
                mutability: catalog.mutability,
                category: catalog.category,
                ownedBy: catalog.ownedBy,
                help: catalog.help,
                isOverridden: overridden,
                isSecret: catalog.mutability == .secret
            )
        }
    }

    private static func catalogDefault(
        catalog: EnvironmentCatalogEntry,
        session: EnvironmentSessionContext
    ) -> (String?, EnvironmentValueSource) {
        switch catalog.mutability {
        case .secret:
            return (nil, .firstClassSetting)
        case .computed:
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .session)
        case .managed:
            // Special managed toggles.
            if catalog.name == "WWN_DISABLE_VULKAN" {
                return (session.disableVulkan ? "1" : nil, .firstClassSetting)
            }
            if catalog.name == "WWN_DISABLE_EGL" {
                return (session.disableEGL ? "1" : nil, .firstClassSetting)
            }
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .firstClassSetting)
        case .defaulted:
            let v = session.resolveToken(catalog.defaultToken)
            return (v, .catalogDefault)
        case .user:
            return (nil, .userExtra)
        }
    }

    /// Map CompositorBackend setting → NIRI_BACKEND value.
    public static func niriBackend(for compositorBackend: String) -> String {
        switch compositorBackend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drm", "tty": return "tty"
        default: return "nested"
        }
    }

    /// Map logLevel → RUST_LOG.
    public static func rustLog(for logLevel: String) -> String {
        switch logLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug": return "debug"
        case "warn", "warning": return "warn"
        case "error": return "error"
        default: return "info"
        }
    }
}
