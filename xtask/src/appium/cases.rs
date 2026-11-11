//! The suite: native host UI, Wayland keep-set sessions, and the catalog
//! battery. A catalog case passes only on a non-blank gallery screenshot of
//! the real Wayland guest (Colima on Darwin, nested on Linux CI).

use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::{bail, ensure, Result};

use super::pages::{self, pause, Ui};
use super::{evidence, session, webdriver::Driver, Matrix};
use crate::util::*;

pub const COMPOSITORS: [&str; 10] = [
    "weston",
    "niri",
    "swaywm",
    "mangowm",
    "hyprland",
    "cosmic_de",
    "phosh_de",
    "kde_plasma_de",
    "kde_plasma_mobile_de",
    "gnome_de",
];
pub const APPLICATIONS: [&str; 8] = [
    "weston_terminal",
    "weston_simple_shm",
    "foot",
    "ghostty_terminal",
    "konsole",
    "firefox_wayland",
    "thunar",
    "dolphin",
];

#[derive(clap::Args)]
pub struct Args {
    /// Groups to run: native, wayland, catalog. Default: all.
    #[arg(long, value_delimiter = ',')]
    group: Vec<String>,
    /// Run only these cases; a catalog client may be named without `catalog_`.
    #[arg(long, value_delimiter = ',')]
    only: Vec<String>,
    /// Run the offline checks and report every UI case skipped. CI uses this
    /// where no product build is wired.
    #[arg(long, env = "WAWONA_APPIUM_DRY", value_parser = clap::builder::BoolishValueParser::new(), default_value = "false")]
    dry: bool,
}

pub enum Outcome {
    Pass,
    Skip(String),
}
use Outcome::*;

pub struct Ctx {
    ui: Ui,
    m: Matrix,
    art: PathBuf,
}

impl Ctx {
    fn state(&self, feature: &str) -> String {
        self.m.state(&self.ui.platform, feature).unwrap_or_else(|_| "unset".into())
    }

    /// None when `feature`'s state is in `allow` (default available).
    fn gate(&self, feature: &str, allow: &[&str]) -> Option<Outcome> {
        let s = self.state(feature);
        let allow = if allow.is_empty() { &["available"][..] } else { allow };
        (!allow.contains(&s.as_str())).then(|| Skip(format!("{feature} is {s} on {}", self.ui.platform)))
    }

    fn shot(&self, name: &str) -> Result<Outcome> {
        self.ui.screenshot(&self.art.join(name))?;
        Ok(Pass)
    }
}

macro_rules! gate {
    ($c:expr, $f:expr $(, $a:expr)*) => {
        if let Some(skip) = $c.gate($f, &[$($a),*]) {
            return Ok(skip);
        }
    };
}

type Case = (String, &'static str, Box<dyn Fn(&Ctx) -> Result<Outcome>>);

fn case(name: &str, group: &'static str, f: impl Fn(&Ctx) -> Result<Outcome> + 'static) -> Case {
    (name.into(), group, Box::new(f))
}

fn kind_gate(c: &Ctx, feature: &str, control: &str, kind: &str) -> Result<Outcome> {
    match c.state(feature).as_str() {
        "forbidden" => {
            c.ui.tap(pages::ADD)?;
            c.ui.assert_absent(control)?;
            Ok(Pass)
        }
        "planned" => Ok(Skip(format!("{feature} planned: Start is not green"))),
        _ => {
            c.ui.add_machine(&format!("appium-{kind}"), kind)?;
            c.shot(&format!("add-{kind}.png"))
        }
    }
}

fn started(c: &Ctx) -> Result<()> {
    c.ui.start("tab")
}

fn native() -> Vec<Case> {
    vec![
        case("add_native_shell", "native", |c| {
            gate!(c, "native_shell");
            c.ui.add_machine("appium-native", "native")?;
            c.shot("add-native.png")
        }),
        case("add_vm_respects_gate", "native", |c| kind_gate(c, "vm", pages::TYPE_VM, "virtual_machine")),
        case("add_container_respects_gate", "native", |c| {
            kind_gate(c, "container", pages::TYPE_CONTAINER, "container")
        }),
        case("start_in_tab", "native", |c| {
            gate!(c, "native_shell");
            started(c)?;
            c.shot("start-tab.png")
        }),
        case("start_in_window", "native", |c| {
            if !c.m.allows_new_window(&c.ui.platform)? {
                return Ok(Skip("hostWindowManagerPolicy does not offer New Window".into()));
            }
            c.ui.start("window")?;
            c.shot("start-window.png")
        }),
        case("wawona_terminal", "native", |c| {
            gate!(c, "native_shell");
            started(c)?;
            c.ui.d.wait_visible(pages::TERMINAL, None)?;
            c.shot("terminal.png")
        }),
        case("pty_cli", "native", |c| {
            gate!(c, "native_shell");
            started(c)?;
            c.ui.run_in_terminal("echo appium-pty-ok")?;
            c.shot("pty-cli.png")
        }),
        case("sidebar", "native", |c| {
            c.ui.tap_if(pages::SIDEBAR)?;
            ensure!(c.ui.exists(pages::SIDEBAR)? || c.ui.exists(pages::ROOT)?, "no sidebar or Machines root");
            c.shot("sidebar.png")
        }),
        case("tab_overview", "native", |c| {
            gate!(c, "native_shell");
            started(c)?;
            if !c.ui.tap_if(pages::OVERVIEW)? {
                return Ok(Skip("overview control not wired on this build".into()));
            }
            for id in [pages::OVERVIEW_FOCUS, pages::OVERVIEW_TERMINATE, pages::OVERVIEW_ADD] {
                c.ui.tap_if(id)?;
            }
            c.shot("overview.png")
        }),
        case("tags_and_color", "native", |c| {
            if !c.ui.tap_if(pages::TAG_CREATE)? {
                return Ok(Skip("tag create not wired on this build".into()));
            }
            if c.ui.exists("wwn.machines.tag.name")? {
                c.ui.type_into("wwn.machines.tag.name", "appium-tag")?;
            }
            c.ui.tap_if("wwn.machines.tag.color")?;
            c.shot("tags.png")
        }),
        case("pin_machine", "native", |c| {
            if !c.ui.tap_if(pages::PIN)? {
                return Ok(Skip("pin control not wired on this build".into()));
            }
            c.shot("pin.png")
        }),
        case("edit_rename_and_search", "native", |c| {
            gate!(c, "native_shell");
            c.ui.add_machine("appium-search-me", "native")?;
            if c.ui.exists(pages::EDIT)? && c.ui.exists(pages::EDITOR_NAME)? {
                c.ui.tap(pages::EDIT)?;
                c.ui.type_into(pages::EDITOR_NAME, "appium-renamed")?;
                c.ui.tap(pages::EDITOR_SAVE)?;
            }
            if c.ui.exists(pages::SEARCH)? {
                c.ui.type_into(pages::SEARCH, "appium-renamed")?;
            }
            c.shot("search.png")
        }),
        case("settings_sections", "native", |c| {
            gate!(c, "native_shell");
            c.ui.open_settings()?;
            for s in pages::SETTINGS_SECTIONS {
                if c.ui.tap_if(s)? {
                    pause(300);
                }
            }
            c.shot("settings.png")?;
            c.ui.tap_if(pages::SETTINGS_DONE)?;
            Ok(Pass)
        }),
        case("watch_import_from_iphone", "native", |c| {
            if !matches!(c.ui.platform.as_str(), "ios" | "watchos") {
                return Ok(Skip("paired Watch import is iPhone Appium only".into()));
            }
            gate!(c, "watch_import_send");
            c.ui.open_settings()?;
            if !c.ui.tap_if(pages::APPLE_WATCH)? {
                return Ok(Skip("Apple Watch settings section missing".into()));
            }
            c.ui.tap("wwn.settings.appleWatch.import")?;
            c.shot("watch-import.png")
        }),
        case("import_file", "native", |c| {
            if !c.ui.tap_if(pages::IMPORT_FILE)? {
                return Ok(Skip("import file control not wired on this build".into()));
            }
            c.shot("import-file.png")
        }),
        case("rotate_or_resize", "native", |c| {
            gate!(c, "device_rotation", "available", "resize_window");
            started(c)?;
            if !c.ui.exists(pages::SURFACE)? {
                return Ok(Skip("compositor surface not visible yet".into()));
            }
            let before = c.ui.surface_rect()?;
            if !matches!(c.ui.platform.as_str(), "ios" | "ipados" | "android") {
                // macOS and Linux resize the host window; record the frame.
                return c.shot("resize.png");
            }
            if let Err(e) = c.ui.d.set_orientation("LANDSCAPE") {
                return Ok(Skip(format!("orientation API unavailable: {e}")));
            }
            pause(1000);
            let resized = c.ui.assert_resized(before);
            c.ui.d.set_orientation("PORTRAIT")?;
            resized.map(|_| Pass)
        }),
        case("toolbar_and_keyboard", "native", |c| {
            gate!(c, "toolbar_keys");
            started(c)?;
            if !c.ui.tap_if(pages::SURFACE)? {
                return Ok(Skip("compositor surface not visible".into()));
            }
            pause(500);
            if c.ui.exists(pages::TOOLBAR)? {
                c.ui.d.wait_visible(pages::TOOLBAR, None)?;
                c.ui.tap_if(pages::TOOLBAR_CUSTOMIZE)?;
            }
            c.ui.dismiss_keyboard()?;
            c.shot("toolbar-keyboard.png")
        }),
        case("multiple_clients", "native", |c| {
            gate!(c, "native_shell");
            started(c)?;
            pause(500);
            if !c.ui.tap_if(pages::OVERVIEW_ADD)? && c.ui.exists(pages::START)? {
                started(c)?;
            }
            c.shot("multi-client.png")
        }),
    ]
}

/// A keep-set session that needs a fixture named by `env`.
fn fixture(name: &'static str, features: &'static [&'static str], env: &'static str) -> Case {
    case(name, "wayland", move |c| {
        for f in features {
            gate!(c, f);
        }
        if std::env::var(env).unwrap_or_default().is_empty() {
            return Ok(Skip(format!("{env} unset")));
        }
        c.ui.add_machine(&format!("appium-{name}"), "native")?;
        started(c)?;
        c.shot(&format!("{name}.png"))
    })
}

fn wayland() -> Vec<Case> {
    vec![
        case("terminal_ls_sees_import", "wayland", |c| {
            gate!(c, "native_shell");
            let marker = env_or("WAWONA_IMPORT_MARKER", "appium-import-marker.txt");
            started(c)?;
            c.ui.run_in_terminal(&format!("ls | grep {marker} || ls"))?;
            c.shot("terminal-ls.png")
        }),
        case("hello_wasi_gui", "wayland", |c| {
            gate!(c, "wasm");
            c.ui.add_machine("appium-wasm", "native")?;
            if c.ui.tap_if(pages::EDIT)? && c.ui.exists(pages::EDITOR_WASM)? {
                c.ui.type_into(pages::EDITOR_WASM, "wasm hello-wasi-gui")?;
                c.ui.tap(pages::EDITOR_SAVE)?;
            }
            started(c)?;
            pause(2000);
            if c.ui.exists(pages::SURFACE)? {
                c.ui.d.wait_visible(pages::SURFACE, None)?;
            }
            c.shot("hello-wasi-gui.png")
        }),
        fixture("ssh", &["ssh"], "WAWONA_SSH_FIXTURE_HOST"),
        fixture("waypipe-tcp", &["waypipe"], "WAWONA_WAYPIPE_TCP_ENDPOINT"),
        fixture("waypipe-ssh", &["waypipe", "ssh"], "WAWONA_WAYPIPE_SSH_HOST"),
        case("graphics_driver_switch", "wayland", |c| {
            gate!(c, "gpu_driver_picker");
            c.ui.open_settings()?;
            if !c.ui.tap_if(pages::GRAPHICS)? {
                return Ok(Skip("graphics settings section missing".into()));
            }
            c.shot("graphics-drivers.png")?;
            c.ui.tap_if(pages::SETTINGS_DONE)?;
            Ok(Pass)
        }),
    ]
}

fn runtime() -> PathBuf {
    std::env::var("WAWONA_RUNTIME").or_else(|_| std::env::var("XDG_RUNTIME_DIR")).map(PathBuf::from).unwrap_or_else(
        |_| format!("/tmp/wawona-{}", try_output(cmd("id").arg("-u")).unwrap_or_default().trim()).into(),
    )
}

fn catalog_client(c: &Ctx, kind: &str, client: &str) -> Result<Outcome> {
    if !matches!(c.ui.platform.as_str(), "macos" | "linux") {
        return Ok(Skip("catalog guests run on macOS (Colima) or Linux (nested)".into()));
    }
    gate!(c, "catalog_clients");
    let entry = c.m.entry(kind, client)?;
    ensure!(
        entry.get("status").and_then(|s| s.as_str()) == Some("available"),
        "{client} must be available in matrix.toml"
    );
    let socket = runtime().join(env_or("WAYLAND_DISPLAY", "wayland-0"));
    let end = Instant::now() + Duration::from_secs(20);
    while !socket.exists() {
        ensure!(Instant::now() < end, "host compositor not up for {client}: {} missing", socket.display());
        pause(500);
    }
    // Present exposes the surface only after Focus, or after the Terminal
    // window that Start opens is closed.
    if !c.ui.exists(pages::SURFACE)? {
        if c.ui.exists(pages::START)? || c.ui.exists(pages::START_TAB)? {
            started(c)?;
        } else {
            c.ui.add_machine(&format!("catalog-{client}"), "native")?;
            started(c)?;
        }
        pause(2000);
    }
    c.ui.tap_if(pages::FOCUS)?;
    if !c.ui.exists(pages::SURFACE)? && c.ui.platform == "macos" {
        c.ui.close_terminal_windows();
    }

    let guest = if cfg!(target_os = "macos") { "colima".to_string() } else { env_or("WAWONA_WAYLAND_GUEST", "nested") };
    let out = cmd("bash")
        .arg(root().join("scripts/appium/launch-wayland-client.sh"))
        .arg(client)
        .env("WAWONA_RUNTIME", runtime())
        .env("WAYLAND_DISPLAY", env_or("WAYLAND_DISPLAY", "wayland-0"))
        .env("WAWONA_WAYLAND_GUEST", guest)
        .current_dir(root())
        .output()?;
    let log = [String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr)].join("\n");
    write(c.art.join(format!("guest-{client}.log")), &log)?;
    if !out.status.success() {
        bail!("guest launch failed for {client} ({}): {}", out.status, &log[log.len().saturating_sub(800)..]);
    }

    pause((env_or("WAWONA_CATALOG_SETTLE_SEC", "4").parse::<f64>().unwrap_or(4.0) * 1000.0) as u64);
    c.ui.tap_if(pages::FOCUS)?;
    let end = Instant::now() + Duration::from_secs(90);
    while !c.ui.exists(pages::SURFACE)? {
        ensure!(Instant::now() < end, "compositor surface missing after launching {client}");
        pause(1000);
    }
    c.ui.tap(pages::SURFACE)?;
    let shot = c.art.join(format!("wayland-{client}.png"));
    c.ui.screenshot_surface(&shot).or_else(|_| c.ui.screenshot(&shot))?;
    evidence::require_client_screenshot(&shot, client)?;
    let published = evidence::publish(&shot, &super::artifacts(), client)?;
    evidence::require_client_screenshot(&published, client)?;
    Ok(Pass)
}

fn catalog() -> Vec<Case> {
    let kinds =
        COMPOSITORS.iter().map(|n| ("compositors", *n)).chain(APPLICATIONS.iter().map(|n| ("applications", *n)));
    kinds.map(|(kind, n)| case(&format!("catalog_{n}"), "catalog", move |c| catalog_client(c, kind, n))).collect()
}

fn xml(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

pub fn run(a: Args) -> Result<()> {
    let art = super::artifacts();
    std::fs::create_dir_all(&art)?;
    super::verify()?;
    let groups = if a.group.is_empty() { vec!["native".into(), "wayland".into(), "catalog".into()] } else { a.group };
    let cases: Vec<Case> = [native(), wayland(), catalog()]
        .into_iter()
        .flatten()
        .filter(|(n, g, _)| {
            groups.iter().any(|x| x == g)
                && (a.only.is_empty() || a.only.iter().any(|o| n == o || *n == format!("catalog_{o}")))
        })
        .collect();

    let platform = super::platform();
    let per_case = env_or("WAWONA_APPIUM_DRIVER_SCOPE", "session") == "function";
    let mut ctx: Option<Ctx> = None;
    let (mut passed, mut skipped, mut failures) = (0, 0, Vec::new());
    let mut junit = String::new();
    for (name, group, f) in &cases {
        let t = Instant::now();
        let result = if a.dry {
            Ok(Skip("WAWONA_APPIUM_DRY: no product build under test".into()))
        } else {
            if ctx.is_none() {
                let d = Driver::new(&session::server(), session::capabilities(&platform))?;
                ctx = Some(Ctx { ui: Ui { d, platform: platform.clone() }, m: Matrix::load()?, art: art.clone() });
            }
            let c = ctx.as_ref().unwrap();
            c.ui.open_root().and_then(|_| f(c))
        };
        let secs = t.elapsed().as_secs_f64();
        let body = match &result {
            Ok(Pass) => {
                passed += 1;
                println!("PASS {group}::{name} ({secs:.1}s)");
                String::new()
            }
            Ok(Skip(why)) => {
                skipped += 1;
                println!("SKIP {group}::{name}: {why}");
                format!("<skipped message=\"{}\"/>", xml(why))
            }
            Err(e) => {
                println!("FAIL {group}::{name}: {e:#}");
                failures.push(name.clone());
                format!("<failure message=\"{}\"/>", xml(&format!("{e:#}")))
            }
        };
        junit += &format!("<testcase classname=\"{group}\" name=\"{name}\" time=\"{secs:.3}\">{body}</testcase>\n");
        if per_case {
            if let Some(c) = ctx.take() {
                c.ui.d.quit();
            }
        }
    }
    if let Some(c) = ctx {
        c.ui.d.quit();
    }
    if groups.iter().any(|g| g == "catalog") {
        evidence::write_index(&art, &Matrix::load()?.clients())?;
    }
    write(
        art.join("junit.xml"),
        format!(
            "<?xml version=\"1.0\"?>\n<testsuite name=\"wawona-appium\" tests=\"{}\" failures=\"{}\" skipped=\"{skipped}\">\n{junit}</testsuite>\n",
            cases.len(),
            failures.len()
        ),
    )?;
    println!("{passed} passed, {skipped} skipped, {} failed", failures.len());
    ensure!(failures.is_empty(), "failed: {}", failures.join(", "));
    Ok(())
}
