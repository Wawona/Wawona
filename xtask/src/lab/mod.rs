//! `cargo xtask lab <name>`: runtime smokes and lab drives of a built product.

mod ad;
mod clients;
mod fuzzel;
mod leak;
mod matrix;
mod runtime;
mod smoke;

use anyhow::Result;
use std::path::PathBuf;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Install the APK on the running emulator, launch it, assert it stays alive.
    AndroidRuntime,
    /// Install and launch the simulator build, assert it stays alive.
    IosRuntime,
    /// Start the compositor host and hold each bundled client against it.
    MacosRuntime,
    /// Linux nightly: nested Weston with XWayland, then nested niri, on the host.
    Capability,
    /// agent-device GUI smokes (WAWONA_IOS_APP, WAWONA_ANDROID_APK install first).
    Smoke {
        #[arg(value_enum)]
        lane: smoke::Lane,
    },
    /// Nested niri + fuzzel (issue #78).
    Fuzzel {
        #[arg(value_enum, default_value = "all")]
        lane: fuzzel::Lane,
    },
    /// Nested niri on the macOS host compositor: child socket and a lit frame.
    NiriMacos {
        #[arg(long)]
        app: Option<PathBuf>,
    },
    /// Build the Freedesktop applications catalog and check it headless.
    AppsCatalog,
    /// Every bundled client on every target with a build (WAWONA_MATRIX_CLIENTS narrows).
    Matrix {
        /// ios, ipados, visionos, tvos, watchos, android, macos (default: all).
        platforms: Vec<String>,
    },
    /// Memory plateau over an idle hold (WAWONA_LEAK_HOLD_SEC).
    Leak {
        #[arg(value_enum, default_value = "all")]
        target: leak::Target,
    },
    /// Keep Allow Paste and the keyboard tutorial off a simulator. Run before `open`.
    IosSystemUi {
        /// Simulator name or UDID (default WAWONA_IOS_SIM, iPhone 17 Pro).
        device: Option<String>,
    },
    /// Make `client` the Default Machine: prefs only, no Edit sheet.
    SetClient {
        client: String,
        #[arg(value_enum)]
        platform: Platform,
        /// Simulator name or UDID (iOS); adb serial (Android).
        device: Option<String>,
    },
}

#[derive(Clone, Copy, clap::ValueEnum)]
pub enum Platform {
    Ios,
    Android,
}

pub fn main(c: Cmd) -> Result<()> {
    std::env::set_current_dir(crate::util::root())?;
    match c {
        Cmd::AndroidRuntime => runtime::android(),
        Cmd::IosRuntime => runtime::ios(),
        Cmd::MacosRuntime => runtime::macos(),
        Cmd::Capability => runtime::capability(),
        Cmd::Smoke { lane } => smoke::main(lane),
        Cmd::Fuzzel { lane } => fuzzel::main(lane),
        Cmd::NiriMacos { app } => fuzzel::niri_macos(app),
        Cmd::AppsCatalog => fuzzel::apps_catalog(),
        Cmd::Matrix { platforms } => matrix::main(platforms),
        Cmd::Leak { target } => leak::main(target),
        Cmd::IosSystemUi { device } => {
            ad::prepare_system_ui(&device.unwrap_or_else(ad::ios_device));
            Ok(())
        }
        Cmd::SetClient { client, platform: Platform::Ios, device } => {
            clients::set_ios(&client, &device.unwrap_or_else(ad::ios_device), ad::IOS_ID)
        }
        Cmd::SetClient { client, platform: Platform::Android, device } => {
            if let Some(d) = device {
                std::env::set_var("WAWONA_ANDROID_SERIAL", d);
            }
            let adb = ad::Adb::find().ok_or_else(|| anyhow::anyhow!("no adb device or emulator"))?;
            clients::set_android(&client, &adb)
        }
    }
}
