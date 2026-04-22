use wayland_server::{Display, ListeningSocket};

use crate::core::state::CompositorState;
use anyhow::{Result, Context};


pub struct WawonaDisplay {
    // The wayland display
    pub display: Display<CompositorState>,
    // The socket we are listening on
    pub socket: ListeningSocket,
}

impl WawonaDisplay {
    pub fn new() -> Result<Self> {
        let mut display = Display::new()?;
        
        // Get or create XDG_RUNTIME_DIR following XDG Base Directory Specification
        let runtime_dir = Self::ensure_runtime_dir()?;
        
        let socket_path = format!("{}/wayland-0", runtime_dir);
        
        // Remove existing socket if present
        let _ = std::fs::remove_file(&socket_path);
        
        let socket = ListeningSocket::bind(&socket_path)
            .context(format!("Failed to bind socket at {}", socket_path))?;

        crate::wlog!(crate::util::logging::DISPLAY, "Compositor listening on: {}", socket_path);
        crate::wlog!(crate::util::logging::DISPLAY, "XDG_RUNTIME_DIR: {}", runtime_dir);
        crate::wlog!(crate::util::logging::DISPLAY, "Set WAYLAND_DISPLAY=wayland-0 to connect clients");
        tracing::info!("Listening on {}", socket_path);
        
        // Register Wayland protocol globals
        Self::register_globals(&mut display)?;

        Ok(Self { display, socket })
    }
    
    /// Register all Wayland protocol globals
    ///
    /// NOTE: Global registration is centralized in `core::compositor::Compositor`
    /// and initialized through `smithay_runtime`. This helper is intentionally a
    /// no-op to avoid dual registration paths.
    fn register_globals(_display: &mut Display<CompositorState>) -> Result<()> {
        tracing::debug!("WawonaDisplay::register_globals is no-op (compositor path owns registration)");
        Ok(())
    }

    /// Ensure XDG_RUNTIME_DIR exists with proper permissions (0700)
    /// Following XDG Base Directory Specification
    fn ensure_runtime_dir() -> Result<String> {
        use std::os::unix::fs::PermissionsExt;
        
        // Check if XDG_RUNTIME_DIR is already set
        if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
            // Verify it exists and has correct permissions
            if let Ok(metadata) = std::fs::metadata(&dir) {
                let perms = metadata.permissions();
                if perms.mode() & 0o777 == 0o700 {
                    return Ok(dir);
                }
                crate::wlog!(crate::util::logging::DISPLAY, "Warning: XDG_RUNTIME_DIR has incorrect permissions, creating new one");
            }
        }
        
        // Create runtime directory: /tmp/<UID>-runtime
        // This follows the XDG spec for systems without /run/user
        let uid = unsafe { libc::getuid() };
        let runtime_dir = format!("/tmp/{}-runtime", uid);
        
        // Create directory if it doesn't exist
        std::fs::create_dir_all(&runtime_dir)?;
        
        // Set strict permissions: 0700 (owner read/write/execute only)
        let mut perms = std::fs::metadata(&runtime_dir)?.permissions();
        perms.set_mode(0o700);
        std::fs::set_permissions(&runtime_dir, perms)?;
        
        // Set XDG_RUNTIME_DIR for child processes
        std::env::set_var("XDG_RUNTIME_DIR", &runtime_dir);
        
        crate::wlog!(crate::util::logging::DISPLAY, "Created XDG_RUNTIME_DIR: {} (mode: 0700)", 
            runtime_dir);
        
        Ok(runtime_dir)
    }

    pub fn handle(&self) -> wayland_server::DisplayHandle {
        self.display.handle()
    }
}
