//! Environment Variables settings page (1:1 with SwiftUI EnvironmentVariablesView
//! and Android Compose EnvironmentVariablesScreen).

use std::cell::RefCell;
use std::collections::{BTreeMap, HashSet};
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::config::LinuxSettings;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EnvCategory {
    Session,
    Graphics,
    Shell,
    Xdg,
    Fonts,
    Input,
    Debug,
    User,
}

impl EnvCategory {
    pub fn all() -> &'static [EnvCategory] {
        &[
            EnvCategory::Session,
            EnvCategory::Graphics,
            EnvCategory::Shell,
            EnvCategory::Xdg,
            EnvCategory::Fonts,
            EnvCategory::Input,
            EnvCategory::Debug,
            EnvCategory::User,
        ]
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Session => "Session",
            Self::Graphics => "Graphics",
            Self::Shell => "Shell",
            Self::Xdg => "XDG",
            Self::Fonts => "Fonts",
            Self::Input => "Input",
            Self::Debug => "Debug",
            Self::User => "User",
        }
    }

    pub fn icon_name(&self) -> &'static str {
        match self {
            Self::Session => "preferences-system-symbolic",
            Self::Graphics => "color-select-symbolic",
            Self::Shell => "utilities-terminal-symbolic",
            Self::Xdg => "folder-symbolic",
            Self::Fonts => "font-x-generic-symbolic",
            Self::Input => "input-keyboard-symbolic",
            Self::Debug => "dialog-warning-symbolic",
            Self::User => "avatar-default-symbolic",
        }
    }

    pub fn css_class(&self) -> &'static str {
        match self {
            Self::Session => "wwn-icon-blue",
            Self::Graphics => "wwn-icon-purple",
            Self::Shell => "wwn-icon-orange",
            Self::Xdg => "wwn-icon-indigo",
            Self::Fonts => "wwn-icon-teal",
            Self::Input => "wwn-icon-green",
            Self::Debug => "wwn-icon-red",
            Self::User => "wwn-icon-teal",
        }
    }
}

fn env_filter_chip(label: &str, icon: &str, color_class: &str) -> gtk::Button {
    let content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    content.set_halign(gtk::Align::Center);
    let image = gtk::Image::from_icon_name(icon);
    image.set_pixel_size(14);
    image.add_css_class(color_class);
    let text = gtk::Label::new(Some(label));
    content.append(&image);
    content.append(&text);
    let btn = gtk::Button::new();
    btn.set_child(Some(&content));
    btn.add_css_class("pill");
    btn.add_css_class("flat");
    btn.add_css_class("wwn-env-chip");
    btn.add_css_class(&format!("{color_class}-chip"));
    btn
}

#[derive(Debug, Clone)]
pub struct EnvCatalogEntry {
    pub name: &'static str,
    pub category: EnvCategory,
    pub mutability: &'static str,
    pub owned_by: Option<&'static str>,
    pub default_val: &'static str,
    pub summary: &'static str,
    pub details: &'static str,
    pub typical_default: &'static str,
    pub examples: &'static [&'static str],
}

pub static CATALOG_ENTRIES: &[EnvCatalogEntry] = &[
    // Session
    EnvCatalogEntry {
        name: "XDG_RUNTIME_DIR",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "/tmp",
        summary: "Runtime directory for Wayland sockets and IPC.",
        details: "Base directory path where user-specific runtime files, UNIX domain sockets, and IPC endpoints reside. Wayland compositors bind their listening sockets in this directory.",
        typical_default: "/tmp (or sandboxed temporary dir)",
        examples: &["/tmp", "/run/user/1000", "/tmp/wawona-runtime"],
    },
    EnvCatalogEntry {
        name: "WAYLAND_DISPLAY",
        category: EnvCategory::Session,
        mutability: "managed",
        owned_by: Some("waylandDisplay"),
        default_val: "wawona-0",
        summary: "Wayland compositor socket filename.",
        details: "Name of the Wayland socket file that client applications connect to inside XDG_RUNTIME_DIR.",
        typical_default: "wawona-0 (or wayland-0)",
        examples: &["wawona-0", "wayland-0", "wayland-1"],
    },
    EnvCatalogEntry {
        name: "WAYLAND_SOCKET",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "",
        summary: "Pre-opened file descriptor for inherited Wayland connections.",
        details: "File descriptor representing an existing open Wayland connection passed directly from a parent process. Cleared by default for multi-client launches.",
        typical_default: "(unset)",
        examples: &["3", "4", "5"],
    },
    EnvCatalogEntry {
        name: "WAWONA_NESTED_WAYLAND_DISPLAY",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "wayland-1",
        summary: "Socket name for nested compositor instances.",
        details: "Designates the Wayland socket name created and managed by an inner nested compositor instance (such as nested Weston or Niri) running inside Wawona.",
        typical_default: "wayland-1",
        examples: &["wayland-1", "wayland-nested", "wayland-2"],
    },
    EnvCatalogEntry {
        name: "WAWONA_NESTED_WAYLAND",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "1",
        summary: "Enables nested Wayland geometry negotiation.",
        details: "Boolean flag enabling nested Wayland mode. When set to 1, nested Weston computes its surface sizing from the parent xdg_toplevel geometry rather than physical wl_output mode.",
        typical_default: "1",
        examples: &["1", "0"],
    },
    EnvCatalogEntry {
        name: "WAWONA_OUTPUT_SCALE",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "1",
        summary: "Display scale factor for Wayland clients.",
        details: "Integer or fractional scale factor advertised to Wayland client surfaces through wl_output events. Set to 1 for standard DPI, or 2 for high-DPI.",
        typical_default: "1",
        examples: &["1", "2", "3", "1.5"],
    },
    EnvCatalogEntry {
        name: "NIRI_BACKEND",
        category: EnvCategory::Session,
        mutability: "managed",
        owned_by: Some("compositorBackend"),
        default_val: "nested",
        summary: "Hardware and display backend for Niri.",
        details: "Selects rendering and input backend for Niri scrollable-tiling compositor. Mapped from Display Backend. Use nested inside a window, or tty under userspace DRM.",
        typical_default: "nested",
        examples: &["nested", "tty", "drm"],
    },
    EnvCatalogEntry {
        name: "NIRI_CONFIG",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.config/niri/config.kdl",
        summary: "Filesystem path to Niri configuration file.",
        details: "Path to the configuration file (config.kdl) read by Niri on startup. Controls workspace keybindings, layouts, and gestures.",
        typical_default: "Generated path in config directory",
        examples: &["/path/to/custom-config.kdl", "$HOME/.config/niri/config.kdl"],
    },
    EnvCatalogEntry {
        name: "WESTON_CONFIG_FILE",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.config/weston.ini",
        summary: "Filesystem path to Weston configuration file.",
        details: "Path to configuration file (weston.ini) loaded by Weston. Configures desktop panels, taskbar launchers, and shell plugins.",
        typical_default: "Generated weston.ini in config directory",
        examples: &["/path/to/weston.ini", "$HOME/.config/weston.ini"],
    },
    EnvCatalogEntry {
        name: "WESTON_DATA_DIR",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "/usr/share/weston",
        summary: "Directory path for Weston static assets.",
        details: "Path where Weston looks for shared assets, including icons, sound themes, default wallpapers, and patterns.",
        typical_default: "Package share/weston directory",
        examples: &["/usr/share/weston", "/nix/store/.../share/weston"],
    },
    EnvCatalogEntry {
        name: "WESTON_MODULE_DIR",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "/usr/lib/weston",
        summary: "Directory path for Weston plugin modules.",
        details: "Path where Weston looks for installable shell and extension modules, such as desktop-shell.so and fullscreen-shell.so.",
        typical_default: "Package lib/weston directory",
        examples: &["/usr/lib/weston", "/nix/store/.../lib/weston"],
    },
    EnvCatalogEntry {
        name: "WESTON_BACKEND_DIR",
        category: EnvCategory::Session,
        mutability: "computed",
        owned_by: None,
        default_val: "/usr/lib/weston",
        summary: "Directory path for Weston backend dynamic libraries.",
        details: "Path where Weston loads output rendering backend plugins (wayland-backend.so, drm-backend.so, etc.).",
        typical_default: "Package lib/weston directory",
        examples: &["/usr/lib/weston", "/nix/store/.../lib/weston"],
    },

    // Graphics
    EnvCatalogEntry {
        name: "VK_DRIVER_FILES",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("vulkanDriver"),
        default_val: "/usr/share/vulkan/icd.d",
        summary: "Manifest paths for the Vulkan loader.",
        details: "Colon-separated list of JSON manifest file paths used by Vulkan loaders to discover and initialize Installable Client Drivers (ICD).",
        typical_default: "Path to system or bundled Vulkan ICD manifest",
        examples: &["/usr/share/vulkan/icd.d/intel_icd.json", "/usr/share/vulkan/icd.d/radeon_icd.json"],
    },
    EnvCatalogEntry {
        name: "VK_ICD_FILENAMES",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("vulkanDriver"),
        default_val: "/usr/share/vulkan/icd.d",
        summary: "Legacy Vulkan ICD manifest paths.",
        details: "Legacy environment variable used by older versions of the Khronos Vulkan loader to locate ICD manifest files.",
        typical_default: "Path to Vulkan ICD manifest",
        examples: &["/usr/share/vulkan/icd.d/intel_icd.json"],
    },
    EnvCatalogEntry {
        name: "WWN_VULKAN_LIBRARY",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("vulkanDriver"),
        default_val: "libvulkan.so.1",
        summary: "Primary Vulkan implementation library path.",
        details: "Absolute path to active Vulkan dynamic library loaded directly by in-process graphics clients in Wawona.",
        typical_default: "libvulkan.so.1",
        examples: &["/usr/lib/libvulkan.so.1", "/usr/lib/libvk_swiftshader.so"],
    },
    EnvCatalogEntry {
        name: "WWN_VULKAN_DRIVER",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("vulkanDriver"),
        default_val: "system",
        summary: "Active Vulkan driver identifier token.",
        details: "Specifies which Vulkan driver pipeline is selected. Owned and synchronized by the Wawona Vulkan Driver setting in preferences.",
        typical_default: "system",
        examples: &["system", "swiftshader", "none"],
    },
    EnvCatalogEntry {
        name: "WWN_OPENGL_DRIVER",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("openGLDriver"),
        default_val: "system",
        summary: "Active OpenGL/GLES driver identifier token.",
        details: "Specifies which OpenGL ES implementation is used for client surfaces and compositor rendering. Owned by OpenGL Driver setting.",
        typical_default: "system",
        examples: &["system", "angle", "mesa", "none"],
    },
    EnvCatalogEntry {
        name: "WWN_DISABLE_VULKAN",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("vulkanDriver"),
        default_val: "",
        summary: "Force disable Vulkan graphics pipeline.",
        details: "When set to 1, completely disables Vulkan loader initialization and driver queries, forcing fallbacks to OpenGL ES or software rasterization.",
        typical_default: "(unset)",
        examples: &["1", "0"],
    },
    EnvCatalogEntry {
        name: "WWN_DISABLE_EGL",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("openGLDriver"),
        default_val: "",
        summary: "Force disable EGL graphics pipeline.",
        details: "When set to 1, prevents EGL display initialization and context creation, forcing applications to rely on pure software rendering.",
        typical_default: "(unset)",
        examples: &["1", "0"],
    },
    EnvCatalogEntry {
        name: "ANGLE_DEFAULT_PLATFORM",
        category: EnvCategory::Graphics,
        mutability: "managed",
        owned_by: Some("openGLDriver"),
        default_val: "vulkan",
        summary: "Underlying rendering backend for ANGLE.",
        details: "Controls which native hardware API Google ANGLE uses to translate OpenGL ES commands into hardware draw calls.",
        typical_default: "vulkan (or metal on Apple)",
        examples: &["vulkan", "opengl", "metal", "swiftshader"],
    },

    // Shell
    EnvCatalogEntry {
        name: "HOME",
        category: EnvCategory::Shell,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME",
        summary: "User home directory path.",
        details: "Standard UNIX home directory. Shell configuration files, dotfiles, and personal documents are located relative to this path.",
        typical_default: "$HOME",
        examples: &["/home/alex", "/home/mobile", "/var/mobile"],
    },
    EnvCatalogEntry {
        name: "USER",
        category: EnvCategory::Shell,
        mutability: "defaulted",
        owned_by: None,
        default_val: "alex",
        summary: "Unix user name for local shell.",
        details: "Standard UNIX user name environment variable.",
        typical_default: "Current login user",
        examples: &["alex", "mobile", "user"],
    },
    EnvCatalogEntry {
        name: "LOGNAME",
        category: EnvCategory::Shell,
        mutability: "defaulted",
        owned_by: None,
        default_val: "alex",
        summary: "Login name for local shell.",
        details: "Standard UNIX login name variable.",
        typical_default: "Current login name",
        examples: &["alex", "mobile"],
    },
    EnvCatalogEntry {
        name: "SHELL",
        category: EnvCategory::Shell,
        mutability: "computed",
        owned_by: None,
        default_val: "/bin/sh",
        summary: "Shell binary path.",
        details: "Standard login shell executable invoked for new terminal and console sessions.",
        typical_default: "/bin/zsh or /bin/bash",
        examples: &["/bin/zsh", "/bin/bash", "/run/current-system/sw/bin/zsh"],
    },
    EnvCatalogEntry {
        name: "TERM",
        category: EnvCategory::Shell,
        mutability: "defaulted",
        owned_by: None,
        default_val: "xterm-256color",
        summary: "Terminal type for PTY and console emulators.",
        details: "Defines the terminal capabilities and color palette communicated to ncurses and terminal applications.",
        typical_default: "xterm-256color",
        examples: &["xterm-256color", "xterm", "vt100"],
    },
    EnvCatalogEntry {
        name: "PATH",
        category: EnvCategory::Shell,
        mutability: "computed",
        owned_by: None,
        default_val: "/usr/bin:/bin",
        summary: "Executable search path.",
        details: "Colon-separated list of directories searched by the shell when running commands without an explicit path.",
        typical_default: "$PATH",
        examples: &["/usr/local/bin:/usr/bin:/bin", "$HOME/.local/bin:$PATH"],
    },
    EnvCatalogEntry {
        name: "PROMPT",
        category: EnvCategory::Shell,
        mutability: "defaulted",
        owned_by: None,
        default_val: "%F{cyan}%~%f %# ",
        summary: "Shell command line prompt string.",
        details: "Prompt string displayed by interactive shells before reading each command line.",
        typical_default: "%F{cyan}%~%f %# ",
        examples: &["%F{cyan}%~%f %# ", "$ ", "wawona> "],
    },

    // XDG
    EnvCatalogEntry {
        name: "XDG_CONFIG_HOME",
        category: EnvCategory::Xdg,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.config",
        summary: "Base directory for user-specific configuration files.",
        details: "Standard XDG directory path where application preferences and config files reside.",
        typical_default: "$HOME/.config",
        examples: &["$HOME/.config", "/etc/xdg"],
    },
    EnvCatalogEntry {
        name: "XDG_CACHE_HOME",
        category: EnvCategory::Xdg,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.cache",
        summary: "Base directory for user-specific non-essential data.",
        details: "Standard XDG directory path where cached web pages, thumbnails, and temporary files reside.",
        typical_default: "$HOME/.cache",
        examples: &["$HOME/.cache", "/tmp"],
    },
    EnvCatalogEntry {
        name: "XDG_DATA_HOME",
        category: EnvCategory::Xdg,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.local/share",
        summary: "Base directory for user-specific data files.",
        details: "Standard XDG directory path where local application data, desktop entries, and icons are stored.",
        typical_default: "$HOME/.local/share",
        examples: &["$HOME/.local/share"],
    },
    EnvCatalogEntry {
        name: "XDG_DATA_DIRS",
        category: EnvCategory::Xdg,
        mutability: "computed",
        owned_by: None,
        default_val: "/usr/local/share:/usr/share",
        summary: "Preference-ordered set of base directories to search for data files.",
        details: "Colon-separated list of directories searched for system-wide application data, MIME types, and icons.",
        typical_default: "/usr/local/share:/usr/share",
        examples: &["/run/current-system/sw/share:/usr/share", "/usr/share"],
    },

    // Fonts / Input
    EnvCatalogEntry {
        name: "FONTCONFIG_FILE",
        category: EnvCategory::Fonts,
        mutability: "computed",
        owned_by: None,
        default_val: "$HOME/.config/fontconfig/fonts.conf",
        summary: "Path to Fontconfig XML configuration file.",
        details: "Main Fontconfig configuration file loaded by Cairo, Pango, and Xft to resolve and substitute font families.",
        typical_default: "/etc/fonts/fonts.conf",
        examples: &["/etc/fonts/fonts.conf", "$HOME/.config/fontconfig/fonts.conf"],
    },
    EnvCatalogEntry {
        name: "WAWONA_TERMINAL_FONT_SIZE",
        category: EnvCategory::Fonts,
        mutability: "defaulted",
        owned_by: None,
        default_val: "12",
        summary: "Font point size for built-in terminal sessions.",
        details: "Default font size in points used when rendering terminal grids in Wawona.",
        typical_default: "12",
        examples: &["10", "12", "14", "16"],
    },
    EnvCatalogEntry {
        name: "XKB_DEFAULT_LAYOUT",
        category: EnvCategory::Input,
        mutability: "defaulted",
        owned_by: None,
        default_val: "us",
        summary: "Default XKB keyboard layout name.",
        details: "Specifies the default XKB layout symbol (e.g. us, de, fr, gb) mapped into the Wayland seat keymap.",
        typical_default: "us",
        examples: &["us", "de", "fr", "gb"],
    },
    EnvCatalogEntry {
        name: "XCURSOR_THEME",
        category: EnvCategory::Fonts,
        mutability: "defaulted",
        owned_by: None,
        default_val: "Adwaita",
        summary: "Name of active XCursor / Wayland pointer theme.",
        details: "Theme name looked up in XCURSOR_PATH for cursor sprites.",
        typical_default: "Adwaita",
        examples: &["Adwaita", "breeze_cursors", "default"],
    },

    // Debug
    EnvCatalogEntry {
        name: "RUST_LOG",
        category: EnvCategory::Debug,
        mutability: "managed",
        owned_by: Some("logLevel"),
        default_val: "info",
        summary: "Logging filter expression for Wawona and Rust crates.",
        details: "Controls tracing filter directives (error, warn, info, debug, trace) across Wawona subsystems.",
        typical_default: "info",
        examples: &["info", "debug", "wawona=trace,smithay=debug", "warn"],
    },
    EnvCatalogEntry {
        name: "RUST_BACKTRACE",
        category: EnvCategory::Debug,
        mutability: "defaulted",
        owned_by: None,
        default_val: "1",
        summary: "Enables backtrace printing on panic.",
        details: "When set to 1, prints a detailed stack trace upon an unhandled panic. Set to full for verbose frame traces.",
        typical_default: "1",
        examples: &["1", "full", "0"],
    },
    EnvCatalogEntry {
        name: "WAWONA_AUTO_CMD",
        category: EnvCategory::Debug,
        mutability: "computed",
        owned_by: None,
        default_val: "",
        summary: "Command automatically executed when the shell opens.",
        details: "Optional startup command executed automatically when terminal sessions open (e.g. fastfetch or htop).",
        typical_default: "(unset)",
        examples: &["fastfetch", "phoon", "htop"],
    },
];

pub fn find_catalog_entry(name: &str) -> Option<&'static EnvCatalogEntry> {
    CATALOG_ENTRIES.iter().find(|e| e.name.eq_ignore_ascii_case(name))
}

/// Resolved entry representing the live state of a single variable.
#[derive(Debug, Clone)]
pub struct ResolvedEnvEntry {
    pub name: String,
    pub category: EnvCategory,
    pub mutability: String,
    pub owned_by: Option<String>,
    pub value: Option<String>,
    pub is_unset: bool,
    pub is_overridden: bool,
    pub typical_default: String,
    pub summary: String,
    pub details: String,
    pub examples: Vec<String>,
}

impl ResolvedEnvEntry {
    pub fn display_value(&self) -> String {
        if self.is_unset {
            "(Unset)".to_string()
        } else if self.is_overridden {
            match &self.value {
                Some(v) if v.is_empty() => "(Empty)".to_string(),
                Some(v) => v.clone(),
                None => "(Empty)".to_string(),
            }
        } else {
            match &self.value {
                Some(v) if !v.is_empty() => v.clone(),
                _ => self.typical_default.clone(),
            }
        }
    }
}

pub fn resolve_all_entries(
    overrides: &BTreeMap<String, String>,
    unsets: &[String],
    settings: &LinuxSettings,
) -> Vec<ResolvedEnvEntry> {
    let unsets_set: HashSet<&str> = unsets.iter().map(|s| s.as_str()).collect();
    let mut entries = Vec::new();

    for cat_entry in CATALOG_ENTRIES {
        let is_unset = unsets_set.contains(cat_entry.name);
        let user_override = overrides.get(cat_entry.name);
        let is_overridden = user_override.is_some() || is_unset;

        let live_default = match cat_entry.name {
            "WAYLAND_DISPLAY" => settings.wayland_display.clone(),
            "NIRI_BACKEND" => settings.compositor_backend.clone(),
            "RUST_LOG" => settings.log_level.clone(),
            "HOME" => std::env::var("HOME").unwrap_or_else(|_| "/home/alex".into()),
            "USER" => std::env::var("USER").unwrap_or_else(|_| "alex".into()),
            "LOGNAME" => std::env::var("LOGNAME").unwrap_or_else(|_| "alex".into()),
            "SHELL" => std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into()),
            "PATH" => std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into()),
            _ => cat_entry.default_val.to_string(),
        };

        let effective_value = if is_unset {
            None
        } else if let Some(val) = user_override {
            Some(val.clone())
        } else {
            Some(live_default.clone())
        };

        entries.push(ResolvedEnvEntry {
            name: cat_entry.name.to_string(),
            category: cat_entry.category,
            mutability: cat_entry.mutability.to_string(),
            owned_by: cat_entry.owned_by.map(|s| s.to_string()),
            value: effective_value,
            is_unset,
            is_overridden,
            typical_default: live_default,
            summary: cat_entry.summary.to_string(),
            details: cat_entry.details.to_string(),
            examples: cat_entry.examples.iter().map(|&s| s.to_string()).collect(),
        });
    }

    // Add extra user-defined variables that are not in catalog
    let catalog_names: HashSet<&str> = CATALOG_ENTRIES.iter().map(|e| e.name).collect();
    for (name, val) in overrides {
        if !catalog_names.contains(name.as_str()) {
            entries.push(ResolvedEnvEntry {
                name: name.clone(),
                category: EnvCategory::User,
                mutability: "user".to_string(),
                owned_by: None,
                value: Some(val.clone()),
                is_unset: false,
                is_overridden: true,
                typical_default: "(user defined)".to_string(),
                summary: "Custom user-defined environment variable.".to_string(),
                details: "Custom variable configured by user. Injected into all child machine environments.".to_string(),
                examples: vec!["1".into(), "true".into(), "/custom/path".into()],
            });
        }
    }

    for name in unsets {
        if !catalog_names.contains(name.as_str()) {
            entries.push(ResolvedEnvEntry {
                name: name.clone(),
                category: EnvCategory::User,
                mutability: "user".to_string(),
                owned_by: None,
                value: None,
                is_unset: true,
                is_overridden: true,
                typical_default: "(user defined)".to_string(),
                summary: "Custom user-defined environment variable (unset).".to_string(),
                details: "Variable is explicitly unset in child processes.".to_string(),
                examples: vec![],
            });
        }
    }

    entries
}

/// Builds the full Environment Variables page with:
/// - 1:1 SwiftUI / Compose parity
/// - Category filter chips
/// - Search entry
/// - Add new variable button
/// - Interactive list with status pills (Custom, Unset)
/// - Variable detail page with Value editing, Revert to Default, Unset, Docs, Defaults, Examples, Metadata
pub fn build_env_vars_view(
    overrides_cell: Rc<RefCell<BTreeMap<String, String>>>,
    unsets_cell: Rc<RefCell<Vec<String>>>,
    settings: &LinuxSettings,
) -> gtk::Widget {
    let main_stack = gtk::Stack::new();
    main_stack.set_transition_type(gtk::StackTransitionType::SlideLeftRight);
    main_stack.set_hexpand(true);
    main_stack.set_vexpand(true);

    let list_box_container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    list_box_container.set_hexpand(true);
    list_box_container.set_vexpand(true);

    // Selected category filter (None = All)
    let selected_category: Rc<RefCell<Option<EnvCategory>>> = Rc::new(RefCell::new(None));
    let search_query: Rc<RefCell<String>> = Rc::new(RefCell::new(String::new()));

    // MARK: 1. Category Filter Chips (horizontal scroll)
    let chips_scroll = gtk::ScrolledWindow::new();
    chips_scroll.set_policy(gtk::PolicyType::Automatic, gtk::PolicyType::Never);
    chips_scroll.set_margin_start(12);
    chips_scroll.set_margin_end(12);
    chips_scroll.set_margin_top(8);
    chips_scroll.set_margin_bottom(6);

    let chips_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    chips_scroll.set_child(Some(&chips_box));

    let chip_buttons: Rc<RefCell<Vec<(Option<EnvCategory>, gtk::Button)>>> =
        Rc::new(RefCell::new(Vec::new()));

    // "All" chip
    let all_btn = env_filter_chip("All", "view-grid-symbolic", "wwn-icon-slate");
    all_btn.add_css_class("wwn-env-chip-selected");
    chips_box.append(&all_btn);
    chip_buttons.borrow_mut().push((None, all_btn.clone()));

    for &cat in EnvCategory::all() {
        let btn = env_filter_chip(cat.display_name(), cat.icon_name(), cat.css_class());
        chips_box.append(&btn);
        chip_buttons.borrow_mut().push((Some(cat), btn));
    }

    list_box_container.append(&chips_scroll);

    // MARK: 2. Search & Add Bar
    let search_add_bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    search_add_bar.set_margin_start(16);
    search_add_bar.set_margin_end(16);
    search_add_bar.set_margin_bottom(8);

    let search_entry = gtk::SearchEntry::new();
    search_entry.set_hexpand(true);
    search_entry.set_placeholder_text(Some("Search variables"));
    search_add_bar.append(&search_entry);

    let add_btn = gtk::Button::from_icon_name("list-add-symbolic");
    add_btn.set_tooltip_text(Some("Add Custom Variable"));
    add_btn.add_css_class("flat");
    search_add_bar.append(&add_btn);

    list_box_container.append(&search_add_bar);

    // MARK: 3. Scrolled List of Variables
    let scroll = gtk::ScrolledWindow::new();
    scroll.set_hexpand(true);
    scroll.set_vexpand(true);
    scroll.set_policy(gtk::PolicyType::Automatic, gtk::PolicyType::Automatic);

    let list_content_box = gtk::Box::new(gtk::Orientation::Vertical, 12);
    list_content_box.set_margin_start(8);
    list_content_box.set_margin_end(8);
    list_content_box.set_margin_bottom(12);

    let list_box = gtk::ListBox::new();
    list_box.set_selection_mode(gtk::SelectionMode::None);
    list_box.add_css_class("boxed-list");
    list_content_box.append(&list_box);

    // MARK: 4. Footer Actions
    let footer_actions = gtk::FlowBox::new();
    footer_actions.set_selection_mode(gtk::SelectionMode::None);
    footer_actions.set_column_spacing(8);
    footer_actions.set_row_spacing(8);
    footer_actions.set_min_children_per_line(1);
    footer_actions.set_max_children_per_line(4);
    footer_actions.set_homogeneous(false);
    footer_actions.set_halign(gtk::Align::Start);
    footer_actions.set_margin_top(8);

    let reset_managed_btn = gtk::Button::with_label("Reset Wawona Defaults");
    reset_managed_btn.add_css_class("pill");
    footer_actions.append(&reset_managed_btn);

    let reset_all_btn = gtk::Button::with_label("Reset All Overrides");
    reset_all_btn.add_css_class("pill");
    reset_all_btn.add_css_class("destructive-action");
    footer_actions.append(&reset_all_btn);

    list_content_box.append(&footer_actions);

    let footer_caption = gtk::Label::new(Some(
        "Wawona manages core Wayland and graphics environment variables automatically.",
    ));
    footer_caption.add_css_class("dim-label");
    footer_caption.add_css_class("caption");
    footer_caption.set_xalign(0.0);
    footer_caption.set_wrap(true);
    list_content_box.append(&footer_caption);

    scroll.set_child(Some(&list_content_box));
    list_box_container.append(&scroll);

    main_stack.add_named(&list_box_container, Some("list"));

    // MARK: 5. Detail Page
    let detail_container = gtk::Box::new(gtk::Orientation::Vertical, 0);
    detail_container.set_hexpand(true);
    detail_container.set_vexpand(true);

    let detail_header = adw::HeaderBar::new();
    detail_header.set_show_end_title_buttons(false);
    detail_header.set_show_start_title_buttons(false);

    let back_btn = gtk::Button::from_icon_name("go-previous-symbolic");
    back_btn.set_tooltip_text(Some("Back to Variables"));
    detail_header.pack_start(&back_btn);

    let detail_title = gtk::Label::new(None);
    detail_title.add_css_class("title");
    detail_header.set_title_widget(Some(&detail_title));

    detail_container.append(&detail_header);

    let detail_scroll = gtk::ScrolledWindow::new();
    detail_scroll.set_hexpand(true);
    detail_scroll.set_vexpand(true);
    detail_container.append(&detail_scroll);

    main_stack.add_named(&detail_container, Some("detail"));

    // State bindings
    let settings_clone = settings.clone();
    let populate_list: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));

    // Detail builder helper
    let main_stack_c = main_stack.clone();
    let detail_scroll_c = detail_scroll.clone();
    let detail_title_c = detail_title.clone();
    let overrides_for_detail = overrides_cell.clone();
    let unsets_for_detail = unsets_cell.clone();
    let populate_list_for_detail = populate_list.clone();

    let open_detail = Rc::new(move |entry: ResolvedEnvEntry| {
        detail_title_c.set_text(&entry.name);

        let detail_pref_page = adw::PreferencesPage::new();
        detail_scroll_c.set_child(Some(&detail_pref_page));

        let var_name = entry.name.clone();
        let cat = entry.category;

        // Group 1: Value editing & status
        let val_group = adw::PreferencesGroup::new();
        val_group.set_title("Value");

        // Status pill row
        let status_box = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        status_box.set_margin_bottom(8);

        let cat_badge = gtk::Label::new(Some(cat.display_name()));
        cat_badge.add_css_class("pill");
        cat_badge.add_css_class("caption");
        cat_badge.add_css_class(cat.css_class());
        status_box.append(&cat_badge);

        let status_badge = gtk::Label::new(Some(if entry.is_unset {
            "Unset"
        } else if entry.is_overridden {
            "Custom Override"
        } else {
            "Default"
        }));
        status_badge.add_css_class("pill");
        status_badge.add_css_class("caption");
        if entry.is_unset {
            status_badge.add_css_class("destructive-action");
        } else if entry.is_overridden {
            status_badge.add_css_class("accent");
        }
        status_box.append(&status_badge);
        val_group.add(&status_box);

        // Value Entry Row
        let val_entry = adw::EntryRow::new();
        val_entry.set_title("Value");
        val_entry.set_text(&entry.value.unwrap_or_default());
        val_group.add(&val_entry);

        // Action Buttons Row
        let actions_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        actions_row.set_margin_top(8);

        let save_btn = gtk::Button::with_label("Save");
        save_btn.add_css_class("suggested-action");
        save_btn.add_css_class("pill");
        actions_row.append(&save_btn);

        let revert_btn = gtk::Button::with_label("Revert to Default");
        revert_btn.add_css_class("pill");
        if !entry.is_overridden && !entry.is_unset {
            revert_btn.set_sensitive(false);
        }
        actions_row.append(&revert_btn);

        let unset_btn = gtk::Button::with_label("Unset Variable");
        unset_btn.add_css_class("pill");
        unset_btn.add_css_class("destructive-action");
        actions_row.append(&unset_btn);

        val_group.add(&actions_row);

        // Saved notice
        let feedback_lbl = gtk::Label::new(None);
        feedback_lbl.add_css_class("caption");
        feedback_lbl.set_xalign(0.0);
        feedback_lbl.set_margin_top(4);
        val_group.add(&feedback_lbl);

        detail_pref_page.add(&val_group);

        // Connect Save
        {
            let val_entry = val_entry.clone();
            let var_name = var_name.clone();
            let overrides = overrides_for_detail.clone();
            let unsets = unsets_for_detail.clone();
            let feedback = feedback_lbl.clone();
            let pop_fn = populate_list_for_detail.clone();
            let revert_btn = revert_btn.clone();
            save_btn.connect_clicked(move |_| {
                let text = val_entry.text().to_string();
                unsets.borrow_mut().retain(|x| x != &var_name);
                overrides.borrow_mut().insert(var_name.clone(), text);
                feedback.set_text("✓ Value saved");
                revert_btn.set_sensitive(true);
                if let Some(f) = pop_fn.borrow().as_ref() {
                    f();
                }
            });
        }

        // Connect Revert
        {
            let var_name = var_name.clone();
            let typical_def = entry.typical_default.clone();
            let val_entry = val_entry.clone();
            let overrides = overrides_for_detail.clone();
            let unsets = unsets_for_detail.clone();
            let feedback = feedback_lbl.clone();
            let pop_fn = populate_list_for_detail.clone();
            let revert_btn_c = revert_btn.clone();
            revert_btn.connect_clicked(move |_| {
                overrides.borrow_mut().remove(&var_name);
                unsets.borrow_mut().retain(|x| x != &var_name);
                val_entry.set_text(&typical_def);
                feedback.set_text("✓ Reverted to default");
                revert_btn_c.set_sensitive(false);
                if let Some(f) = pop_fn.borrow().as_ref() {
                    f();
                }
            });
        }

        // Connect Unset
        {
            let var_name = var_name.clone();
            let val_entry = val_entry.clone();
            let overrides = overrides_for_detail.clone();
            let unsets = unsets_for_detail.clone();
            let feedback = feedback_lbl.clone();
            let pop_fn = populate_list_for_detail.clone();
            let revert_btn = revert_btn.clone();
            unset_btn.connect_clicked(move |_| {
                overrides.borrow_mut().remove(&var_name);
                if !unsets.borrow().contains(&var_name) {
                    unsets.borrow_mut().push(var_name.clone());
                }
                val_entry.set_text("");
                feedback.set_text("✓ Marked as unset");
                revert_btn.set_sensitive(true);
                if let Some(f) = pop_fn.borrow().as_ref() {
                    f();
                }
            });
        }

        // Group 2: Documentation
        if !entry.summary.is_empty() || !entry.details.is_empty() {
            let doc_group = adw::PreferencesGroup::new();
            doc_group.set_title("Documentation");

            if !entry.summary.is_empty() {
                let summary_lbl = gtk::Label::new(Some(&entry.summary));
                summary_lbl.add_css_class("heading");
                summary_lbl.set_xalign(0.0);
                summary_lbl.set_wrap(true);
                summary_lbl.set_margin_bottom(4);
                doc_group.add(&summary_lbl);
            }

            if !entry.details.is_empty() {
                let details_lbl = gtk::Label::new(Some(&entry.details));
                details_lbl.add_css_class("body");
                details_lbl.set_xalign(0.0);
                details_lbl.set_wrap(true);
                doc_group.add(&details_lbl);
            }

            detail_pref_page.add(&doc_group);
        }

        // Group 3: Typical Default
        if !entry.typical_default.is_empty() {
            let def_group = adw::PreferencesGroup::new();
            def_group.set_title("Typical Default");

            let def_row = adw::ActionRow::new();
            def_row.set_title(&entry.typical_default);
            def_row.set_subtitle("Catalog Default");

            let use_def_btn = gtk::Button::with_label("Use Default");
            use_def_btn.add_css_class("pill");
            let val_entry_c = val_entry.clone();
            let typical_def_c = entry.typical_default.clone();
            use_def_btn.connect_clicked(move |_| {
                val_entry_c.set_text(&typical_def_c);
            });
            def_row.add_suffix(&use_def_btn);
            def_group.add(&def_row);

            detail_pref_page.add(&def_group);
        }

        // Group 4: Examples
        if !entry.examples.is_empty() {
            let ex_group = adw::PreferencesGroup::new();
            ex_group.set_title("Examples");

            for ex in &entry.examples {
                let row = adw::ActionRow::new();
                row.set_title(ex);
                let use_btn = gtk::Button::with_label("Use");
                use_btn.add_css_class("pill");
                let val_entry_c = val_entry.clone();
                let ex_text = ex.clone();
                use_btn.connect_clicked(move |_| {
                    val_entry_c.set_text(&ex_text);
                });
                row.add_suffix(&use_btn);
                ex_group.add(&row);
            }

            detail_pref_page.add(&ex_group);
        }

        // Group 5: Details / Metadata
        let meta_group = adw::PreferencesGroup::new();
        meta_group.set_title("Details");

        let add_meta_row = |title: &str, val: &str| {
            let row = adw::ActionRow::new();
            row.set_title(title);
            let lbl = gtk::Label::new(Some(val));
            lbl.add_css_class("dim-label");
            row.add_suffix(&lbl);
            meta_group.add(&row);
        };

        add_meta_row("Variable Name", &entry.name);
        add_meta_row("Category", cat.display_name());
        add_meta_row("Mutability", &entry.mutability);
        if let Some(owned) = &entry.owned_by {
            add_meta_row("Managed By", owned);
        }
        add_meta_row("Scope", "Global Preference");

        detail_pref_page.add(&meta_group);

        main_stack_c.set_visible_child_name("detail");
    });

    // Connect Back button
    {
        let main_stack = main_stack.clone();
        back_btn.connect_clicked(move |_| {
            main_stack.set_visible_child_name("list");
        });
    }

    // Populate List closure
    {
        let list_box = list_box.clone();
        let selected_category = selected_category.clone();
        let search_query = search_query.clone();
        let overrides_cell = overrides_cell.clone();
        let unsets_cell = unsets_cell.clone();
        let settings = settings_clone;
        let open_detail = open_detail.clone();

        let populate = Rc::new(move || {
            // Remove existing rows
            while let Some(child) = list_box.first_child() {
                list_box.remove(&child);
            }

            let all_entries = resolve_all_entries(
                &overrides_cell.borrow(),
                &unsets_cell.borrow(),
                &settings,
            );

            let cat_filter = *selected_category.borrow();
            let query = search_query.borrow().trim().to_lowercase();

            let mut count = 0;
            for entry in all_entries {
                if let Some(filter_cat) = cat_filter {
                    if entry.category != filter_cat {
                        continue;
                    }
                }

                if !query.is_empty() {
                    let matches_name = entry.name.to_lowercase().contains(&query);
                    let matches_val = entry
                        .value
                        .as_deref()
                        .map(|v| v.to_lowercase().contains(&query))
                        .unwrap_or(false);
                    let matches_summary = entry.summary.to_lowercase().contains(&query);
                    if !matches_name && !matches_val && !matches_summary {
                        continue;
                    }
                }

                count += 1;
                let row = adw::ActionRow::new();
                row.set_activatable(true);

                // Prefix icon with colored container
                let icon_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                icon_box.set_size_request(32, 32);
                icon_box.add_css_class("card");
                let icon = gtk::Image::from_icon_name(entry.category.icon_name());
                icon.set_pixel_size(16);
                icon.add_css_class(entry.category.css_class());
                icon_box.append(&icon);
                row.add_prefix(&icon_box);

                // Title & Subtitle
                row.set_title(&entry.name);
                row.set_subtitle(&entry.display_value());

                // Suffix status pill & chevron
                let suffix_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                if entry.is_unset {
                    let unset_pill = gtk::Label::new(Some("Unset"));
                    unset_pill.add_css_class("pill");
                    unset_pill.add_css_class("caption");
                    unset_pill.add_css_class("destructive-action");
                    suffix_box.append(&unset_pill);
                } else if entry.is_overridden {
                    let custom_pill = gtk::Label::new(Some("Custom"));
                    custom_pill.add_css_class("pill");
                    custom_pill.add_css_class("caption");
                    custom_pill.add_css_class("accent");
                    suffix_box.append(&custom_pill);
                }

                let chevron = gtk::Image::from_icon_name("go-next-symbolic");
                chevron.add_css_class("dim-label");
                suffix_box.append(&chevron);
                row.add_suffix(&suffix_box);

                // Row click -> Open Detail
                let open_det = open_detail.clone();
                let entry_c = entry.clone();
                row.connect_activated(move |_| {
                    open_det(entry_c.clone());
                });

                list_box.append(&row);
            }

            if count == 0 {
                let empty_row = adw::ActionRow::new();
                empty_row.set_title("No Variables Found");
                empty_row.set_subtitle("No environment variables match your search or filter.");
                list_box.append(&empty_row);
            }
        });

        *populate_list.borrow_mut() = Some(populate.clone());
        populate();
    }

    // Connect Filter Chip Clicks
    {
        for (cat_opt, btn) in chip_buttons.borrow().iter() {
            let cat_val = *cat_opt;
            let sel_cat = selected_category.clone();
            let chip_btns = chip_buttons.clone();
            let pop_fn = populate_list.clone();
            btn.connect_clicked(move |_| {
                *sel_cat.borrow_mut() = cat_val;
                for (other_cat, other_btn) in chip_btns.borrow().iter() {
                    if *other_cat == cat_val {
                        other_btn.add_css_class("wwn-env-chip-selected");
                    } else {
                        other_btn.remove_css_class("wwn-env-chip-selected");
                    }
                }
                if let Some(f) = pop_fn.borrow().as_ref() {
                    f();
                }
            });
        }
    }

    // Connect Search Query
    {
        let query_cell = search_query.clone();
        let pop_fn = populate_list.clone();
        search_entry.connect_search_changed(move |entry| {
            *query_cell.borrow_mut() = entry.text().to_string();
            if let Some(f) = pop_fn.borrow().as_ref() {
                f();
            }
        });
    }

    // Connect Add Variable Button
    {
        let overrides_cell = overrides_cell.clone();
        let unsets_cell = unsets_cell.clone();
        let pop_fn = populate_list.clone();
        let open_detail = open_detail.clone();
        let root_anchor = add_btn.clone();

        add_btn.connect_clicked(move |_| {
            let popover = gtk::Popover::new();
            popover.set_parent(&root_anchor);

            let pop_box = gtk::Box::new(gtk::Orientation::Vertical, 8);
            pop_box.set_margin_start(12);
            pop_box.set_margin_end(12);
            pop_box.set_margin_top(12);
            pop_box.set_margin_bottom(12);

            let title_lbl = gtk::Label::new(Some("New Environment Variable"));
            title_lbl.add_css_class("heading");
            pop_box.append(&title_lbl);

            let name_entry = gtk::Entry::new();
            name_entry.set_placeholder_text(Some("VARIABLE_NAME"));
            pop_box.append(&name_entry);

            let val_entry = gtk::Entry::new();
            val_entry.set_placeholder_text(Some("Value"));
            pop_box.append(&val_entry);

            let btns_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            let cancel_btn = gtk::Button::with_label("Cancel");
            let add_confirm_btn = gtk::Button::with_label("Add");
            add_confirm_btn.add_css_class("suggested-action");
            btns_box.append(&cancel_btn);
            btns_box.append(&add_confirm_btn);
            pop_box.append(&btns_box);

            popover.set_child(Some(&pop_box));

            {
                let popover = popover.clone();
                cancel_btn.connect_clicked(move |_| {
                    popover.popdown();
                });
            }

            {
                let popover = popover.clone();
                let overrides = overrides_cell.clone();
                let unsets = unsets_cell.clone();
                let pop_fn = pop_fn.clone();
                let open_det = open_detail.clone();
                add_confirm_btn.connect_clicked(move |_| {
                    let name = name_entry.text().trim().to_uppercase();
                    let val = val_entry.text().trim().to_string();
                    if !name.is_empty() {
                        unsets.borrow_mut().retain(|x| x != &name);
                        overrides.borrow_mut().insert(name.clone(), val.clone());
                        popover.popdown();
                        if let Some(f) = pop_fn.borrow().as_ref() {
                            f();
                        }
                        open_det(ResolvedEnvEntry {
                            name: name.clone(),
                            category: EnvCategory::User,
                            mutability: "user".to_string(),
                            owned_by: None,
                            value: Some(val),
                            is_unset: false,
                            is_overridden: true,
                            typical_default: "(user defined)".to_string(),
                            summary: "Custom user-defined environment variable.".to_string(),
                            details: "Custom variable configured by user.".to_string(),
                            examples: vec![],
                        });
                    }
                });
            }

            popover.popup();
        });
    }

    // Connect Reset Managed Defaults
    {
        let overrides_cell = overrides_cell.clone();
        let unsets_cell = unsets_cell.clone();
        let pop_fn = populate_list.clone();
        reset_managed_btn.connect_clicked(move |_| {
            // Remove managed and computed overrides from overrides & unsets
            let managed_names: HashSet<&str> = CATALOG_ENTRIES
                .iter()
                .filter(|e| e.mutability == "managed" || e.mutability == "computed")
                .map(|e| e.name)
                .collect();

            overrides_cell.borrow_mut().retain(|k, _| !managed_names.contains(k.as_str()));
            unsets_cell.borrow_mut().retain(|k| !managed_names.contains(k.as_str()));

            if let Some(f) = pop_fn.borrow().as_ref() {
                f();
            }
        });
    }

    // Connect Reset All Overrides
    {
        let overrides_cell = overrides_cell.clone();
        let unsets_cell = unsets_cell.clone();
        let pop_fn = populate_list.clone();
        let parent_btn = reset_all_btn.clone();
        reset_all_btn.connect_clicked(move |_| {
            let dialog = adw::MessageDialog::new(
                parent_btn.root().and_downcast_ref::<gtk::Window>(),
                Some("Reset all environment overrides?"),
                Some("Clears all custom overrides and unsets. Catalog defaults will apply."),
            );
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("reset", "Reset All");
            dialog.set_response_appearance("reset", adw::ResponseAppearance::Destructive);
            dialog.set_default_response(Some("cancel"));
            dialog.set_close_response("cancel");

            let overrides_cell = overrides_cell.clone();
            let unsets_cell = unsets_cell.clone();
            let pop_fn = pop_fn.clone();
            dialog.connect_response(None, move |_, resp| {
                if resp == "reset" {
                    overrides_cell.borrow_mut().clear();
                    unsets_cell.borrow_mut().clear();
                    if let Some(f) = pop_fn.borrow().as_ref() {
                        f();
                    }
                }
            });
            dialog.present();
        });
    }

    main_stack.upcast()
}
