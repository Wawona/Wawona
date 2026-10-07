//! Capability results for Darwin CLI operations.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Capability {
    Supported,
    SupportedVirtual,
    SupportedRestricted,
    UnsupportedPlatform,
    UnsupportedSandbox,
    MissingEntitlement,
    MissingBackend,
}

impl Capability {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Supported => "Supported",
            Self::SupportedVirtual => "SupportedVirtual",
            Self::SupportedRestricted => "SupportedRestricted",
            Self::UnsupportedPlatform => "UnsupportedPlatform",
            Self::UnsupportedSandbox => "UnsupportedSandbox",
            Self::MissingEntitlement => "MissingEntitlement",
            Self::MissingBackend => "MissingBackend",
        }
    }
}

pub fn unavailable(cmd: &str, cap: Capability) -> i32 {
    eprintln!(
        "{cmd}: unavailable in this app ({})",
        cap.as_str()
    );
    1
}

pub fn virtual_note(cmd: &str, detail: &str) {
    eprintln!("{cmd}: Wawona scope ({}, {detail})", Capability::SupportedVirtual.as_str());
}
