//! Linux GTK talks the same Relay policy as `wawona_relay.h`.
//! Backend choice is not a Settings switch. Never QEMU.
//!
//! A virtual machine or container Start attaches the guest serial console to
//! Wawona Terminal. The process on that PTY is cloud-hypervisor (or the
//! `wawona-linux-vm-run` wrapper, which execs it). It is not the host login
//! shell. Containers use the same KVM guest. The image and entry travel on
//! the kernel command line (`wawona.image`, `wawona.entry`).

use anyhow::{bail, Result};

use crate::domain::machine_profile::{MachineProfile, MachineType};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelayKind {
    Vm,
    Container,
    Wasm,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelayBackend {
    KvmCloudHypervisor,
    WasmCranelift,
}

impl RelayBackend {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::KvmCloudHypervisor => "kvm-ch",
            Self::WasmCranelift => "wasm-cranelift",
        }
    }
}

/// Resolve a Machines kind on the Linux AppImage host.
pub fn resolve_backend(kind: RelayKind) -> Result<RelayBackend> {
    match kind {
        RelayKind::Wasm => Ok(RelayBackend::WasmCranelift),
        RelayKind::Vm | RelayKind::Container => {
            if !std::path::Path::new("/dev/kvm").exists() {
                bail!("/dev/kvm missing. Fail closed. No QEMU TCG");
            }
            Ok(RelayBackend::KvmCloudHypervisor)
        }
    }
}

/// What Wawona Terminal should exec for this guest. `role` is the terminal
/// subtitle. On failure `argv` prints the reason and exits. It never starts
/// the host login shell.
pub struct GuestTerminal {
    pub argv: Vec<String>,
    pub role: &'static str,
}

pub fn guest_terminal(profile: &MachineProfile) -> GuestTerminal {
    let role = match profile.machine_type {
        MachineType::Container => "Container console",
        _ => "Virtual machine console",
    };
    match guest_console_argv(profile) {
        Ok(argv) => GuestTerminal { argv, role },
        Err(err) => GuestTerminal {
            argv: message_argv(&err.to_string()),
            role,
        },
    }
}

fn guest_console_argv(profile: &MachineProfile) -> Result<Vec<String>> {
    resolve_backend(match profile.machine_type {
        MachineType::Container => RelayKind::Container,
        _ => RelayKind::Vm,
    })?;

    let memory_mb = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.memory_mb)
        .unwrap_or(2048)
        .clamp(256, 65536);

    let variant = normalize_guest_variant(
        profile
            .vm_settings
            .as_ref()
            .and_then(|s| s.guest_variant.as_deref())
            .unwrap_or("4k"),
    );
    let (kernel, rootfs) = locate_guest(variant)?;

    let mut cmdline = String::from("console=ttyS0 root=/dev/vda rw");
    if profile.machine_type == MachineType::Container {
        let image = profile
            .container_settings
            .as_ref()
            .and_then(|s| s.container_ref.as_deref())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "Container needs an OCI image reference. No host container runtime."
                )
            })?;
        let entry = profile
            .container_settings
            .as_ref()
            .and_then(|s| s.entry_command.as_deref())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("");
        cmdline.push(' ');
        cmdline.push_str(&cmdline_token("wawona.kind", "container"));
        cmdline.push(' ');
        cmdline.push_str(&cmdline_token("wawona.image", image));
        if !entry.is_empty() {
            cmdline.push(' ');
            cmdline.push_str(&cmdline_token("wawona.entry", entry));
        }
    }

    Ok(kvm_console_argv(memory_mb, &kernel, &rootfs, &cmdline))
}

/// cloud-hypervisor argv, or `wawona-linux-vm-run` when that wrapper is on PATH.
/// `--serial tty` is the Wawona Terminal PTY. `--console off` keeps virtio
/// console from taking the same stream.
pub fn kvm_console_argv(memory_mb: i32, kernel: &str, rootfs: &str, cmdline: &str) -> Vec<String> {
    if let Some(wrapper) = find_on_path("wawona-linux-vm-run") {
        return vm_run_argv(&wrapper, memory_mb, kernel, rootfs, cmdline);
    }
    let program = find_on_path("cloud-hypervisor").unwrap_or_else(|| "cloud-hypervisor".into());
    cloud_hypervisor_argv(&program, memory_mb, kernel, rootfs, cmdline)
}

pub fn vm_run_argv(
    wrapper: &str,
    memory_mb: i32,
    kernel: &str,
    rootfs: &str,
    cmdline: &str,
) -> Vec<String> {
    vec![
        wrapper.to_string(),
        "--memory-mb".into(),
        memory_mb.to_string(),
        "--cpus".into(),
        "2".into(),
        "--cmdline".into(),
        cmdline.to_string(),
        "--kernel".into(),
        kernel.to_string(),
        "--rootfs".into(),
        rootfs.to_string(),
    ]
}

pub fn cloud_hypervisor_argv(
    program: &str,
    memory_mb: i32,
    kernel: &str,
    rootfs: &str,
    cmdline: &str,
) -> Vec<String> {
    vec![
        program.to_string(),
        "--cpus".into(),
        "boot=2".into(),
        "--memory".into(),
        format!("size={memory_mb}M"),
        "--kernel".into(),
        kernel.to_string(),
        "--disk".into(),
        format!("path={rootfs}"),
        "--cmdline".into(),
        cmdline.to_string(),
        "--serial".into(),
        "tty".into(),
        "--console".into(),
        "off".into(),
    ]
}

fn message_argv(message: &str) -> Vec<String> {
    let bin = find_on_path("echo").unwrap_or_else(|| "/bin/echo".into());
    vec![bin, message.to_string()]
}

pub fn normalize_guest_variant(raw: &str) -> &'static str {
    match raw.trim() {
        "16k" | "nixos-guest-16k" | "guest-16k" | "wawona-nixos-guest-16k" => "16k",
        _ => "4k",
    }
}

fn cmdline_token(key: &str, value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.as_bytes() {
        match byte {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'/' | b':' | b'@' => {
                encoded.push(*byte as char);
            }
            _ => encoded.push_str(&format!("%{byte:02X}")),
        }
    }
    format!("{key}={encoded}")
}

fn locate_guest(variant: &str) -> Result<(String, String)> {
    if let (Ok(kernel), Ok(rootfs)) = (
        std::env::var("WAWONA_VM_KERNEL"),
        std::env::var("WAWONA_VM_ROOTFS"),
    ) {
        let kernel = kernel.trim();
        let rootfs = rootfs.trim();
        if std::path::Path::new(kernel).is_file() && std::path::Path::new(rootfs).is_file() {
            return Ok((kernel.to_string(), rootfs.to_string()));
        }
    }

    let mut dirs = Vec::new();
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        dirs.push(
            std::path::PathBuf::from(xdg)
                .join("wawona/guests")
                .join(variant),
        );
    }
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(
            std::path::PathBuf::from(home)
                .join(".local/share/wawona/guests")
                .join(variant),
        );
    }
    dirs.push(std::path::PathBuf::from("/var/lib/wawona/guests").join(variant));

    for dir in &dirs {
        let kernel = ["Image", "vmlinuz", "kernel"]
            .into_iter()
            .map(|name| dir.join(name))
            .find(|path| path.is_file());
        let rootfs = ["rootfs.img", "disk.img", "rootfs"]
            .into_iter()
            .map(|name| dir.join(name))
            .find(|path| path.is_file());
        if let (Some(kernel), Some(rootfs)) = (kernel, rootfs) {
            return Ok((kernel.display().to_string(), rootfs.display().to_string()));
        }
    }

    let looked = dirs
        .iter()
        .map(|dir| dir.display().to_string())
        .collect::<Vec<_>>()
        .join(", ");
    bail!(
        "NixOS guest {variant} is not installed (Image + rootfs.img). Looked in {looked}. Set WAWONA_VM_KERNEL and WAWONA_VM_ROOTFS. No QEMU."
    )
}

fn find_on_path(name: &str) -> Option<String> {
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Some(candidate.display().to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kvm_argv_uses_serial_tty_not_a_shell() {
        let argv = cloud_hypervisor_argv(
            "cloud-hypervisor",
            2048,
            "/guest/Image",
            "/guest/rootfs.img",
            "console=ttyS0",
        );
        assert_eq!(argv[0], "cloud-hypervisor");
        assert!(argv
            .windows(2)
            .any(|pair| pair[0] == "--serial" && pair[1] == "tty"));
        assert!(argv
            .windows(2)
            .any(|pair| pair[0] == "--console" && pair[1] == "off"));
        assert!(!argv
            .iter()
            .any(|arg| arg == "-l" || arg == "-i" || arg == "zsh" || arg == "bash"));
    }

    #[test]
    fn container_cmdline_encodes_spaces() {
        let token = cmdline_token("wawona.entry", "/bin/sh -lc 'weston'");
        assert!(token.starts_with("wawona.entry="));
        assert!(!token.contains(' '));
        assert!(token.contains("%20") || token.contains("%2F"));
    }

    #[test]
    fn sixteen_k_variant_names() {
        assert_eq!(normalize_guest_variant("16k"), "16k");
        assert_eq!(normalize_guest_variant("wawona-nixos-guest-16k"), "16k");
        assert_eq!(normalize_guest_variant("nixos-guest-4k"), "4k");
        assert_eq!(normalize_guest_variant(""), "4k");
    }
}
