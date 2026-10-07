//! Terminal UI for the private physical-iPhone lab. No external Rust crates.
use super::*;
use std::{
    io::{BufRead, BufReader, IsTerminal, Read},
    process::Child,
    sync::mpsc::{self, Receiver},
};

const ITEMS: &[&str] = &[
    "Pair iPhone",
    "Start CarPlay",
    "Open viewer",
    "Help",
    "Quit",
];
#[derive(Debug, PartialEq)]
enum PairOutcome {
    Paired,
    Cancelled,
}
#[derive(PartialEq, Debug)]
enum Key {
    Up,
    Down,
    Enter,
    Quit,
    Stop,
    Open,
    Back,
    Char(char),
    Idle,
}
struct Terminal {
    saved: String,
    frame: std::cell::RefCell<String>,
}
impl Terminal {
    fn enter() -> Result<Self> {
        if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
            return Err("The menu needs an interactive terminal. Use doctor or setup for noninteractive work.".into());
        }
        let saved = Command::new("/bin/stty")
            .arg("-g")
            .stdin(Stdio::inherit())
            .output()?;
        if !saved.status.success() {
            return Err("Could not read terminal settings.".into());
        }
        let terminal = Self {
            saved: String::from_utf8(saved.stdout)?.trim().into(),
            frame: std::cell::RefCell::new(String::new()),
        };
        super::run(Command::new("/bin/stty").args(["raw", "-echo", "min", "0", "time", "1"]))?;
        print!("\x1b[?1049h\x1b[?25l");
        io::stdout().flush()?;
        Ok(terminal)
    }
    fn draw(&self, body: &str) -> Result<()> {
        if self.frame.borrow().as_str() == body {
            return Ok(());
        }
        *self.frame.borrow_mut() = body.to_owned();
        print!("\x1b[H\x1b[2J{}", body.replace('\n', "\r\n"));
        io::stdout().flush()?;
        Ok(())
    }
    fn form(&self, title: &str, label: &str, secret: bool) -> Result<Option<String>> {
        let mut value = String::new();
        loop {
            let shown = if secret {
                "*".repeat(value.chars().count())
            } else {
                clean(&value)
            };
            self.draw(&format!(
                "WAWONA CARPLAY\n\n{title}\n\n{label}\n> {shown}\n\nEnter: continue   Esc: cancel"
            ))?;
            match key()? {
                Key::Enter => return Ok(Some(value)),
                Key::Back | Key::Quit => return Ok(None),
                Key::Char('\u{7f}') | Key::Char('\u{8}') => {
                    value.pop();
                }
                Key::Char(c) if !c.is_control() => value.push(c),
                Key::Open => value.push('o'),
                Key::Stop => value.push('s'),
                _ => (),
            }
        }
    }
    fn notice(&self, title: &str, body: &str) -> Result<()> {
        self.draw(&format!(
            "WAWONA CARPLAY\n\n{}\n\n{}\n\nEnter or Esc: back",
            clean(title),
            body
        ))?;
        let mut released = false;
        loop {
            let input = key()?;
            if input == Key::Idle {
                released = true;
            }
            if input == Key::Quit || (released && matches!(input, Key::Enter | Key::Back)) {
                return Ok(());
            }
        }
    }
}
impl Drop for Terminal {
    fn drop(&mut self) {
        print!("\x1b[?25h\x1b[?1049l");
        let _ = io::stdout().flush();
        let _ = Command::new("/bin/stty").arg(&self.saved).status();
    }
}
fn key() -> Result<Key> {
    let mut byte = [0];
    if io::stdin().read(&mut byte)? == 0 {
        return Ok(Key::Idle);
    }
    Ok(match byte[0] {
        3 => Key::Quit,
        b'\r' | b'\n' => Key::Enter,
        27 => {
            let mut tail = [0; 2];
            let mut count = 0;
            while count < 2 {
                let n = io::stdin().read(&mut tail[count..])?;
                if n == 0 {
                    break;
                }
                count += n;
            }
            match tail {
                [b'[', b'A'] => Key::Up,
                [b'[', b'B'] => Key::Down,
                _ => Key::Back,
            }
        }
        b'o' => Key::Open,
        b's' => Key::Stop,
        b if b < 128 => Key::Char(b as char),
        b => {
            let length = if b < 224 {
                2
            } else if b < 240 {
                3
            } else {
                4
            };
            let mut bytes = vec![b];
            for _ in 1..length {
                if io::stdin().read(&mut byte)? == 0 {
                    return Ok(Key::Idle);
                }
                bytes.push(byte[0]);
            }
            match std::str::from_utf8(&bytes)
                .ok()
                .and_then(|s| s.chars().next())
            {
                Some(c) => Key::Char(c),
                None => Key::Idle,
            }
        }
    })
}
fn clean(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).take(80).collect()
}
fn address(s: &str) -> bool {
    let parts: Vec<_> = s.split(':').collect();
    parts.len() == 6
        && parts
            .iter()
            .all(|p| p.len() == 2 && p.bytes().all(|b| b.is_ascii_hexdigit()))
}
#[derive(Debug, PartialEq)]
struct Device {
    address: String,
    name: String,
}
fn device(line: &str) -> Option<Device> {
    let (mac, name) = line.split_once(' ')?;
    if !address(mac) {
        return None;
    }
    Some(Device {
        address: mac.to_uppercase(),
        name: clean(name),
    })
}
fn forward_lines(stream: impl Read + Send + 'static, tx: mpsc::Sender<String>) {
    std::thread::spawn(move || {
        for line in BufReader::new(stream)
            .lines()
            .map_while(std::result::Result::ok)
        {
            if tx.send(line).is_err() {
                break;
            }
        }
    });
}
fn lines(child: &mut Child) -> Receiver<String> {
    let (tx, rx) = mpsc::channel();
    forward_lines(child.stdout.take().expect("piped child stdout"), tx);
    rx
}
fn bridge_lines(child: &mut Child) -> Receiver<String> {
    let (tx, rx) = mpsc::channel();
    forward_lines(
        child.stdout.take().expect("piped bridge stdout"),
        tx.clone(),
    );
    forward_lines(child.stderr.take().expect("piped bridge stderr"), tx);
    rx
}
// Read the final diagnostics after process exit before classifying the result.
fn remember_message(message: &mut String, line: &str) {
    let line = clean(line);
    if line.trim().is_empty() {
        return;
    }
    let mut recent: Vec<_> = message.lines().map(str::to_owned).collect();
    recent.push(line);
    if recent.len() > 8 {
        recent.drain(..recent.len() - 8);
    }
    *message = recent.join("\n");
}
fn finish_messages(rx: &Receiver<String>, message: &mut String) {
    while let Ok(line) = rx.recv_timeout(Duration::from_millis(100)) {
        remember_message(message, &line);
    }
}
struct Process {
    child: Child,
}
impl Process {
    fn stop(&mut self) {
        if self.child.try_wait().ok().flatten().is_some() {
            return;
        }
        // Let the JVM run its shutdown hook and close the Bluetooth bridge.
        let _ = Command::new("/bin/kill")
            .args(["-TERM", &self.child.id().to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(3) {
            if self.child.try_wait().ok().flatten().is_some() {
                return;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
impl Drop for Process {
    fn drop(&mut self) {
        self.stop();
    }
}
enum ScanChoice {
    Phone(String),
    Again,
    Back,
}
fn discover(lab: &Lab, terminal: &Terminal) -> Result<Option<String>> {
    loop {
        match discover_once(lab, terminal)? {
            ScanChoice::Phone(mac) => return Ok(Some(mac)),
            ScanChoice::Again => (),
            ScanChoice::Back => return Ok(None),
        }
    }
}
fn discover_once(lab: &Lab, terminal: &Terminal) -> Result<ScanChoice> {
    let mut process = Process {
        child: Command::new(lab.src.join("macos/bt-bridge/bt-bridge"))
            .arg("--scan")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?,
    };
    let rx = bridge_lines(&mut process.child);
    let start = Instant::now();
    let mut devices: Vec<Device> = Vec::new();
    let mut selected = 0;
    let mut done = false;
    let mut diagnostic = String::new();
    loop {
        for line in rx.try_iter() {
            remember_message(&mut diagnostic, &line);
            if let Some(item) = device(&line) {
                if !devices.iter().any(|d| d.address == item.address) {
                    devices.push(item);
                }
            }
        }
        if !done {
            if let Some(status) = process.child.try_wait()? {
                if !status.success() {
                    finish_messages(&rx, &mut diagnostic);
                    terminal.notice("Scan failed", &format!("{}\n\nEnable Bluetooth for your terminal in macOS Privacy & Security.\nYou can still enter the iPhone address manually.", diagnostic))?;
                }
                done = true;
            } else if start.elapsed() >= Duration::from_secs(15) {
                process.stop();
                done = true;
            }
        }
        let mut body = format!(
            "WAWONA CARPLAY\n\nFind your iPhone\nKeep iPhone Settings > Bluetooth open.\n\n{}\n\n",
            if done {
                "Scan complete. Select your iPhone.".into()
            } else {
                format!(
                    "Scanning... {} seconds remaining",
                    15_u64.saturating_sub(start.elapsed().as_secs())
                )
            }
        );
        if devices.is_empty() {
            body.push_str(if done {
                "No devices found. Enter the address manually or scan again.\n"
            } else {
                "Looking for devices...\n"
            });
        }
        for (i, d) in devices.iter().enumerate() {
            body.push_str(&format!(
                "{} {}  {}\n",
                if i == selected { ">" } else { " " },
                d.name,
                d.address
            ));
        }
        for (offset, label) in ["Enter address manually", "Scan again", "Back"]
            .iter()
            .enumerate()
        {
            body.push_str(&format!(
                "{} {}\n",
                if selected == devices.len() + offset {
                    ">"
                } else {
                    " "
                },
                label
            ));
        }
        body.push_str("\nUp/Down: select   Enter: choose   Esc: back\nVerify iPhone address in General > About > Bluetooth.");
        terminal.draw(&body)?;
        match key()? {
            Key::Up => selected = selected.saturating_sub(1),
            Key::Down => selected = (selected + 1).min(devices.len() + 2),
            Key::Enter if selected < devices.len() => {
                return Ok(ScanChoice::Phone(devices[selected].address.clone()))
            }
            Key::Enter if selected == devices.len() => {
                return terminal
                    .form(
                        "Pair iPhone",
                        "Bluetooth address from iPhone General > About",
                        false,
                    )
                    .map(|mac| mac.map(ScanChoice::Phone).unwrap_or(ScanChoice::Back))
            }
            Key::Enter if selected == devices.len() + 1 => {
                drop(process);
                return Ok(ScanChoice::Again);
            }
            Key::Enter => return Ok(ScanChoice::Back),
            Key::Back | Key::Quit => return Ok(ScanChoice::Back),
            _ => (),
        }
    }
}
fn pair(lab: &Lab, terminal: &Terminal, mac: &str) -> Result<PairOutcome> {
    if !address(mac) {
        return Err("Use a Bluetooth address like AA:BB:CC:DD:EE:FF.".into());
    }
    let mut process = Process {
        child: Command::new(lab.src.join("macos/bt-bridge/bt-bridge"))
            .args(["--pair", mac])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?,
    };
    let rx = bridge_lines(&mut process.child);
    let start = Instant::now();
    let mut message = "Wait for the pairing code. Confirm it on your iPhone.".to_string();
    loop {
        for line in rx.try_iter() {
            remember_message(&mut message, &line);
        }
        if let Some(status) = process.child.try_wait()? {
            finish_messages(&rx, &mut message);
            if !status.success() {
                return Err(format!("{}\n\nKeep iPhone Settings > Bluetooth open and retry.\nCheck macOS Bluetooth permission for your terminal.", message).into());
            }
            let saved = lab.root.join("iphone-address");
            if saved.exists() {
                fs::remove_file(&saved)?;
            }
            private_file(&saved, mac.to_uppercase().as_bytes())?;
            terminal.notice(
                "iPhone paired",
                &format!(
                    "{}\n\nBluetooth pairing succeeded.\nChoose Start CarPlay next.",
                    clean(mac)
                ),
            )?;
            return Ok(PairOutcome::Paired);
        }
        if start.elapsed() >= Duration::from_secs(75) {
            return Err("Pairing timed out. Keep iPhone Bluetooth settings open and retry.".into());
        }
        terminal.draw(&format!(
            "WAWONA CARPLAY\n\nPairing {}\n\n{}\n\n{} seconds remaining\nEsc: cancel",
            clean(mac),
            message,
            75_u64.saturating_sub(start.elapsed().as_secs())
        ))?;
        if matches!(key()?, Key::Back | Key::Quit) {
            return Ok(PairOutcome::Cancelled);
        }
    }
}
fn ensure_setup(lab: &Lab, terminal: Terminal) -> Result<Terminal> {
    drop(terminal);
    let result = lab.setup();
    let terminal = Terminal::enter()?;
    if let Err(e) = result {
        terminal.notice("Setup failed", &clean(&e.to_string()))?;
    }
    Ok(terminal)
}
const GUIDE: &str = "1. Turn off macOS AirPlay Receiver.\n2. Enable Bluetooth for your terminal in Privacy & Security.\n3. Keep Mac and iPhone on the same Wi-Fi.\n4. Select Pair iPhone; confirm the code on iPhone.\n5. Start CarPlay, then choose Open viewer.\n6. Accept the CarPlay prompt on iPhone (PIN 3939 if asked).\n\nWawona needs its approved CarPlay entitlement and signing profile.\nPrivate credentials stay outside Git. Do not share viewer URLs.";
pub(super) fn run(lab: &Lab) -> Result<()> {
    let mut terminal = Terminal::enter()?;
    let mut selected = if lab.root.join("iphone-address").exists() {
        1
    } else {
        0
    };
    let mut status = "Pair your iPhone, then start CarPlay.".to_string();
    let mut server: Option<Process> = None;
    let mut output: Option<Receiver<String>> = None;
    let mut viewer: Option<String> = None;
    loop {
        if let Some(rx) = &output {
            for line in rx.try_iter() {
                if let Some(url) = line.trim().strip_prefix("Browser UI          : ") {
                    if url.starts_with("https://") || url.starts_with("http://") {
                        viewer = Some(url.to_owned());
                        status =
                            "Receiver ready. Press O to open the viewer; accept CarPlay on iPhone."
                                .into();
                    }
                }
            }
        }
        if let Some(p) = &mut server {
            if let Some(exit) = p.child.try_wait()? {
                status =
                    format!("Receiver exited ({exit}). Check permissions and connection guide.");
                server = None;
                output = None;
                viewer = None;
            }
        }
        let phone = fs::read_to_string(lab.root.join("iphone-address"))
            .ok()
            .filter(|s| address(s));
        let mut body = format!(
            "WAWONA CARPLAY\nPhysical iPhone testing\n\nSetup: {}    Receiver: {}\niPhone: {}\n\n",
            if lab.ready() { "Ready" } else { "Needs setup" },
            if server.is_some() {
                "Running"
            } else {
                "Stopped"
            },
            phone.as_deref().unwrap_or("Not selected")
        );
        for (i, item) in ITEMS.iter().enumerate() {
            body.push_str(&format!(
                "{} {}\n",
                if i == selected { ">" } else { " " },
                if i == 1 && server.is_some() {
                    "Stop CarPlay"
                } else {
                    item
                }
            ));
        }
        body.push_str(&format!(
            "\n{}\n\nUp/Down: select   Enter: choose   Q: quit",
            clean(&status)
        ));
        terminal.draw(&body)?;
        match key()? {
            Key::Up => selected = selected.saturating_sub(1),
            Key::Down => selected = (selected + 1).min(ITEMS.len() - 1),
            Key::Quit | Key::Char('q') => break,
            Key::Stop => {
                server = None;
                output = None;
                viewer = None;
                status = "Receiver stopped.".into();
            }
            Key::Open => {
                if let Some(url) = &viewer {
                    if !Command::new("/usr/bin/open")
                        .arg(url)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status()?
                        .success()
                    {
                        status = "Could not open the browser.".into();
                    }
                } else {
                    status =
                        "Start CarPlay first; the viewer opens when the receiver is ready.".into();
                }
            }
            Key::Enter => match selected {
                0 => {
                    if server.is_some() {
                        status = "Stop CarPlay before changing pairing.".into();
                        continue;
                    }
                    if !lab.ready() {
                        terminal = ensure_setup(lab, terminal)?;
                        if !lab.ready() {
                            continue;
                        }
                    }
                    let outcome = discover(lab, &terminal).and_then(|mac| match mac {
                        Some(mac) => pair(lab, &terminal, &mac),
                        None => Ok(PairOutcome::Cancelled),
                    });
                    match outcome {
                        Ok(PairOutcome::Paired) => {
                            selected = 1;
                            status = "iPhone paired. Start CarPlay when ready.".into();
                        }
                        Ok(PairOutcome::Cancelled) => status = "Pairing cancelled.".into(),
                        Err(e) => {
                            terminal.notice("Pairing did not complete", &e.to_string())?;
                            status =
                                "Pairing did not complete. Select Pair iPhone to retry.".into();
                        }
                    }
                }
                1 => {
                    if server.is_some() {
                        server = None;
                        output = None;
                        viewer = None;
                        status = "CarPlay stopped.".into();
                        continue;
                    }
                    if phone.is_none() {
                        selected = 0;
                        status = "Pair your iPhone first.".into();
                        continue;
                    }
                    if !lab.ready() {
                        terminal = ensure_setup(lab, terminal)?;
                        if !lab.ready() {
                            continue;
                        }
                    }
                    let Some(ssid) = terminal.form("Start CarPlay", "Wi-Fi name", false)? else {
                        continue;
                    };
                    if ssid.is_empty() {
                        status = "Wi-Fi name is required.".into();
                        continue;
                    }
                    let Some(password) = terminal.form(
                        "Start CarPlay",
                        "Wi-Fi password (hidden; blank if already known)",
                        true,
                    )?
                    else {
                        continue;
                    };
                    let extra = vec!["--bt-address".into(), phone.expect("selected phone")];
                    match lab
                        .server_command(ssid, password, &extra)
                        .and_then(|mut c| {
                            c.stdout(Stdio::piped()).stderr(Stdio::null());
                            Ok(c.spawn()?)
                        }) {
                        Ok(mut child) => {
                            output = Some(lines(&mut child));
                            server = Some(Process { child });
                            status = "Starting CarPlay...".into();
                        }
                        Err(e) => {
                            terminal.notice("Could not start CarPlay", &clean(&e.to_string()))?;
                        }
                    }
                }
                2 => {
                    if let Some(url) = &viewer {
                        if !Command::new("/usr/bin/open")
                            .arg(url)
                            .stdout(Stdio::null())
                            .stderr(Stdio::null())
                            .status()?
                            .success()
                        {
                            status = "Could not open browser.".into();
                        }
                    } else {
                        status = "Start CarPlay first. Wait for the receiver to be ready.".into();
                    }
                }
                3 => terminal.notice("Help", GUIDE)?,
                _ => break,
            },
            _ => (),
        }
    }
    drop(server);
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fast_pairing_failure_keeps_final_stderr() {
        let mut child = Command::new("/bin/sh")
            .args([
                "-c",
                "printf 'pairing started\n'; printf 'pairing failed: status 0x5\n' >&2; exit 1",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let rx = bridge_lines(&mut child);
        assert!(!child.wait().unwrap().success());
        let mut diagnostics = String::new();
        finish_messages(&rx, &mut diagnostics);
        assert!(diagnostics.contains("pairing failed: status 0x5"));
        assert!(diagnostics.contains("pairing started"));
    }
    #[test]
    #[ignore = "interactive terminal regression fixture"]
    fn pairing_failure_screen() {
        let root = env::temp_dir().join(format!("carplay-tui-fixture-{}", std::process::id()));
        private_dir(&root).unwrap();
        let lab = Lab {
            src: root.join("src"),
            root: root.clone(),
        };
        for path in [
            "src/server/build/install/server/lib",
            "src/web/dist",
            "src/macos/bt-bridge",
            "identity/offline-mfi",
        ] {
            fs::create_dir_all(root.join(path)).unwrap();
        }
        for path in [
            "src/web/dist/index.html",
            "identity/offline-mfi/identity.pk8",
            "identity/offline-mfi/certificate.p7b",
        ] {
            private_file(&root.join(path), b"regression fixture, not credentials").unwrap();
        }
        let helper = root.join("src/macos/bt-bridge/bt-bridge");
        private_file(&helper, b"#!/bin/sh\ncase \"$1\" in\n --scan) printf 'AA:BB:CC:DD:EE:FF Test iPhone [new]\\n';;\n --pair) printf 'pairing failed: status 0x5\\n' >&2; exit 1;;\nesac\n").unwrap();
        fs::set_permissions(helper, fs::Permissions::from_mode(0o700)).unwrap();
        run(&lab).unwrap();
        assert!(!root.join("iphone-address").exists());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn scan_parser_accepts_devices_and_rejects_diagnostics() {
        assert_eq!(
            device("64:31:35:b5:92:80 STARDUST [new]"),
            Some(Device {
                address: "64:31:35:B5:92:80".into(),
                name: "STARDUST [new]".into()
            })
        );
        assert!(device("bt-bridge: scanning for 10s").is_none());
        assert!(!address("64:31:35:B5:92:ZZ"));
    }
    #[test]
    fn device_names_cannot_inject_terminal_controls() {
        assert_eq!(clean("Phone\x1b\n\r\x07"), "Phone");
    }
    #[test]
    fn leaving_menu_reaps_receiver() {
        let child = Command::new("/bin/sleep").arg("10").spawn().unwrap();
        let mut process = Process { child };
        process.stop();
        assert!(process.child.try_wait().unwrap().is_some());
    }
}
