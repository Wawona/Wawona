//! Linux GTK talks the same Relay policy as `wawona_relay.h`.
//! Backend choice is not a Settings switch. Never QEMU.

use anyhow::{bail, Result};

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
