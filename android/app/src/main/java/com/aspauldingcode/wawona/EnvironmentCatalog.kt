package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Tune
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Keep in sync with `contracts/environment-catalog.yaml` and
 * `Sources/WawonaModel/EnvironmentVariables.swift` EnvironmentCatalog.
 */
enum class EnvironmentCategory(
    val displayName: String,
    val icon: ImageVector,
    val accent: Color,
) {
    SESSION("Session", Icons.Filled.Tune, Color(0xFF007AFF)),
    GRAPHICS("Graphics", Icons.Filled.Palette, Color(0xFFAF52DE)),
    SHELL("Shell", Icons.Filled.Terminal, Color(0xFFFF9500)),
    XDG("XDG", Icons.Filled.Folder, Color(0xFF5956D6)),
    FONTS("Fonts", Icons.AutoMirrored.Filled.List, Color(0xFF30B0C7)),
    INPUT("Input", Icons.Filled.Keyboard, Color(0xFF34C759)),
    DEBUG("Debug", Icons.Filled.BugReport, Color(0xFFFF3B30)),
    USER("User", Icons.Filled.Person, Color(0xFF00C7BE)),
}

enum class EnvironmentMutability {
    COMPUTED,
    MANAGED,
    DEFAULTED,
    USER,
    SECRET,
}

data class EnvironmentVariableDoc(
    val summary: String,
    val details: String,
    val typicalDefault: String,
    val examples: List<String> = emptyList(),
)

data class EnvironmentCatalogEntry(
    val name: String,
    val category: EnvironmentCategory,
    val mutability: EnvironmentMutability,
    val ownedBy: String? = null,
    val defaultToken: String = "",
    val help: String? = null,
)

data class ResolvedEnvironmentEntry(
    val name: String,
    val value: String?,
    val isUnset: Boolean,
    val category: EnvironmentCategory,
    val mutability: EnvironmentMutability,
    val ownedBy: String?,
    val help: String?,
    val isOverridden: Boolean,
    val typicalDefault: String,
    val documentation: EnvironmentVariableDoc,
) {
    val displayValue: String
        get() = when {
            isUnset -> "(Unset)"
            isOverridden && (value.isNullOrEmpty()) -> "(Empty)"
            isOverridden -> value.orEmpty()
            value.isNullOrEmpty() -> "(Default)"
            else -> value.orEmpty()
        }
}

object EnvironmentCatalog {
    val entries: List<EnvironmentCatalogEntry> = listOf(
        // Session
        e("XDG_RUNTIME_DIR", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "xdgRuntimeDir", "Runtime directory for the Wayland socket."),
        e("WAYLAND_DISPLAY", EnvironmentCategory.SESSION, EnvironmentMutability.MANAGED, "waylandDisplay", "Socket name clients connect to.", ownedBy = "waylandDisplay"),
        e("WAYLAND_SOCKET", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "", "Inherited fd socket; usually cleared for multi-client launches."),
        e("WAWONA_NESTED_WAYLAND_DISPLAY", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "nestedWaylandDisplay"),
        e("WAWONA_NESTED_WAYLAND", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "1", "Nested weston sizes from xdg_toplevel instead of parent wl_output.mode."),
        e("WAWONA_OUTPUT_SCALE", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "outputScale"),
        e("NIRI_BACKEND", EnvironmentCategory.SESSION, EnvironmentMutability.MANAGED, "niriBackend", "Mapped from Display Backend.", ownedBy = "compositorBackend"),
        e("NIRI_CONFIG", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "niriConfig"),
        e("WESTON_CONFIG_FILE", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "westonConfigFile"),
        e("WESTON_DATA_DIR", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "westonDataDir"),
        e("WESTON_MODULE_DIR", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "westonModuleDir"),
        e("WESTON_BACKEND_DIR", EnvironmentCategory.SESSION, EnvironmentMutability.COMPUTED, "westonBackendDir"),
        // Graphics
        e("VK_DRIVER_FILES", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "vulkanIcd", ownedBy = "vulkanDriver"),
        e("VK_ICD_FILENAMES", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "vulkanIcd", ownedBy = "vulkanDriver"),
        e("WWN_VULKAN_LIBRARY", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "vulkanLibrary", ownedBy = "vulkanDriver"),
        e("WWN_VULKAN_LIBRARY_FALLBACKS", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "vulkanFallbacks", ownedBy = "vulkanDriver"),
        e("WWN_VULKAN_DRIVER", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "vulkanDriver", ownedBy = "vulkanDriver"),
        e("WWN_OPENGL_DRIVER", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "openGLDriver", ownedBy = "openGLDriver"),
        e("WWN_DISABLE_VULKAN", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "", ownedBy = "vulkanDriver"),
        e("WWN_DISABLE_EGL", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "", ownedBy = "openGLDriver"),
        e("ANGLE_DEFAULT_PLATFORM", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "anglePlatform", ownedBy = "openGLDriver"),
        e("WWN_SWIFTSHADER_LIBRARY", EnvironmentCategory.GRAPHICS, EnvironmentMutability.MANAGED, "swiftshaderLibrary", ownedBy = "vulkanDriver"),
        // Shell
        e("HOME", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "home"),
        e("USER", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "mobile"),
        e("LOGNAME", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "mobile"),
        e("SHELL", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "shell"),
        e("WAWONA_SHELL", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "shell"),
        e("WAWONA_ZSH_IN_PROCESS", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "1"),
        e("TERM", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "xterm-256color", "Terminal type for PTY / weston-terminal."),
        e("PATH", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "path"),
        e("ZDOTDIR", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "home"),
        e("WAWONA_ROOTFS", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "rootfs"),
        e("WAWONA_BUNDLE_ROOTFS", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "bundleRootfs"),
        e("WAWONA_FILES_DIR", EnvironmentCategory.SHELL, EnvironmentMutability.COMPUTED, "filesDir"),
        e("PROMPT", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "%F{cyan}%~%f %# "),
        e("PS1", EnvironmentCategory.SHELL, EnvironmentMutability.DEFAULTED, "%F{cyan}%~%f %# "),
        // XDG
        e("XDG_CONFIG_HOME", EnvironmentCategory.XDG, EnvironmentMutability.COMPUTED, "xdgConfigHome"),
        e("XDG_CACHE_HOME", EnvironmentCategory.XDG, EnvironmentMutability.COMPUTED, "xdgCacheHome"),
        e("XDG_DATA_HOME", EnvironmentCategory.XDG, EnvironmentMutability.COMPUTED, "xdgDataHome"),
        e("XDG_STATE_HOME", EnvironmentCategory.XDG, EnvironmentMutability.COMPUTED, "xdgStateHome"),
        e("XDG_DATA_DIRS", EnvironmentCategory.XDG, EnvironmentMutability.COMPUTED, "xdgDataDirs"),
        // Fonts / input
        e("FONTCONFIG_FILE", EnvironmentCategory.FONTS, EnvironmentMutability.COMPUTED, "fontconfigFile"),
        e("FONTCONFIG_PATH", EnvironmentCategory.FONTS, EnvironmentMutability.COMPUTED, "fontconfigPath"),
        e("WAWONA_MONO_FONT", EnvironmentCategory.FONTS, EnvironmentMutability.COMPUTED, "monoFont"),
        e("WAWONA_SANS_FONT", EnvironmentCategory.FONTS, EnvironmentMutability.COMPUTED, "sansFont"),
        e("WAWONA_TERMINAL_FONT_SIZE", EnvironmentCategory.FONTS, EnvironmentMutability.DEFAULTED, "12"),
        e("XKB_CONFIG_ROOT", EnvironmentCategory.INPUT, EnvironmentMutability.COMPUTED, "xkbConfigRoot"),
        e("XKB_DEFAULT_LAYOUT", EnvironmentCategory.INPUT, EnvironmentMutability.DEFAULTED, "us"),
        e("XKB_DEFAULT_VARIANT", EnvironmentCategory.INPUT, EnvironmentMutability.DEFAULTED, ""),
        e("XCURSOR_PATH", EnvironmentCategory.FONTS, EnvironmentMutability.COMPUTED, "xcursorPath"),
        e("XCURSOR_THEME", EnvironmentCategory.FONTS, EnvironmentMutability.DEFAULTED, "Adwaita"),
        // Debug
        e("RUST_LOG", EnvironmentCategory.DEBUG, EnvironmentMutability.MANAGED, "rustLog", "Mapped from Log Level.", ownedBy = "logLevel"),
        e("RUST_BACKTRACE", EnvironmentCategory.DEBUG, EnvironmentMutability.DEFAULTED, "1"),
        e("WAWONA_AUTO_CMD", EnvironmentCategory.DEBUG, EnvironmentMutability.COMPUTED, ""),
    )

    val byName: Map<String, EnvironmentCatalogEntry> = entries.associateBy { it.name }
    val catalogNames: Set<String> = entries.map { it.name }.toSet()
    val uiEntries: List<EnvironmentCatalogEntry> =
        entries.filter { it.mutability != EnvironmentMutability.SECRET }

    fun documentation(forName: String): EnvironmentVariableDoc =
        docs[forName] ?: EnvironmentVariableDoc(
            summary = "Custom user-defined environment variable.",
            details = "Custom environment variable configured by the user. Passed directly to launched Wayland clients, compositor instances, and shell environments.",
            typicalDefault = "(none, user defined)",
            examples = listOf("1", "true", "/custom/path", "debug"),
        )

    fun resolveRows(
        context: Context,
        prefs: SharedPreferences,
        overrides: Map<String, EnvironmentOverrides.Entry>,
    ): List<ResolvedEnvironmentEntry> {
        val tokens = sessionTokens(context, prefs)
        val catalogRows = uiEntries.map { entry ->
            resolveOne(entry, overrides[entry.name], tokens)
        }
        val extras = overrides.keys
            .filter { it !in catalogNames }
            .sorted()
            .map { name ->
                val override = overrides[name]!!
                val doc = documentation(name)
                ResolvedEnvironmentEntry(
                    name = name,
                    value = if (override.action == "unset") null else override.value,
                    isUnset = override.action == "unset",
                    category = EnvironmentCategory.USER,
                    mutability = EnvironmentMutability.USER,
                    ownedBy = null,
                    help = "User-defined override.",
                    isOverridden = true,
                    typicalDefault = doc.typicalDefault,
                    documentation = doc,
                )
            }
        return catalogRows + extras
    }

    private fun resolveOne(
        entry: EnvironmentCatalogEntry,
        override: EnvironmentOverrides.Entry?,
        tokens: Map<String, String>,
    ): ResolvedEnvironmentEntry {
        val doc = documentation(entry.name)
        val defaultValue = resolveToken(entry.defaultToken, tokens) ?: doc.typicalDefault
        return when {
            override?.action == "unset" -> ResolvedEnvironmentEntry(
                name = entry.name,
                value = null,
                isUnset = true,
                category = entry.category,
                mutability = entry.mutability,
                ownedBy = entry.ownedBy,
                help = entry.help,
                isOverridden = true,
                typicalDefault = defaultValue,
                documentation = doc,
            )
            override != null -> ResolvedEnvironmentEntry(
                name = entry.name,
                value = override.value.orEmpty(),
                isUnset = false,
                category = entry.category,
                mutability = entry.mutability,
                ownedBy = entry.ownedBy,
                help = entry.help,
                isOverridden = true,
                typicalDefault = defaultValue,
                documentation = doc,
            )
            else -> ResolvedEnvironmentEntry(
                name = entry.name,
                value = defaultValue.takeIf { it.isNotEmpty() && !it.startsWith("(") },
                isUnset = false,
                category = entry.category,
                mutability = entry.mutability,
                ownedBy = entry.ownedBy,
                help = entry.help,
                isOverridden = false,
                typicalDefault = defaultValue,
                documentation = doc,
            )
        }
    }

    private fun resolveToken(token: String, tokens: Map<String, String>): String? {
        if (token.isEmpty()) return ""
        tokens[token]?.let { return it }
        // camelCase resolver tokens without a live value fall through to docs.
        if (token.first().isLowerCase() && token.any { it.isUpperCase() }) {
            return null
        }
        return token
    }

    private fun sessionTokens(context: Context, prefs: SharedPreferences): Map<String, String> {
        val files = context.filesDir.absolutePath
        val home = "$files/home"
        val vulkan = prefs.getString("vulkanDriver", "System") ?: "System"
        val opengl = prefs.getString("openglDriver", "ANGLE") ?: "ANGLE"
        val backend = prefs.getString("compositorBackend", "auto") ?: "auto"
        val niriBackend = when (backend) {
            "drm" -> "tty"
            "wayland" -> "nested"
            else -> "nested"
        }
        val angle = if (opengl.equals("ANGLE", ignoreCase = true)) "vulkan" else "vulkan"
        return mapOf(
            "waylandDisplay" to "wayland-0",
            "xdgRuntimeDir" to (context.cacheDir.absolutePath),
            "nestedWaylandDisplay" to "wayland-1",
            "outputScale" to "1",
            "niriBackend" to niriBackend,
            "niriConfig" to "$files/niri/config.kdl",
            "westonConfigFile" to "$files/weston.ini",
            "westonDataDir" to "$files/share/weston",
            "westonModuleDir" to "$files/lib/weston",
            "westonBackendDir" to "$files/lib/weston",
            "vulkanIcd" to "",
            "vulkanLibrary" to "",
            "vulkanFallbacks" to "",
            "vulkanDriver" to vulkan.lowercase(),
            "openGLDriver" to opengl.lowercase(),
            "anglePlatform" to angle,
            "swiftshaderLibrary" to "",
            "home" to home,
            "shell" to "$files/bin/zsh",
            "path" to "$files/bin:/system/bin",
            "rootfs" to "$files/rootfs",
            "bundleRootfs" to "$files/bundle-rootfs",
            "filesDir" to files,
            "xdgConfigHome" to "$home/.config",
            "xdgCacheHome" to "$home/.cache",
            "xdgDataHome" to "$home/.local/share",
            "xdgStateHome" to "$home/.local/state",
            "xdgDataDirs" to "$files/share",
            "fontconfigFile" to "$files/share/fontconfig/fonts.conf",
            "fontconfigPath" to "$files/share/fontconfig",
            "monoFont" to "DejaVu Sans Mono",
            "sansFont" to "DejaVu Sans",
            "xkbConfigRoot" to "$files/share/X11/xkb",
            "xcursorPath" to "$files/share/icons",
            "rustLog" to "info",
            "term" to "xterm-256color",
        )
    }

    private fun e(
        name: String,
        category: EnvironmentCategory,
        mutability: EnvironmentMutability,
        defaultToken: String,
        help: String? = null,
        ownedBy: String? = null,
    ) = EnvironmentCatalogEntry(name, category, mutability, ownedBy, defaultToken, help)

    private val docs: Map<String, EnvironmentVariableDoc> = mapOf(
        "XDG_RUNTIME_DIR" to EnvironmentVariableDoc(
            "Runtime directory for Wayland sockets and IPC.",
            "Base directory path where user-specific runtime files, UNIX domain sockets, and IPC endpoints reside. Wayland compositors such as Wawona, Weston, and Niri bind their listening sockets in this directory.",
            "App sandboxed temporary directory",
            listOf("/tmp", "/data/user/0/.../cache"),
        ),
        "WAYLAND_DISPLAY" to EnvironmentVariableDoc(
            "Wayland compositor socket filename.",
            "Name of the Wayland socket file that client applications connect to inside XDG_RUNTIME_DIR.",
            "wayland-0",
            listOf("wayland-0", "wayland-1", "wayland-wawona"),
        ),
        "WAYLAND_SOCKET" to EnvironmentVariableDoc(
            "Pre-opened file descriptor for inherited Wayland connections.",
            "When present, Wayland clients connect over this file descriptor instead of looking up WAYLAND_DISPLAY. Wawona clears this by default for multi-client sessions.",
            "(unset)",
            listOf("3", "4", "5"),
        ),
        "WAWONA_NESTED_WAYLAND_DISPLAY" to EnvironmentVariableDoc(
            "Socket name for nested compositor instances.",
            "Designates the Wayland socket name created by an inner nested compositor instance running inside Wawona.",
            "wayland-1",
            listOf("wayland-1", "wayland-nested"),
        ),
        "WAWONA_NESTED_WAYLAND" to EnvironmentVariableDoc(
            "Enables nested Wayland geometry negotiation.",
            "When set to 1, nested Weston sizes from parent xdg_toplevel geometry rather than raw wl_output mode.",
            "1",
            listOf("1", "0"),
        ),
        "WAWONA_OUTPUT_SCALE" to EnvironmentVariableDoc(
            "Display scale factor for Wayland clients.",
            "Scale factor advertised to Wayland client surfaces through wl_output events.",
            "1",
            listOf("1", "2", "3", "1.5"),
        ),
        "NIRI_BACKEND" to EnvironmentVariableDoc(
            "Hardware and display backend for Niri.",
            "Mapped from the Wawona Display Backend setting. Use nested inside a window, or tty under userspace DRM/KMS.",
            "nested",
            listOf("nested", "tty"),
        ),
        "NIRI_CONFIG" to EnvironmentVariableDoc(
            "Filesystem path to Niri configuration file.",
            "Path to the config.kdl file read by Niri on startup.",
            "Generated path in app files",
            listOf("\$XDG_CONFIG_HOME/niri/config.kdl"),
        ),
        "WESTON_CONFIG_FILE" to EnvironmentVariableDoc(
            "Filesystem path to Weston configuration file.",
            "Path to weston.ini loaded by Weston.",
            "Generated weston.ini in app files",
            listOf("\$HOME/.config/weston.ini"),
        ),
        "WESTON_DATA_DIR" to EnvironmentVariableDoc(
            "Directory path for Weston static assets.",
            "Path where Weston looks for shared assets and desktop shell resources.",
            "App share/weston directory",
            listOf("/usr/share/weston"),
        ),
        "WESTON_MODULE_DIR" to EnvironmentVariableDoc(
            "Directory path for Weston plugin modules.",
            "Path where Weston loads shell and extension modules.",
            "App lib/weston directory",
            emptyList(),
        ),
        "WESTON_BACKEND_DIR" to EnvironmentVariableDoc(
            "Directory path for Weston backend dynamic libraries.",
            "Path where Weston loads output rendering backends.",
            "App lib/weston directory",
            emptyList(),
        ),
        "VK_DRIVER_FILES" to EnvironmentVariableDoc(
            "Manifest paths for the Vulkan loader.",
            "Colon-separated list of JSON ICD manifest paths for the Vulkan loader.",
            "Bundled ICD manifest path",
            emptyList(),
        ),
        "VK_ICD_FILENAMES" to EnvironmentVariableDoc(
            "Legacy Vulkan ICD manifest paths.",
            "Legacy loader variable kept alongside VK_DRIVER_FILES.",
            "Bundled ICD manifest path",
            emptyList(),
        ),
        "WWN_VULKAN_LIBRARY" to EnvironmentVariableDoc(
            "Primary Vulkan implementation library path.",
            "Absolute path to the active Vulkan dynamic library loaded by in-process graphics clients.",
            "App lib Vulkan ICD",
            emptyList(),
        ),
        "WWN_VULKAN_LIBRARY_FALLBACKS" to EnvironmentVariableDoc(
            "Fallback Vulkan library search paths.",
            "Colon-separated alternate Vulkan library paths.",
            "Fallback paths in app lib",
            emptyList(),
        ),
        "WWN_VULKAN_DRIVER" to EnvironmentVariableDoc(
            "Active Vulkan driver identifier token.",
            "Owned by the Wawona Vulkan Driver setting.",
            "system",
            listOf("system", "swiftshader", "none"),
        ),
        "WWN_OPENGL_DRIVER" to EnvironmentVariableDoc(
            "Active OpenGL/GLES driver identifier token.",
            "Owned by the Wawona OpenGL Driver setting.",
            "angle",
            listOf("angle", "system", "none"),
        ),
        "WWN_DISABLE_VULKAN" to EnvironmentVariableDoc(
            "Force disable Vulkan graphics pipeline.",
            "When set to 1, disables Vulkan loader initialization.",
            "(unset)",
            listOf("1", "0"),
        ),
        "WWN_DISABLE_EGL" to EnvironmentVariableDoc(
            "Force disable EGL graphics pipeline.",
            "When set to 1, prevents EGL display initialization.",
            "(unset)",
            listOf("1", "0"),
        ),
        "ANGLE_DEFAULT_PLATFORM" to EnvironmentVariableDoc(
            "Underlying rendering backend for ANGLE.",
            "Controls which native API ANGLE uses. Typically vulkan on Android.",
            "vulkan",
            listOf("vulkan", "opengl", "swiftshader"),
        ),
        "WWN_SWIFTSHADER_LIBRARY" to EnvironmentVariableDoc(
            "Path to Google SwiftShader software rasterizer.",
            "Used when hardware GPU acceleration is unavailable.",
            "(if bundled)",
            emptyList(),
        ),
        "HOME" to EnvironmentVariableDoc(
            "User home directory path.",
            "Standard UNIX home directory for shell sessions and dotfiles.",
            "App sandbox home",
            emptyList(),
        ),
        "USER" to EnvironmentVariableDoc(
            "Current UNIX username.",
            "Username of the active account for shell sessions.",
            "mobile",
            listOf("mobile", "u0_a123"),
        ),
        "LOGNAME" to EnvironmentVariableDoc(
            "Login name of the active user.",
            "Generally matches USER.",
            "mobile",
            emptyList(),
        ),
        "SHELL" to EnvironmentVariableDoc(
            "Default interactive command shell binary.",
            "Path to the preferred interactive command interpreter.",
            "Bundled zsh",
            emptyList(),
        ),
        "WAWONA_SHELL" to EnvironmentVariableDoc(
            "Executable path for Wawona built-in shell.",
            "Shell binary selected for Wawona terminal emulators.",
            "Bundled zsh",
            emptyList(),
        ),
        "WAWONA_ZSH_IN_PROCESS" to EnvironmentVariableDoc(
            "Controls whether Zsh runs in-process.",
            "Boolean flag enabling in-process Zsh execution on sandboxed targets.",
            "1",
            listOf("1", "0"),
        ),
        "TERM" to EnvironmentVariableDoc(
            "Terminal capabilities identifier string.",
            "Identifies the terminal emulation standard for editors and ncurses apps.",
            "xterm-256color",
            listOf("xterm-256color", "xterm-color", "vt100"),
        ),
        "PATH" to EnvironmentVariableDoc(
            "Search path list for executable binaries.",
            "Colon-separated directory list searched for commands.",
            "Bundled and system bin paths",
            emptyList(),
        ),
        "ZDOTDIR" to EnvironmentVariableDoc(
            "Zsh configuration directory path.",
            "Directory where Zsh searches for startup scripts.",
            "Same as HOME",
            emptyList(),
        ),
        "WAWONA_ROOTFS" to EnvironmentVariableDoc(
            "Active writable root filesystem path.",
            "Root directory of the active machine sandbox tree.",
            "App sandboxed rootfs",
            emptyList(),
        ),
        "WAWONA_BUNDLE_ROOTFS" to EnvironmentVariableDoc(
            "Bundled read-only rootfs template path.",
            "Read-only template used to populate new machine environments.",
            "App bundle rootfs",
            emptyList(),
        ),
        "WAWONA_FILES_DIR" to EnvironmentVariableDoc(
            "Internal data storage directory path.",
            "Android internal files directory for persistent Wawona state.",
            "Android app files directory",
            emptyList(),
        ),
        "PROMPT" to EnvironmentVariableDoc(
            "Primary prompt string format for Zsh.",
            "Formatted string defining the Zsh interactive prompt.",
            "%F{cyan}%~%f %# ",
            emptyList(),
        ),
        "PS1" to EnvironmentVariableDoc(
            "POSIX standard primary prompt string.",
            "Prompt format for Bourne-compatible shells.",
            "%F{cyan}%~%f %# ",
            emptyList(),
        ),
        "XDG_CONFIG_HOME" to EnvironmentVariableDoc(
            "User configuration files base directory.",
            "XDG Base Directory for user-specific configuration files.",
            "\$HOME/.config",
            emptyList(),
        ),
        "XDG_CACHE_HOME" to EnvironmentVariableDoc(
            "User non-essential cache base directory.",
            "XDG Base Directory for cache data.",
            "\$HOME/.cache",
            emptyList(),
        ),
        "XDG_DATA_HOME" to EnvironmentVariableDoc(
            "User data files base directory.",
            "XDG Base Directory for user data files.",
            "\$HOME/.local/share",
            emptyList(),
        ),
        "XDG_STATE_HOME" to EnvironmentVariableDoc(
            "User state files base directory.",
            "XDG Base Directory for persistent state data.",
            "\$HOME/.local/state",
            emptyList(),
        ),
        "XDG_DATA_DIRS" to EnvironmentVariableDoc(
            "System data search paths.",
            "Colon-separated system directories for shared desktop data.",
            "App share directory",
            emptyList(),
        ),
        "FONTCONFIG_FILE" to EnvironmentVariableDoc(
            "Main Fontconfig configuration file path.",
            "Path to fonts.conf loaded by fontconfig.",
            "App share/fontconfig/fonts.conf",
            emptyList(),
        ),
        "FONTCONFIG_PATH" to EnvironmentVariableDoc(
            "Fontconfig configuration search directory.",
            "Directory where fontconfig searches for configuration modules.",
            "App share/fontconfig",
            emptyList(),
        ),
        "WAWONA_MONO_FONT" to EnvironmentVariableDoc(
            "Default monospaced font family.",
            "Font used for terminal and monospace UI text.",
            "DejaVu Sans Mono",
            listOf("DejaVu Sans Mono", "monospace"),
        ),
        "WAWONA_SANS_FONT" to EnvironmentVariableDoc(
            "Default sans-serif font family.",
            "Font used for proportional UI text.",
            "DejaVu Sans",
            emptyList(),
        ),
        "WAWONA_TERMINAL_FONT_SIZE" to EnvironmentVariableDoc(
            "Terminal font size in points.",
            "Point size for terminal cell glyph rendering.",
            "12",
            listOf("10", "12", "14", "16"),
        ),
        "XKB_CONFIG_ROOT" to EnvironmentVariableDoc(
            "XKB keyboard rules and keymap root directory.",
            "Root directory for xkbcommon keymap databases.",
            "App share/X11/xkb",
            emptyList(),
        ),
        "XKB_DEFAULT_LAYOUT" to EnvironmentVariableDoc(
            "Default keyboard layout code.",
            "Two-letter layout code such as us, gb, de, fr.",
            "us",
            listOf("us", "gb", "de", "fr"),
        ),
        "XKB_DEFAULT_VARIANT" to EnvironmentVariableDoc(
            "Default keyboard layout variant.",
            "Sub-variant such as dvorak or colemak.",
            "(empty / standard)",
            listOf("dvorak", "colemak", "intl"),
        ),
        "XCURSOR_PATH" to EnvironmentVariableDoc(
            "Cursor theme directory search paths.",
            "Colon-separated directories searched for cursor themes.",
            "App share/icons",
            emptyList(),
        ),
        "XCURSOR_THEME" to EnvironmentVariableDoc(
            "Active cursor theme name.",
            "Name of the cursor icon set used for pointer rendering.",
            "Adwaita",
            listOf("Adwaita", "default"),
        ),
        "RUST_LOG" to EnvironmentVariableDoc(
            "Logging filter for Rust components.",
            "Log filter for Wawona, Niri, Relay, and Smithay Rust modules.",
            "info",
            listOf("debug", "trace", "warn", "wawona=debug"),
        ),
        "RUST_BACKTRACE" to EnvironmentVariableDoc(
            "Rust panic backtrace verbosity.",
            "Controls whether Rust panics generate call stack traces.",
            "1",
            listOf("1", "full", "0"),
        ),
        "WAWONA_AUTO_CMD" to EnvironmentVariableDoc(
            "Automatic command executed on shell startup.",
            "Command sent to the shell session immediately upon startup.",
            "(unset)",
            listOf("phoon", "neofetch", "htop"),
        ),
    )
}
