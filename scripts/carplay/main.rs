mod tui;
// Developer-only Playport lab. No credentials enter Git or Nix derivations.
use std::{
    env, fs,
    io::{self, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
const REV: &str = "9a0882dd0ffe48e467b59d58b12d81391df55ade";
const REPO: &str = "https://github.com/youcci/playport.git";
const APK: &str =
    "https://github.com/shihabal3amri/DiPlay/releases/download/v0.2.7/DiPlay-0.2.7.apk";
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn run(c: &mut Command) -> Result<()> {
    if !c.status()?.success() {
        return Err("A setup step failed. Fix it and rerun setup.".into());
    }
    Ok(())
}
// Inquiry completion can stall while macOS resolves Bluetooth device names.
// Keep the displayed discoveries, but never let that callback block the prompt.
fn run_bounded(c: &mut Command, limit: Duration) -> Result<bool> {
    let mut child = c.spawn()?;
    let started = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                return Err(
                    "Bluetooth helper failed. Check terminal Bluetooth permission and retry."
                        .into(),
                );
            }
            return Ok(false);
        }
        if started.elapsed() >= limit {
            child.kill()?;
            child.wait()?;
            return Ok(true);
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}
fn private_dir(p: &Path) -> Result<()> {
    if fs::symlink_metadata(p).is_ok_and(|m| m.file_type().is_symlink()) {
        return Err("Private path must not be a symlink.".into());
    }
    fs::create_dir_all(p)?;
    fs::set_permissions(p, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
fn private_file(p: &Path, bytes: &[u8]) -> Result<()> {
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(p)?;
    f.write_all(bytes)?;
    Ok(())
}
struct Lab {
    root: PathBuf,
    src: PathBuf,
}
impl Lab {
    fn new() -> Result<Self> {
        let home = PathBuf::from(env::var_os("HOME").ok_or("HOME is not set")?);
        let root = home.join(".playport/wawona-lab");
        private_dir(&home.join(".playport"))?;
        private_dir(&root)?;
        // Refuse a lab beneath any Git checkout, including a home-directory repo.
        if root.ancestors().any(|p| p.join(".git").exists()) {
            return Err(
                "The private lab is inside a Git checkout. Use a HOME outside repositories.".into(),
            );
        }
        Ok(Self {
            src: root.join("src"),
            root,
        })
    }
    fn identity(&self) -> PathBuf {
        self.root.join("identity")
    }
    fn ready(&self) -> bool {
        self.src.join("server/build/install/server/lib").is_dir()
            && self.src.join("web/dist/index.html").is_file()
            && self.src.join("macos/bt-bridge/bt-bridge").is_file()
            && ["identity.pk8", "certificate.p7b"]
                .iter()
                .all(|f| self.identity().join("offline-mfi").join(f).is_file())
    }
    fn setup(&self) -> Result<()> {
        if !self.src.exists() {
            println!("Cloning the pinned Playport source into the private developer lab.");
            run(Command::new("git").args(["clone", REPO]).arg(&self.src))?;
            run(Command::new("git")
                .current_dir(&self.src)
                .args(["checkout", "--detach", REV]))?;
        }
        let revision = Command::new("git")
            .current_dir(&self.src)
            .args(["rev-parse", "HEAD"])
            .output()?;
        if !revision.status.success() || String::from_utf8_lossy(&revision.stdout).trim() != REV {
            return Err("Lab source has a different revision. Preserve your changes and move src aside before setup.".into());
        }
        println!("Building the server, browser, and Bluetooth bridge.");
        run(Command::new("./gradlew")
            .current_dir(&self.src)
            .args(["build", ":server:installDist"]))?;
        let web = self.src.join("web");
        run(Command::new("npm").current_dir(&web).arg("ci"))?;
        run(Command::new("npm").current_dir(&web).arg("test"))?;
        run(Command::new("npm").current_dir(&web).args(["run", "build"]))?;
        // Use Apple's SDK/compiler, not the Nix compiler wrapper.
        run(Command::new("/bin/sh")
            .current_dir(&self.src)
            .arg("macos/bt-bridge/build.sh")
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin"))?;
        self.import_identity()?;
        println!("Setup complete. Keep iPhone Settings > Bluetooth open, then run carplay scan and carplay pair ADDRESS.");
        Ok(())
    }
    fn import_identity(&self) -> Result<()> {
        let identity = self.identity().join("offline-mfi");
        private_dir(&self.identity())?;
        private_dir(&identity)?;
        if ["identity.pk8", "certificate.p7b"]
            .iter()
            .all(|f| identity.join(f).is_file())
        {
            return Ok(());
        }
        println!("Importing the upstream-documented experimental identity privately. No key material is printed.");
        let temp = self.root.join(format!("import-{}", std::process::id()));
        private_dir(&temp)?;
        let result = (|| -> Result<()> {
            let apk = temp.join("identity-source.apk");
            private_file(&apk, &[])?;
            run(Command::new("curl")
                .args([
                    "--fail",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--proto",
                    "=https",
                    "--proto-redir",
                    "=https",
                    "--output",
                ])
                .arg(&apk)
                .arg(APK))?;
            for name in ["identity.pk8", "certificate.p7b"] {
                let output = Command::new("unzip")
                    .args(["-p"])
                    .arg(&apk)
                    .arg(format!("assets/offline-mfi/{name}"))
                    .stderr(Stdio::null())
                    .output()?;
                if !output.status.success() || output.stdout.is_empty() {
                    return Err("Identity archive is missing a required file.".into());
                }
                let dest = identity.join(name);
                if !dest.exists() {
                    private_file(&dest, &output.stdout)?;
                }
            }
            Ok(())
        })();
        fs::remove_dir_all(temp)?;
        result
    }
    fn bridge(&self, args: &[String]) -> Result<()> {
        let scan = args.first().is_some_and(|arg| arg == "--scan");
        let limit = Duration::from_secs(if scan { 15 } else { 75 });
        if run_bounded(
            Command::new(self.src.join("macos/bt-bridge/bt-bridge")).args(args),
            limit,
        )? {
            if scan {
                println!("Scan complete. Use an iPhone address shown above, or check Settings > General > About > Bluetooth.");
            } else {
                return Err(
                    "Bluetooth pairing timed out. Keep iPhone Bluetooth settings open and retry."
                        .into(),
                );
            }
        }
        Ok(())
    }
    fn launch(&self, extra: &[String]) -> Result<()> {
        if !self.ready() {
            self.setup()?;
        }
        for a in extra {
            if [
                "--wifi-passphrase",
                "--mfi-token",
                "--token",
                "--identity-dir",
                "--state-dir",
            ]
            .iter()
            .any(|flag| a == flag || a.starts_with(&format!("{flag}=")))
            {
                return Err("Credentials and private paths are managed by the lab. Do not pass them on the command line.".into());
            }
        }
        println!("Turn off macOS AirPlay Receiver. Enable Bluetooth for your terminal. Keep Mac and iPhone on the same Wi-Fi.");
        let paired = self.root.join("pairing-guided");
        if !paired.exists() {
            let choice = prompt("Scan and pair your iPhone now? [y/N]: ", false)?;
            if choice.eq_ignore_ascii_case("y") || choice.eq_ignore_ascii_case("yes") {
                println!("Keep iPhone Settings > Bluetooth open.");
                self.bridge(&["--scan".into()])?;
                let address = prompt("iPhone Bluetooth address from the scan: ", false)?;
                if address.is_empty() {
                    return Err("An iPhone Bluetooth address is required.".into());
                }
                self.bridge(&["--pair".into(), address])?;
                private_file(
                    &paired,
                    b"Pairing confirmed through the Bluetooth helper.\n",
                )?;
            }
        }
        let ssid = prompt("Wi-Fi name: ", false)?;
        if ssid.is_empty() {
            return Err("Wi-Fi name is required.".into());
        }
        let password = prompt(
            "Wi-Fi password (hidden; blank if already known to iPhone): ",
            true,
        )?;
        let result = self.server_command(ssid, password, extra)?.status()?;
        if !result.success() {
            return Err("Playport exited with an error.".into());
        }
        Ok(())
    }
    fn server_command(&self, ssid: String, password: String, extra: &[String]) -> Result<Command> {
        let state = self.root.join("state");
        private_dir(&state)?;
        let mut args = vec![
            "-Dorg.slf4j.simpleLogger.defaultLogLevel=info".into(),
            "-cp".into(),
            self.src
                .join("server/build/install/server/lib/*")
                .to_string_lossy()
                .into_owned(),
            "com.playport.server.MainKt".into(),
            "--wireless".into(),
            "--device-name".into(),
            "Wawona CarPlay Lab".into(),
            "--identity-dir".into(),
            self.identity().to_string_lossy().into_owned(),
            "--state-dir".into(),
            state.to_string_lossy().into_owned(),
            "--wifi-ssid".into(),
            ssid,
        ];
        if !password.is_empty() {
            args.extend(["--wifi-passphrase".into(), password]);
        }
        args.extend(extra.iter().cloned());
        // Java expands @argfiles before parsing its main class. Pass an open,
        // unlinked file as stdin: secrets have no pathname once Java starts.
        let argfile = self
            .root
            .join(format!("launch-{}.args", std::process::id()));
        private_file(
            &argfile,
            args.iter()
                .map(|s| java_quote(s))
                .collect::<Vec<_>>()
                .join("\n")
                .as_bytes(),
        )?;
        let launch_input = fs::File::open(&argfile)?;
        fs::remove_file(&argfile)?;
        let mut command = Command::new("java");
        command
            .current_dir(&self.src)
            .arg("@/dev/fd/0")
            .stdin(Stdio::from(launch_input));
        Ok(command)
    }
}
fn java_quote(s: &str) -> String {
    format!(
        "\"{}\"",
        s.replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t")
    )
}
fn prompt(label: &str, secret: bool) -> Result<String> {
    use std::io::IsTerminal;
    if !io::stdin().is_terminal() {
        return Err(
            "Launch from an interactive terminal; credentials must not be passed as arguments."
                .into(),
        );
    }
    print!("{label}");
    io::stdout().flush()?;
    let mut terminal = EchoGuard(false);
    if secret {
        run(Command::new("/bin/stty").arg("-echo"))?;
        terminal.0 = true;
    }
    let mut value = String::new();
    let read = io::stdin().read_line(&mut value);
    drop(terminal);
    if secret {
        println!();
    }
    read?;
    Ok(value.trim_end_matches(['\r', '\n']).to_owned())
}
struct EchoGuard(bool);
impl Drop for EchoGuard {
    fn drop(&mut self) {
        if self.0 {
            let _ = Command::new("/bin/stty").arg("echo").status();
        }
    }
}
fn main() {
    if let Err(e) = entry() {
        eprintln!("carplay: {e}");
        std::process::exit(1);
    }
}
fn entry() -> Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    let action = args.first().map(String::as_str).unwrap_or("tui");
    if matches!(action, "help" | "--help" | "-h") {
        println!("Wawona physical-iPhone CarPlay lab\n\nnix run .#carplay                  Open the interactive CarPlay menu\nnix run .#carplay -- setup         Build and privately import identity\nnix run .#carplay -- doctor        Check build and identity readiness\nnix run .#carplay -- scan          Find the iPhone Bluetooth address\nnix run .#carplay -- pair ADDRESS  Pair once; confirm on iPhone\nnix run .#carplay -- run [FLAGS]   Pass display/network flags to Playport\n\nPrivate files: ~/.playport/wawona-lab (never add to Git or RAG).");
        return Ok(());
    }
    if !cfg!(target_os = "macos") {
        return Err("Playport's Bluetooth bridge requires macOS.".into());
    }
    let lab = Lab::new()?;
    match action {
        "tui" if args.len() <= 1 => tui::run(&lab),
        "setup" if args.len() == 1 => lab.setup(),
        "doctor" if args.len() == 1 => {
            println!("Pinned Playport revision: {REV}");
            println!(
                "Build and identity: {}",
                if lab.ready() {
                    "ready"
                } else {
                    "not ready; run setup"
                }
            );
            if lab.ready() {
                Ok(())
            } else {
                Err("Setup is incomplete.".into())
            }
        }
        "scan" if args.len() == 1 => {
            if !lab.ready() {
                lab.setup()?;
            }
            lab.bridge(&["--scan".into()])
        }
        "pair" if args.len() == 2 => {
            if !lab.ready() {
                lab.setup()?;
            }
            lab.bridge(&["--pair".into(), args[1].clone()])
        }
        "run" => lab.launch(if args.is_empty() { &[] } else { &args[1..] }),
        _ => Err("Unknown command or wrong arguments. Run nix run .#carplay -- help.".into()),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stalled_helper_is_killed_and_reaped() {
        let started = Instant::now();
        assert!(run_bounded(
            Command::new("/bin/sleep").arg("10"),
            Duration::from_millis(20),
        )
        .unwrap());
        assert!(started.elapsed() < Duration::from_secs(2));
    }
    #[test]
    fn argfile_preserves_special_characters() {
        assert_eq!(java_quote("a b\"c\\d\ne"), "\"a b\\\"c\\\\d\\ne\"");
    }
    #[test]
    fn credentials_are_owner_only_and_not_overwritten() {
        let p = env::temp_dir().join(format!("carplay-test-{}", std::process::id()));
        private_file(&p, b"test").unwrap();
        assert_eq!(
            fs::metadata(&p).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(private_file(&p, b"replacement").is_err());
        fs::remove_file(p).unwrap();
    }
}
