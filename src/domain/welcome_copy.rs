//! First-launch welcome alert copy. Same on every product host.
//!
//! Apple (`WelcomeView` / Watch), Android (`MainActivity` AlertDialog), and
//! Linux (GTK MessageDialog) must use these exact strings. Rule:
//! `wawona-welcome-alert`.

pub const TITLE: &str = "Welcome to Wawona";
pub const MESSAGE: &str =
    "A Universal Wayland Compositor. Tap '+' to add a Machine.";
pub const CONTINUE: &str = "Continue";

#[cfg(test)]
mod tests {
    #[test]
    fn welcome_copy_locked() {
        assert_eq!(super::TITLE, "Welcome to Wawona");
        assert_eq!(
            super::MESSAGE,
            "A Universal Wayland Compositor. Tap '+' to add a Machine."
        );
        assert_eq!(super::CONTINUE, "Continue");
    }
}
