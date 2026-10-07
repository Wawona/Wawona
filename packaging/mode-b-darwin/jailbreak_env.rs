//! Jailbreak filesystem layout. Mode B packages only. Not linked into the App Store app.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum JailbreakKind {
    Rootful,
    Rootless,
    RootHide,
    Unknown,
}

pub struct JailbreakEnvironment {
    pub kind: JailbreakKind,
    prefix: String,
}

impl JailbreakEnvironment {
    pub fn detect() -> Self {
        if std::path::Path::new("/var/jb/usr/bin/dpkg").exists() {
            return Self {
                kind: JailbreakKind::Rootless,
                prefix: "/var/jb".into(),
            };
        }
        if std::path::Path::new("/usr/bin/dpkg").exists()
            && !std::path::Path::new("/usr/bin/sw_vers").exists()
        {
            return Self {
                kind: JailbreakKind::Rootful,
                prefix: String::new(),
            };
        }
        Self {
            kind: JailbreakKind::Unknown,
            prefix: String::new(),
        }
    }

    pub fn join(&self, bootstrap_path: &str) -> String {
        match self.kind {
            JailbreakKind::Rootless => format!("{}{}", self.prefix, bootstrap_path),
            JailbreakKind::RootHide => format!("jbroot:{}", bootstrap_path),
            _ => bootstrap_path.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rootless_join() {
        let env = JailbreakEnvironment {
            kind: JailbreakKind::Rootless,
            prefix: "/var/jb".into(),
        };
        assert_eq!(env.join("/usr/bin/ldid"), "/var/jb/usr/bin/ldid");
    }
}
