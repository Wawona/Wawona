//! Darwin process argv policy for the single Wawona.app Mach-O.
//!
//! Parses CLI into a JSON plan. Swift Lifecycle applies host ops
//! (recipes, DesktopReplacementController, AppKit). No ObjC.

use serde::Serialize;

/// Bundled client ids accepted by `--client` / `--list-clients`.
pub const BUNDLED_CLIENT_IDS: &[&str] = &[
    "weston",
    "niri",
    "weston-simple-egl",
    "weston-simple-shm",
    "weston-terminal",
    "foot",
    "opengl-cube",
    "vkcube",
    "kmscube",
    "neovim",
    "fastfetch",
    "phoon",
    "fuzzel",
    "gbm-es2-demo",
    "wawona-wasm",
    "hello-wasi-gui",
];

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum DarwinCliPlan {
    Help,
    Version,
    ListClients,
    ListMachines,
    MachinesShow { query: String },
    Run {
        recipe: String,
        headless: bool,
    },
    ModeB {
        action: String,
        machine: Option<String>,
    },
    /// Continue into a process role (UI / host / menubar).
    Launch {
        compositor_host: bool,
        menubar: bool,
        show_settings: bool,
        show_about: bool,
        settings_section: Option<String>,
        headless: bool,
        force_gui: bool,
        client: Option<String>,
        machine: Option<String>,
        backend: Option<String>,
    },
    Error { message: String, exit_code: i32 },
}

fn is_cocoa_passthrough(arg: &str) -> bool {
    arg.starts_with("-psn_") || arg == "-NSDocumentRevisionsDebugMode"
}

/// Parse argv (without argv[0]). Returns a serializable plan.
pub fn parse(args: &[String]) -> DarwinCliPlan {
    let mut force_gui = false;
    let mut headless = false;
    let mut compositor_host = false;
    let mut menubar = false;
    let mut show_settings = false;
    let mut show_about = false;
    let mut settings_section: Option<String> = None;
    let mut client: Option<String> = None;
    let mut machine: Option<String> = None;
    let mut backend: Option<String> = None;

    // First pass: early-exit verbs and Mode B.
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        if is_cocoa_passthrough(arg) {
            i += 1;
            continue;
        }
        match arg {
            "--help" | "-h" => return DarwinCliPlan::Help,
            "--version" | "-v" => return DarwinCliPlan::Version,
            "--list-clients" => return DarwinCliPlan::ListClients,
            "--list-machines" => return DarwinCliPlan::ListMachines,
            "run" => {
                if i + 1 >= args.len() || args[i + 1].starts_with('-') {
                    return DarwinCliPlan::Error {
                        message: "Missing recipe. Try: Wawona run --help".into(),
                        exit_code: 2,
                    };
                }
                let recipe = args[i + 1].clone();
                if recipe == "--help" || recipe == "-h" {
                    return DarwinCliPlan::Help;
                }
                let mut run_headless = false;
                for a in args {
                    if a == "--headless" || a == "--no-gui" {
                        run_headless = true;
                    }
                    if a == "--gui" {
                        run_headless = false;
                        force_gui = true;
                    }
                }
                return DarwinCliPlan::Run {
                    recipe,
                    headless: run_headless && !force_gui,
                };
            }
            "machines" => {
                let sub = args.get(i + 1).map(|s| s.as_str()).unwrap_or("list");
                match sub {
                    "list" => return DarwinCliPlan::ListMachines,
                    "--help" | "-h" => {
                        return DarwinCliPlan::Error {
                            message: "Usage: Wawona machines list|show <id|name>".into(),
                            exit_code: 0,
                        };
                    }
                    "show" => {
                        if i + 2 >= args.len() {
                            return DarwinCliPlan::Error {
                                message: "machines show requires an id or name".into(),
                                exit_code: 2,
                            };
                        }
                        return DarwinCliPlan::MachinesShow {
                            query: args[i + 2].clone(),
                        };
                    }
                    other => {
                        return DarwinCliPlan::Error {
                            message: format!("unknown machines subcommand '{other}'"),
                            exit_code: 2,
                        };
                    }
                }
            }
            _ => {}
        }

        if arg == "--mode-b-status"
            || arg == "--mode-b-ready"
            || arg == "--mode-b-prepare"
            || arg == "--mode-b-stage"
            || arg == "--mode-b-probe"
            || arg == "--mode-b-engage"
            || arg == "--mode-b-disengage"
            || arg == "--mode-b-machine"
            || arg.starts_with("--mode-b-machine=")
        {
            return parse_mode_b(args);
        }
        i += 1;
    }

    // Second pass: launch flags.
    i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        if is_cocoa_passthrough(arg) {
            i += 1;
            continue;
        }
        match arg {
            "--compositor-host" => compositor_host = true,
            "--menubar" => menubar = true,
            "--show-about" => show_about = true,
            "--show-settings" => show_settings = true,
            "--headless" | "--no-gui" => headless = true,
            "--gui" => force_gui = true,
            "--client" => {
                if i + 1 >= args.len() {
                    return DarwinCliPlan::Error {
                        message: "--client requires an id (see --list-clients)".into(),
                        exit_code: 2,
                    };
                }
                i += 1;
                client = Some(args[i].clone());
            }
            a if a.starts_with("--client=") => {
                client = Some(a["--client=".len()..].to_string());
            }
            "--machine" => {
                if i + 1 >= args.len() {
                    return DarwinCliPlan::Error {
                        message: "--machine requires an id (see --list-machines)".into(),
                        exit_code: 2,
                    };
                }
                i += 1;
                machine = Some(args[i].clone());
            }
            a if a.starts_with("--machine=") => {
                machine = Some(a["--machine=".len()..].to_string());
            }
            "--backend" => {
                if i + 1 >= args.len() {
                    return DarwinCliPlan::Error {
                        message: "--backend requires auto|wayland|drm".into(),
                        exit_code: 2,
                    };
                }
                i += 1;
                backend = Some(args[i].clone());
            }
            a if a.starts_with("--backend=") => {
                backend = Some(a["--backend=".len()..].to_string());
            }
            a if a.starts_with("--settings-section=") => {
                settings_section = Some(a["--settings-section=".len()..].to_string());
                show_settings = true;
            }
            "--settings-section" => {
                if i + 1 < args.len() {
                    i += 1;
                    settings_section = Some(args[i].clone());
                    show_settings = true;
                }
            }
            "--help" | "-h" | "--version" | "-v" | "--list-clients" | "--list-machines"
            | "run" | "machines" => {}
            a if a.starts_with("--mode-b-") => {}
            a if a.starts_with('-') => {
                return DarwinCliPlan::Error {
                    message: format!("unknown option '{a}' (try --help)"),
                    exit_code: 2,
                };
            }
            _ => {}
        }
        i += 1;
    }

    if let Some(ref b) = backend {
        let lower = b.to_ascii_lowercase();
        if lower != "auto" && lower != "wayland" && lower != "drm" {
            return DarwinCliPlan::Error {
                message: format!("--backend must be auto, wayland, or drm (got '{b}')"),
                exit_code: 2,
            };
        }
        backend = Some(lower);
    }

    if compositor_host && menubar {
        return DarwinCliPlan::Error {
            message: "--compositor-host and --menubar are mutually exclusive".into(),
            exit_code: 2,
        };
    }

    // --client / --machine imply headless unless --gui or `run` forced UI.
    if !force_gui && (client.is_some() || machine.is_some()) {
        headless = true;
    }
    if force_gui {
        headless = false;
    }

    DarwinCliPlan::Launch {
        compositor_host,
        menubar,
        show_settings,
        show_about,
        settings_section,
        headless,
        force_gui,
        client,
        machine,
        backend,
    }
}

fn parse_mode_b(args: &[String]) -> DarwinCliPlan {
    let mut action: Option<String> = None;
    let mut machine: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        match a {
            "--mode-b-status" => action = Some("status".into()),
            "--mode-b-ready" => action = Some("ready".into()),
            "--mode-b-prepare" => action = Some("prepare".into()),
            "--mode-b-stage" => action = Some("stage".into()),
            "--mode-b-probe" => action = Some("probe".into()),
            "--mode-b-engage" => action = Some("engage".into()),
            "--mode-b-disengage" => action = Some("disengage".into()),
            "--mode-b-machine" => {
                if i + 1 >= args.len() {
                    return DarwinCliPlan::Error {
                        message: "--mode-b-machine requires an id/name (or weston)".into(),
                        exit_code: 2,
                    };
                }
                i += 1;
                machine = Some(args[i].clone());
                if action.is_none() {
                    action = Some("select".into());
                }
            }
            a if a.starts_with("--mode-b-machine=") => {
                machine = Some(a["--mode-b-machine=".len()..].to_string());
                if action.is_none() {
                    action = Some("select".into());
                }
            }
            "--machine" => {
                if i + 1 >= args.len() {
                    return DarwinCliPlan::Error {
                        message: "--machine requires an id (see --list-machines)".into(),
                        exit_code: 2,
                    };
                }
                i += 1;
                if machine.is_none() {
                    machine = Some(args[i].clone());
                }
            }
            a if a.starts_with("--machine=") => {
                if machine.is_none() {
                    machine = Some(a["--machine=".len()..].to_string());
                }
            }
            _ => {}
        }
        i += 1;
    }

    let Some(action) = action else {
        return DarwinCliPlan::Error {
            message: "Mode B flag without action".into(),
            exit_code: 2,
        };
    };
    if action == "select" && machine.as_ref().map(|s| s.is_empty()).unwrap_or(true) {
        return DarwinCliPlan::Error {
            message: "--mode-b-machine requires an id/name (or weston)".into(),
            exit_code: 2,
        };
    }
    DarwinCliPlan::ModeB { action, machine }
}

/// Serialize a plan to JSON for the C trampoline / Swift decoder.
pub fn parse_to_json(args: &[String]) -> String {
    serde_json::to_string(&parse(args)).unwrap_or_else(|_| {
        r#"{"kind":"error","message":"serialize failed","exit_code":2}"#.into()
    })
}

/// Full CLI help text (macOS Darwin entry).
pub fn help_text() -> &'static str {
    "Wawona. Wayland compositor for macOS (and Apple / Android targets)\n\
\n\
Usage:\n\
  Wawona run <recipe>           Auto-create Machines card if needed, then start\n\
  Wawona machines list          Same profiles as the Machines GUI\n\
  Wawona machines show <id|name>\n\
  Wawona [options]\n\
\n\
Informational:\n\
  -h, --help              Show this help and exit\n\
  -v, --version           Print version and exit\n\
  --list-clients          List bundled client ids and exit\n\
  --list-machines         Alias for: Wawona machines list\n\
\n\
Mode B (Desktop Replacement):\n\
  --mode-b-status | --mode-b-ready | --mode-b-prepare | --mode-b-stage\n\
  --mode-b-probe | --mode-b-engage | --mode-b-disengage\n\
  --mode-b-machine <id>\n\
\n\
GUI vs headless:\n\
  --headless, --no-gui    Compositor only\n\
  --gui                   Force Machines UI\n\
  --client <id>           Launch bundled client (implies headless unless --gui)\n\
  --machine <id>          Connect saved profile (implies headless unless --gui)\n\
  --backend <mode>        auto | wayland | drm\n\
\n\
Service modes:\n\
  --compositor-host       Compositor service without Machines UI\n\
  --menubar               Menu-bar agent\n\
  --show-settings         Open in-app Global Settings\n\
  --settings-section=NAME Prefer a Settings section title\n"
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn help_and_run() {
        assert_eq!(parse(&args(&["--help"])), DarwinCliPlan::Help);
        assert_eq!(
            parse(&args(&["run", "weston"])),
            DarwinCliPlan::Run {
                recipe: "weston".into(),
                headless: false,
            }
        );
        assert_eq!(
            parse(&args(&["run", "flower", "--headless"])),
            DarwinCliPlan::Run {
                recipe: "flower".into(),
                headless: true,
            }
        );
    }

    #[test]
    fn mode_b_and_backend() {
        match parse(&args(&["--mode-b-probe", "--machine", "weston"])) {
            DarwinCliPlan::ModeB { action, machine } => {
                assert_eq!(action, "probe");
                assert_eq!(machine.as_deref(), Some("weston"));
            }
            other => panic!("{other:?}"),
        }
        match parse(&args(&["--client", "niri", "--backend", "DRM"])) {
            DarwinCliPlan::Launch {
                client,
                backend,
                headless,
                ..
            } => {
                assert_eq!(client.as_deref(), Some("niri"));
                assert_eq!(backend.as_deref(), Some("drm"));
                assert!(headless);
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn mutually_exclusive_service() {
        match parse(&args(&["--compositor-host", "--menubar"])) {
            DarwinCliPlan::Error { exit_code, .. } => assert_eq!(exit_code, 2),
            other => panic!("{other:?}"),
        }
    }
}
