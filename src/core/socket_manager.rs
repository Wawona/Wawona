//! Socket Manager - handles multiple listening sockets for Wayland connections
//!
//! Supports:
//! - Unix domain sockets (primary and additional)
//! - vsock for VM connections
//! - Multiple simultaneous connection types

use std::os::unix::io::{AsRawFd, RawFd};

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use wayland_server::ListeningSocket;

/// Socket type enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SocketType {
    /// Primary Wayland socket (e.g., wayland-0)
    Primary,
    /// Additional Unix domain socket (e.g., for waypipe)
    Unix,
    /// vsock for VM connections
    Vsock,
}

/// Information about a bound socket
#[derive(Debug)]
pub struct SocketInfo {
    /// Type of socket
    pub socket_type: SocketType,
    /// Path (for Unix sockets) or identifier
    pub identifier: String,
    /// Port (for vsock)
    pub port: Option<u32>,
}

/// Manages multiple listening sockets for the compositor
pub struct SocketManager {
    /// Wayland listening sockets (primary + additional)
    sockets: Vec<(SocketType, ListeningSocket, SocketInfo)>,

    /// Primary socket identifier (e.g., "wayland-0")
    primary_socket: String,

    /// Runtime directory for Unix sockets
    runtime_dir: PathBuf,
}

impl SocketManager {
    /// Create a new socket manager
    pub fn new(runtime_dir: impl AsRef<Path>) -> Result<Self> {
        let runtime_dir = runtime_dir.as_ref().to_path_buf();

        // Ensure runtime directory exists
        if !runtime_dir.exists() {
            std::fs::create_dir_all(&runtime_dir).context("Failed to create runtime directory")?;
        }

        Ok(Self {
            sockets: Vec::new(),
            primary_socket: String::new(),
            runtime_dir,
        })
    }

    /// Bind the primary Wayland socket
    pub fn bind_primary(&mut self, socket_name: &str) -> Result<()> {
        let socket_path = self.runtime_dir.join(socket_name);

        // Remove existing socket if present
        let _ = std::fs::remove_file(&socket_path);

        tracing::info!("Binding primary socket: {}", socket_path.display());

        let socket = ListeningSocket::bind(&socket_path).context(format!(
            "Failed to bind primary socket at {}",
            socket_path.display()
        ))?;

        let info = SocketInfo {
            socket_type: SocketType::Primary,
            identifier: socket_path.to_string_lossy().to_string(),
            port: None,
        };

        self.sockets.push((SocketType::Primary, socket, info));
        self.primary_socket = socket_name.to_string();

        Ok(())
    }

    /// Add an additional Unix domain socket
    pub fn add_unix_socket(&mut self, path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref();

        // Remove existing socket if present
        let _ = std::fs::remove_file(path);

        tracing::info!("Binding additional Unix socket: {}", path.display());

        let socket = ListeningSocket::bind(path)
            .context(format!("Failed to bind Unix socket at {}", path.display()))?;

        let info = SocketInfo {
            socket_type: SocketType::Unix,
            identifier: path.to_string_lossy().to_string(),
            port: None,
        };

        self.sockets.push((SocketType::Unix, socket, info));

        Ok(())
    }

    /// Add a vsock listener
    ///
    /// Note: vsock support requires platform-specific implementation
    /// For now, this is a placeholder that will need platform-specific code
    pub fn add_vsock_listener(&mut self, port: u32) -> Result<()> {
        #[cfg(target_os = "linux")]
        {
            // TODO: Implement Linux vsock support using vm_sockets crate
            tracing::warn!("vsock support not yet implemented on Linux");
            anyhow::bail!("vsock not yet implemented");
        }

        #[cfg(not(target_os = "linux"))]
        {
            tracing::warn!("vsock only supported on Linux, port {} requested", port);
            anyhow::bail!("vsock not supported on this platform");
        }
    }

    /// Remove a socket by its path/identifier
    pub fn remove_socket(&mut self, identifier: &str) -> Result<()> {
        let initial_len = self.sockets.len();

        self.sockets
            .retain(|(_, _, info)| info.identifier != identifier);

        if self.sockets.len() < initial_len {
            tracing::info!("Removed socket: {}", identifier);

            // Clean up the file if it's a Unix socket
            let path = Path::new(identifier);
            if path.exists() {
                let _ = std::fs::remove_file(path);
            }

            Ok(())
        } else {
            anyhow::bail!("Socket not found: {}", identifier);
        }
    }

    /// Get information about all bound sockets
    pub fn get_socket_info(&self) -> Vec<&SocketInfo> {
        self.sockets.iter().map(|(_, _, info)| info).collect()
    }

    /// Get the primary socket name
    pub fn primary_socket_name(&self) -> &str {
        &self.primary_socket
    }

    /// Get the primary socket path
    pub fn primary_socket_path(&self) -> PathBuf {
        self.runtime_dir.join(&self.primary_socket)
    }

    /// Get all file descriptors for polling
    pub fn poll_fds(&self) -> Vec<RawFd> {
        self.sockets
            .iter()
            .map(|(_, socket, _)| socket.as_raw_fd())
            .collect()
    }

    /// Accept a connection from any socket
    ///
    /// Returns `None` if no connections are pending
    pub fn accept_any(&mut self) -> Option<(SocketType, std::os::unix::net::UnixStream)> {
        for (socket_type, socket, _) in &mut self.sockets {
            if let Ok(Some(stream)) = socket.accept() {
                return Some((*socket_type, stream));
            }
        }
        None
    }

    /// Get reference to a specific socket by type
    pub fn get_socket(&self, socket_type: SocketType) -> Option<&ListeningSocket> {
        self.sockets
            .iter()
            .find(|(st, _, _)| *st == socket_type)
            .map(|(_, socket, _)| socket)
    }

    /// Close all sockets and clean up socket files
    ///
    /// This should be called during graceful shutdown to ensure
    /// clients receive proper disconnect notifications
    pub fn close_all(&mut self) {
        tracing::info!("Closing {} socket(s)", self.sockets.len());

        // Clean up socket files for Unix sockets
        for (_, _, info) in &self.sockets {
            if matches!(info.socket_type, SocketType::Primary | SocketType::Unix) {
                let path = std::path::Path::new(&info.identifier);
                if path.exists() {
                    if let Err(e) = std::fs::remove_file(path) {
                        tracing::warn!("Failed to remove socket file {}: {}", info.identifier, e);
                    } else {
                        tracing::debug!("Removed socket file: {}", info.identifier);
                    }
                }
            }
        }

        // Clear the sockets - this drops them and closes the underlying fds
        self.sockets.clear();
        tracing::debug!("All sockets closed");
    }
}

impl Drop for SocketManager {
    fn drop(&mut self) {
        // Clean up socket files
        for (_, _, info) in &self.sockets {
            if matches!(info.socket_type, SocketType::Primary | SocketType::Unix) {
                let path = Path::new(&info.identifier);
                if path.exists() {
                    let _ = std::fs::remove_file(path);
                    tracing::debug!("Cleaned up socket: {}", info.identifier);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn get_test_runtime_dir() -> PathBuf {
        use std::time::{SystemTime, UNIX_EPOCH};
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("wawona-test-{}-{}", std::process::id(), timestamp));
        let _ = std::fs::create_dir_all(&dir);
        dir
    }

    #[test]
    fn test_socket_manager_creation() {
        let runtime_dir = get_test_runtime_dir();
        let manager = SocketManager::new(&runtime_dir);
        assert!(manager.is_ok());
        let _ = std::fs::remove_dir_all(runtime_dir);
    }

    #[test]
    fn test_bind_primary_socket() {
        let runtime_dir = get_test_runtime_dir();
        let mut manager = SocketManager::new(&runtime_dir).unwrap();

        let result = manager.bind_primary("wayland-test-0");
        assert!(
            result.is_ok(),
            "Failed to bind primary socket: {:?}",
            result.err()
        );
        assert_eq!(manager.primary_socket_name(), "wayland-test-0");

        // Verify socket file exists
        let socket_path = runtime_dir.join("wayland-test-0");
        assert!(socket_path.exists());

        let _ = std::fs::remove_dir_all(runtime_dir);
    }

    #[test]
    fn test_add_unix_socket() {
        let runtime_dir = get_test_runtime_dir();
        let mut manager = SocketManager::new(&runtime_dir).unwrap();

        manager.bind_primary("wayland-test-0").unwrap();

        let additional_socket = runtime_dir.join("waypipe-test");
        let result = manager.add_unix_socket(&additional_socket);
        assert!(
            result.is_ok(),
            "Failed to add unix socket: {:?}",
            result.err()
        );

        // Verify we have 2 sockets
        assert_eq!(manager.get_socket_info().len(), 2);

        let _ = std::fs::remove_dir_all(runtime_dir);
    }

    #[test]
    fn test_remove_socket() {
        let runtime_dir = get_test_runtime_dir();
        let mut manager = SocketManager::new(&runtime_dir).unwrap();

        manager.bind_primary("wayland-test-0").unwrap();

        let additional_socket = runtime_dir.join("waypipe-test");
        manager.add_unix_socket(&additional_socket).unwrap();

        // Remove the additional socket
        let socket_path = additional_socket.to_string_lossy().to_string();
        let result = manager.remove_socket(&socket_path);
        assert!(result.is_ok());

        // Verify we're back to 1 socket
        assert_eq!(manager.get_socket_info().len(), 1);

        let _ = std::fs::remove_dir_all(runtime_dir);
    }
}
