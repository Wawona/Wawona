//! Central compositor state machine.
//!
//! The `Compositor` struct is the heart of Wawona. It manages:
//! - Wayland display and client connections
//! - Global protocol objects
//! - Event dispatching
//! - Frame timing
//!
//! This is the Rust core that platform adapters interact with via FFI.

use std::sync::{Arc, Mutex};
use std::collections::{HashMap, HashSet};
use std::os::unix::io::{AsRawFd, RawFd};
use std::time::{Duration, Instant};

use wayland_server::{Display, DisplayHandle};
use wayland_server::backend::{ClientData, ClientId, DisconnectReason};
use anyhow::{Result, Context};

use crate::core::state::CompositorState;
use crate::core::window::DecorationMode;
use crate::core::errors::CoreError;
use crate::core::socket_manager::SocketManager;
use crate::core::traits::ProtocolState;

// Import protocol modules to ensure trait impls are linked
#[allow(unused_imports)]
use crate::core::wayland::ext::subcompositor;
#[allow(unused_imports)]
use crate::core::wayland::ext::data_device;
#[allow(unused_imports)]
use crate::core::wayland::xdg::decoration;
#[allow(unused_imports)]
use crate::core::wayland::xdg::xdg_output;
#[allow(unused_imports)]
use crate::core::wayland::ext::viewporter;
#[allow(unused_imports)]
use crate::core::wayland::ext::presentation_time;
#[allow(unused_imports)]
use crate::core::wayland::ext::relative_pointer;
#[allow(unused_imports)]
use crate::core::wayland::ext::pointer_constraints;
#[allow(unused_imports)]
use crate::core::wayland::ext::pointer_gestures;
#[allow(unused_imports)]
use crate::core::wayland::ext::idle_inhibit;
#[allow(unused_imports)]
use crate::core::wayland::ext::text_input;
#[allow(unused_imports)]
use crate::core::wayland::ext::keyboard_shortcuts_inhibit;
#[allow(unused_imports)]
use crate::core::wayland::ext::linux_dmabuf;
#[allow(unused_imports)]
use crate::core::wayland::ext::linux_explicit_sync;
#[allow(unused_imports)]
use crate::core::wayland::xdg::xdg_foreign;
#[allow(unused_imports)]
use crate::core::wayland::wlr::{layer_shell, output_management, output_power_management, foreign_toplevel_management, screencopy, gamma_control, data_control, export_dmabuf};

// ============================================================================
// Client Data
// ============================================================================

/// Per-client data stored with each Wayland connection
#[derive(Debug, Clone)]
pub struct WawonaClientData {
    /// Unique client identifier (internal)
    pub id: u32,
    /// backend identifier
    pub backend_id: ClientId,
    /// Process ID of the client (if available)
    pub pid: Option<u32>,
    /// Connection timestamp
    pub connected_at: Instant,
    /// Shared queue where disconnect callbacks are recorded for the compositor loop
    pub disconnected_queue: Arc<Mutex<Vec<ClientId>>>,
}

impl WawonaClientData {
    pub fn new(
        id: u32,
        backend_id: wayland_server::backend::ClientId,
        disconnected_queue: Arc<Mutex<Vec<ClientId>>>,
    ) -> Self {
        Self {
            id,
            backend_id,
            pid: None,
            connected_at: Instant::now(),
            disconnected_queue,
        }
    }
}

impl ClientData for WawonaClientData {
    fn initialized(&self, client_id: ClientId) {
        tracing::info!("Client {} initialized (internal id: {:?})", self.id, client_id);
    }
    
    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        let reason_str = match reason {
            DisconnectReason::ConnectionClosed => "connection closed",
            DisconnectReason::ProtocolError(_) => "protocol error",
        };
        tracing::info!("Client {} disconnected: {} (internal id: {:?})", 
            self.id, reason_str, client_id);
        if let Ok(mut queue) = self.disconnected_queue.lock() {
            queue.push(client_id);
        }
    }
}

// ============================================================================
// Compositor Configuration
// ============================================================================

/// Configuration for the compositor
#[derive(Debug, Clone)]
pub struct CompositorConfig {
    /// Socket name (e.g., "wayland-0")
    pub socket_name: String,
    /// Force server-side decorations
    pub force_ssd: bool,
    /// Initial output width
    pub output_width: u32,
    /// Initial output height
    pub output_height: u32,
    /// Output scale factor
    pub output_scale: f32,
    /// Keyboard repeat rate (Hz)
    pub keyboard_repeat_rate: i32,
    /// Keyboard repeat delay (ms)
    pub keyboard_repeat_delay: i32,
    /// Whether to advertise zwp_fullscreen_shell_v1
    pub advertise_fullscreen_shell: bool,
}

impl Default for CompositorConfig {
    fn default() -> Self {
        Self {
            socket_name: "wayland-0".to_string(),
            force_ssd: false,
            output_width: 1920,
            output_height: 1080,
            output_scale: 1.0,
            keyboard_repeat_rate: 33,
            keyboard_repeat_delay: 500,
            advertise_fullscreen_shell: false,
        }
    }
}

// ============================================================================
// Compositor Events
// ============================================================================

/// Events emitted by the compositor for the platform to handle
#[derive(Debug, Clone)]
pub enum CompositorEvent {
    /// A new client connected
    ClientConnected { client_id: wayland_server::backend::ClientId, pid: Option<u32> },
    /// A client disconnected
    ClientDisconnected {
        client_id: wayland_server::backend::ClientId,
        internal_id: u32,
    },
    /// A new window was created
    WindowCreated {
        client_id: ClientId,
        window_id: u32,
        surface_id: u32,
        title: String,
        width: u32,
        height: u32,
        decoration_mode: DecorationMode,
        fullscreen_shell: bool,
    },
    /// A new popup was created
    PopupCreated { client_id: ClientId, window_id: u32, surface_id: u32, parent_id: u32, x: i32, y: i32, width: u32, height: u32 },
    /// A popup was repositioned
    PopupRepositioned { window_id: u32, x: i32, y: i32, width: u32, height: u32 },
    /// A window was destroyed
    WindowDestroyed { window_id: u32 },
    /// Window title changed
    WindowTitleChanged { window_id: u32, title: String },
    /// Window size changed
    WindowSizeChanged { window_id: u32, width: u32, height: u32 },
    /// Window decoration mode changed (CSD/SSD)
    DecorationModeChanged { window_id: u32, mode: DecorationMode },
    /// Window requests activation
    WindowActivationRequested { window_id: u32 },
    /// Window requests close
    WindowCloseRequested { window_id: u32 },
    /// Window was minimized or unminimized
    WindowMinimized { window_id: u32, minimized: bool },
    /// Window was maximized or unmaximized
    WindowMaximized { window_id: u32, maximized: bool },
    /// Window requests interactive move
    WindowMoveRequested { window_id: u32, seat_id: u32, serial: u32 },
    /// Window requests interactive resize
    WindowResizeRequested { window_id: u32, seat_id: u32, serial: u32, edges: u32 },
    /// Surface committed with new buffer
    SurfaceCommitted { client_id: ClientId, surface_id: u32, buffer_id: Option<u64> },
    /// Layer surface committed with new buffer (for wlr-layer-shell)
    LayerSurfaceCommitted { client_id: ClientId, surface_id: u32, buffer_id: Option<u64> },
    /// Cursor surface committed with hotspot info
    CursorCommitted { client_id: ClientId, surface_id: u32, buffer_id: Option<u64>, hotspot_x: i32, hotspot_y: i32 },
    /// Cursor shape changed via wp_cursor_shape protocol
    CursorShapeChanged { shape: u32 },
    /// System bell / notification requested by client
    SystemBell { client_id: ClientId, surface_id: u32 },
    /// Redraw needed
    RedrawNeeded { window_id: u32 },
}

// ============================================================================
// Main Compositor
// ============================================================================

/// The main compositor object.
///
/// This manages the entire compositor lifecycle:
/// - Creating and binding the Wayland socket
/// - Accepting client connections
/// - Processing Wayland events
/// - Managing compositor state
pub struct Compositor {
    /// Wayland display
    display: Display<CompositorState>,
    
    /// Socket manager (handles multiple sockets)
    socket_manager: SocketManager,
    
    /// Compositor configuration
    config: CompositorConfig,
    
    /// Next client ID
    next_client_id: u32,
    
    /// Connected clients
    clients: HashMap<u32, WawonaClientData>,
    
    /// Disconnect notifications collected from ClientData callbacks
    disconnected_clients: Arc<Mutex<Vec<ClientId>>>,
    
    /// Event queue for platform
    events: Vec<CompositorEvent>,
    
    /// Running state
    running: bool,
    
    /// Serial number generator
    serial: u32,
    
    /// Last frame time
    last_frame: Instant,
    
    /// Last ping time for heartbeats
    last_ping: Instant,
}

impl Compositor {
    /// Create a new compositor with the given configuration
    pub fn new(config: CompositorConfig) -> Result<Self> {
        tracing::info!("Creating compositor with socket: {}", config.socket_name);
        
        // Create the Wayland display
        let display = Display::new()
            .context("Failed to create Wayland display")?;
        
        // Ensure runtime directory exists
        let runtime_dir = Self::ensure_runtime_dir()?;
        
        // Create socket manager and bind primary socket
        let mut socket_manager = SocketManager::new(&runtime_dir)?;
        socket_manager.bind_primary(&config.socket_name)?;
        
        tracing::info!("Compositor listening on: {}", socket_manager.primary_socket_path().display());
        
        Ok(Self {
            display,
            socket_manager,
            config,
            next_client_id: 1,
            clients: HashMap::new(),
            disconnected_clients: Arc::new(Mutex::new(Vec::new())),
            events: Vec::new(),
            running: false,
            serial: 1,
            last_frame: Instant::now(),
            last_ping: Instant::now(),
        })
    }
    
    /// Create compositor with default configuration
    pub fn new_default() -> Result<Self> {
        Self::new(CompositorConfig::default())
    }
    
    /// Get the display handle for registering globals
    pub fn display_handle(&self) -> DisplayHandle {
        self.display.handle()
    }
    
    /// Get the socket path
    pub fn socket_path(&self) -> String {
        self.socket_manager.primary_socket_path().to_string_lossy().to_string()
    }
    
    /// Get the socket name
    pub fn socket_name(&self) -> &str {
        self.socket_manager.primary_socket_name()
    }
    
    /// Get the socket file descriptors for polling
    pub fn socket_fds(&self) -> Vec<RawFd> {
        self.socket_manager.poll_fds()
    }
    
    /// Add an additional Unix socket
    pub fn add_unix_socket(&mut self, path: &str) -> Result<()> {
        self.socket_manager.add_unix_socket(path)
            .context(format!("Failed to add Unix socket: {}", path))
    }
    
    /// Add a vsock listener
    pub fn add_vsock_listener(&mut self, port: u32) -> Result<()> {
        self.socket_manager.add_vsock_listener(port)
            .context(format!("Failed to add vsock listener on port {}", port))
    }
    
    /// Remove a socket
    pub fn remove_socket(&mut self, identifier: &str) -> Result<()> {
        self.socket_manager.remove_socket(identifier)
            .context(format!("Failed to remove socket: {}", identifier))
    }
    
    /// Get list of all socket paths
    pub fn get_socket_paths(&self) -> Vec<String> {
        self.socket_manager.get_socket_info()
            .iter()
            .map(|info| info.identifier.clone())
            .collect()
    }
    
    /// Get the display file descriptor for polling
    pub fn display_fd(&mut self) -> RawFd {
        self.display.backend().poll_fd().as_raw_fd()
    }
    
    /// Check if compositor is running
    pub fn is_running(&self) -> bool {
        self.running
    }
    
    /// Get configuration
    pub fn config(&self) -> &CompositorConfig {
        &self.config
    }
    
    /// Get mutable configuration
    pub fn config_mut(&mut self) -> &mut CompositorConfig {
        &mut self.config
    }
    
    // =========================================================================
    // Lifecycle
    // =========================================================================
    
    /// Start the compositor
    /// 
    /// This registers all protocol globals and prepares for client connections.
    pub fn start(&mut self, state: &mut CompositorState) -> Result<()> {
        if self.running {
            return Err(CoreError::state_error("Compositor already running").into());
        }
        
        tracing::info!("Starting compositor");
        
        // Register protocol globals
        self.register_globals(state)?;
        
        self.running = true;
        self.last_frame = Instant::now();
        
        tracing::info!("Compositor started successfully");
        Ok(())
    }
    
    /// Stop the compositor
    pub fn stop(&mut self) -> Result<()> {
        if !self.running {
            return Err(CoreError::state_error("Compositor not running").into());
        }
        
        tracing::info!("Stopping compositor - disconnecting {} clients", self.clients.len());
        
        // Properly disconnect all clients by killing their connections.
        let client_ids: Vec<u32> = self.clients.keys().copied().collect();
        let client_count = client_ids.len();
        for client_id in client_ids {
            let _ = self.disconnect_client_by_internal(client_id);
        }

        // Drop remaining local bookkeeping after disconnect requests.
        self.clients.clear();
        
        // Flush any pending events to clients before shutdown
        // This ensures clients receive disconnect notifications
        if let Err(e) = self.display.flush_clients() {
            tracing::warn!("Error flushing clients during shutdown: {}", e);
        }
        
        // Give clients a brief moment to process disconnect
        // This helps prevent the "dispatch function returned negative value" spam
        std::thread::sleep(std::time::Duration::from_millis(50));
        
        // Close all sockets
        self.socket_manager.close_all();
        
        self.running = false;
        
        tracing::info!("Compositor stopped ({} clients disconnected)", client_count);
        Ok(())
    }
    
    /// Register all Wayland protocol globals
    fn register_globals(&mut self, state: &mut CompositorState) -> Result<()> {
        let dh = self.display.handle();

        // Register protocols by category
        crate::core::wayland::wayland::register(state, &dh);
        crate::core::wayland::xdg::register(state, &dh);
        crate::core::wayland::wlr::register(state, &dh);
        crate::core::wayland::plasma::register(state, &dh);
        crate::core::wayland::ext::register(state, &dh);

        Ok(())
    }
    
    // =========================================================================
    // Event Processing
    // =========================================================================
    
    /// Accept pending client connections
    pub fn accept_connections(&mut self, _state: &mut CompositorState) {
        let mut display_handle = self.display.handle();
        // Accept new client connections from all sockets
        while let Some((_socket_type, stream)) = self.socket_manager.accept_any() {
            let next_id = self.next_client_id;
            self.next_client_id += 1;
            
            // Install disconnect-aware client data immediately so the backend
            // callback queue remains accurate for all clients.
            #[derive(Clone)]
            struct ConnectedClientData {
                internal_id: u32,
                disconnected_queue: Arc<Mutex<Vec<ClientId>>>,
            }

            impl ClientData for ConnectedClientData {
                fn initialized(&self, client_id: ClientId) {
                    tracing::info!(
                        "Client {} initialized (backend id: {:?})",
                        self.internal_id,
                        client_id
                    );
                }

                fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
                    let reason_str = match reason {
                        DisconnectReason::ConnectionClosed => "connection closed",
                        DisconnectReason::ProtocolError(_) => "protocol error",
                    };
                    tracing::info!(
                        "Client {} disconnected: {} (backend id: {:?})",
                        self.internal_id,
                        reason_str,
                        client_id
                    );
                    if let Ok(mut queue) = self.disconnected_queue.lock() {
                        queue.push(client_id);
                    }
                }
            }

            let client_data_for_backend = ConnectedClientData {
                internal_id: next_id,
                disconnected_queue: self.disconnected_clients.clone(),
            };

            match display_handle.insert_client(stream, Arc::new(client_data_for_backend)) {
                Ok(client) => {
                    let backend_id = client.id();
                    tracing::info!("Accepted client connection: {} (backend={:?})", next_id, backend_id);
                    
                    let client_data = WawonaClientData::new(
                        next_id,
                        backend_id.clone(),
                        self.disconnected_clients.clone(),
                    );
                    
                    // Track the client
                    self.clients.insert(next_id, client_data.clone());
                    
                    // Emit event
                    self.events.push(CompositorEvent::ClientConnected {
                        client_id: backend_id,
                        pid: client_data.pid,
                    });
                }
                Err(e) => {
                    tracing::error!("Failed to insert client: {}", e);
                }
            }
        }
    }

    /// Convert backend ClientId to internal u32 (as used in FFI)
    pub fn client_id_to_internal(&self, client_id: ClientId) -> u32 {
        for (&id, data) in &self.clients {
            if data.backend_id == client_id {
                return id;
            }
        }
        0
    }
    
    /// Convert internal u32 back to backend ClientId
    pub fn internal_to_client_id(&self, internal_id: u32) -> Option<ClientId> {
        self.clients.get(&internal_id).map(|data| data.backend_id.clone())
    }
    
    /// Dispatch pending Wayland events
    pub fn dispatch(&mut self, state: &mut CompositorState) -> Result<usize> {
        if !self.running {
            return Ok(0);
        }
        
        // Accept any pending connections first
        self.accept_connections(state);
        
        // Dispatch events to clients.
        //
        // A nested compositor (weston, cage, etc.) exiting can race with
        // dispatch/flush and produce transient backend errors. Those should not
        // be treated as fatal for the host compositor.
        let dispatched = match self.display.dispatch_clients(state) {
            Ok(count) => count,
            Err(e) => {
                tracing::warn!(
                    "Non-fatal Wayland dispatch error (client likely disconnected): {}",
                    e
                );
                0
            }
        };
        
        // Flush client event queues. Treat disconnect-related failures as
        // non-fatal to keep the compositor alive for remaining clients.
        if let Err(e) = self.display.flush_clients() {
            tracing::warn!(
                "Non-fatal Wayland flush error (client likely disconnected): {}",
                e
            );
        }
        
        // Reconcile clients that disconnected during dispatch/flush.
        self.reconcile_disconnected_clients(state);
        
        // Fire presentation feedback for any committed frames
        state.fire_presentation_feedback();
        
        // Periodic heartbeat for shell clients (every 1 second)
        if self.last_ping.elapsed().as_secs() >= 1 {
            self.ping_clients(state);
            self.last_ping = Instant::now();
        }
        
        Ok(dispatched)
    }

    /// Drain disconnect callback queue and clean up state for disconnected clients.
    fn reconcile_disconnected_clients(&mut self, state: &mut CompositorState) {
        let disconnected = {
            let mut queue = match self.disconnected_clients.lock() {
                Ok(q) => q,
                Err(_) => {
                    tracing::warn!("Failed to lock disconnected client queue");
                    return;
                }
            };
            queue.drain(..).collect::<Vec<_>>()
        };

        if disconnected.is_empty() {
            return;
        }

        let mut seen = HashSet::new();
        for backend_id in disconnected {
            if !seen.insert(backend_id.clone()) {
                continue;
            }

            let internal_id = self
                .clients
                .iter()
                .find_map(|(id, data)| (data.backend_id == backend_id).then_some(*id));

            state.client_disconnected(backend_id.clone());
            self.events.push(CompositorEvent::ClientDisconnected {
                client_id: backend_id.clone(),
                internal_id: internal_id.unwrap_or(0),
            });
            if let Some(id) = internal_id {
                self.clients.remove(&id);
            }
        }
    }
    
    /// Dispatch with timeout (for poll-based event loops).
    /// Currently dispatches without blocking; proper epoll-based dispatch with
    /// timeout requires platform-specific `poll(2)` / `kevent()` integration.
    pub fn dispatch_timeout(&mut self, state: &mut CompositorState, _timeout: Duration) -> Result<usize> {
        self.dispatch(state)
    }
    
    /// Flush all client event queues
    pub fn flush(&mut self) -> Result<()> {
        // Client disconnects can race with flush. Do not hard-fail the main
        // compositor loop when this happens.
        if let Err(e) = self.display.flush_clients() {
            tracing::warn!(
                "Non-fatal flush_clients error (client likely disconnected): {}",
                e
            );
        }
        Ok(())
    }
    
    // =========================================================================
    // Serial Numbers
    // =========================================================================
    
    /// Get the next serial number
    pub fn next_serial(&mut self) -> u32 {
        let serial = self.serial;
        self.serial = self.serial.wrapping_add(1);
        serial
    }
    
    /// Get current serial without incrementing
    pub fn current_serial(&self) -> u32 {
        self.serial
    }
    
    // =========================================================================
    // Events
    // =========================================================================
    
    /// Take all pending events (clears the internal queue)
    pub fn take_events(&mut self) -> Vec<CompositorEvent> {
        std::mem::take(&mut self.events)
    }
    
    /// Push an event to the queue
    pub fn push_event(&mut self, event: CompositorEvent) {
        self.events.push(event);
    }
    
    /// Check if there are pending events
    pub fn has_events(&self) -> bool {
        !self.events.is_empty()
    }
    
    // =========================================================================
    // Frame Timing
    // =========================================================================
    
    /// Get time since last frame in milliseconds
    pub fn time_since_last_frame_ms(&self) -> u32 {
        self.last_frame.elapsed().as_millis() as u32
    }
    
    /// Mark frame as complete
    pub fn mark_frame_complete(&mut self, state: &mut CompositorState) {
        self.last_frame = Instant::now();
        state.flush_buffer_releases();
    }
    
    /// Get current timestamp in milliseconds (for Wayland events)
    pub fn timestamp_ms() -> u32 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u32
    }
    
    // =========================================================================
    // Client Management
    // =========================================================================
    
    /// Get connected client count
    pub fn client_count(&self) -> usize {
        self.clients.len()
    }
    
    /// Get client IDs
    pub fn client_ids(&self) -> Vec<u32> {
        self.clients.keys().copied().collect()
    }

    /// Forcefully disconnect a tracked client by internal ID.
    pub fn disconnect_client_by_internal(&mut self, internal_id: u32) -> bool {
        let Some(client_data) = self.clients.get(&internal_id).cloned() else {
            tracing::warn!("Disconnect requested for unknown client {}", internal_id);
            return false;
        };

        let backend_id = client_data.backend_id.clone();

        let display_handle = self.display.handle();
        tracing::info!(
            "Force disconnecting client {} (backend={:?})",
            internal_id,
            backend_id
        );
        display_handle
            .backend_handle()
            .kill_client(backend_id.clone(), DisconnectReason::ConnectionClosed);
        true
    }
    
    // =========================================================================
    // Helpers
    // =========================================================================
    
    /// Ensure XDG_RUNTIME_DIR exists with proper permissions
    fn ensure_runtime_dir() -> Result<String> {
        use std::os::unix::fs::PermissionsExt;
        
        // Check if XDG_RUNTIME_DIR is already set (e.g. by the ObjC/Swift layer on iOS)
        if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
            if let Ok(metadata) = std::fs::metadata(&dir) {
                let perms = metadata.permissions();
                if perms.mode() & 0o777 == 0o700 {
                    return Ok(dir);
                }
                // On iOS, the sandbox already provides isolation — the app container
                // tmp directory may not have 0o700 perms. Try to tighten them, but
                // accept the directory regardless since /tmp is not writable on iOS.
                let mut new_perms = perms.clone();
                new_perms.set_mode(0o700);
                if let Err(e) = std::fs::set_permissions(&dir, new_perms) {
                    tracing::warn!(
                        "Could not set 0700 on XDG_RUNTIME_DIR ({}): {} — using as-is",
                        dir, e
                    );
                }
                return Ok(dir);
            }
        }
        
        // Create runtime directory: /tmp/wawona-<UID>
        // Must match the macosEnv path in flake.nix and the ObjC bridge
        let uid = unsafe { libc::getuid() };
        let runtime_dir = format!("/tmp/wawona-{}", uid);
        
        // Create directory if it doesn't exist
        std::fs::create_dir_all(&runtime_dir)?;
        
        // Set strict permissions: 0700
        let mut perms = std::fs::metadata(&runtime_dir)?.permissions();
        perms.set_mode(0o700);
        std::fs::set_permissions(&runtime_dir, perms)?;
        
        // Set environment variable
        std::env::set_var("XDG_RUNTIME_DIR", &runtime_dir);
        
        tracing::debug!("Created XDG_RUNTIME_DIR: {}", runtime_dir);
        Ok(runtime_dir)
    }

    /// Send ping to all shell clients and track for timeout
    pub fn ping_clients(&mut self, state: &mut CompositorState) {
        let now = Instant::now();

        // Check for timed-out pings (>10 seconds without pong)
        let timed_out: Vec<u32> = state.xdg.pending_pings.iter()
            .filter(|(_, (_, _, ts))| now.duration_since(*ts).as_secs() > 10)
            .map(|(serial, _)| *serial)
            .collect();

        for stale_serial in timed_out {
            if let Some((client_id, shell_resource_id, ts)) = state.xdg.pending_pings.remove(&stale_serial) {
                tracing::warn!(
                    "xdg_wm_base ping timeout: serial={}, client={:?}, shell={}, elapsed={:.1}s — client may be unresponsive",
                    stale_serial, client_id, shell_resource_id, now.duration_since(ts).as_secs_f64()
                );
            }
        }

        // Snapshot shell resources to avoid mutable/immutable borrow conflicts
        // while allocating serials and updating ping bookkeeping.
        let shell_targets = state
            .xdg
            .shell_resources
            .iter()
            .map(|((client_id, resource_id), shell)| {
                (client_id.clone(), *resource_id, shell.clone())
            })
            .collect::<Vec<_>>();

        // Send new pings with unique serial per client/resource pair.
        for (client_id, resource_id, shell) in shell_targets {
            state.xdg.pending_pings.retain(|_, (cid, sid, _)| {
                *cid != client_id || *sid != resource_id
            });
            let serial = self.next_serial();
            shell.ping(serial);
            state
                .xdg
                .pending_pings
                .insert(serial, (client_id.clone(), resource_id, now));
            tracing::trace!(
                "Sent xdg_wm_base ping: serial={}, client={:?}, shell={}",
                serial,
                client_id,
                resource_id
            );
        }

        // Check idle timeouts and send idled/resumed events
        state.ext.idle_notify.check_idle();
    }
}

impl Default for Compositor {
    fn default() -> Self {
        Self::new_default().expect("Failed to create default compositor")
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::net::UnixStream;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;
    use wayland_server::Display;

    static TEST_SOCKET_SEQ: AtomicU64 = AtomicU64::new(0);

    /// Avoid parallel test collisions on `XDG_RUNTIME_DIR/wayland-0`.
    fn test_compositor() -> Compositor {
        let mut cfg = CompositorConfig::default();
        cfg.socket_name = format!(
            "wayland-test-{}",
            TEST_SOCKET_SEQ.fetch_add(1, Ordering::Relaxed)
        );
        Compositor::new(cfg).unwrap()
    }

    fn make_backend_client_id() -> ClientId {
        let display = Display::<CompositorState>::new().unwrap();
        let mut handle = display.handle();
        let (server_sock, _client_sock) = UnixStream::pair().unwrap();
        let client_data = crate::core::state::ClientState::default();
        let client = handle
            .insert_client(server_sock, Arc::new(client_data))
            .unwrap();
        client.id()
    }
    
    #[test]
    fn test_config_default() {
        let config = CompositorConfig::default();
        assert_eq!(config.socket_name, "wayland-0");
        assert_eq!(config.output_width, 1920);
        assert_eq!(config.output_height, 1080);
    }
    
    #[test]
    fn test_serial_generation() {
        let mut compositor = test_compositor();
        assert_eq!(compositor.next_serial(), 1);
        assert_eq!(compositor.next_serial(), 2);
        assert_eq!(compositor.next_serial(), 3);
    }

    #[test]
    fn test_reconcile_disconnected_client_removes_client_and_emits_event() {
        let mut compositor = test_compositor();
        let mut state = CompositorState::new(None);
        let backend_id = make_backend_client_id();
        let internal_id = 7u32;

        compositor.clients.insert(
            internal_id,
            WawonaClientData::new(
                internal_id,
                backend_id.clone(),
                compositor.disconnected_clients.clone(),
            ),
        );

        {
            let mut queue = compositor.disconnected_clients.lock().unwrap();
            queue.push(backend_id.clone());
        }

        compositor.reconcile_disconnected_clients(&mut state);

        assert!(!compositor.clients.contains_key(&internal_id));
        let events = compositor.take_events();
        assert!(events.iter().any(|evt| matches!(
            evt,
            CompositorEvent::ClientDisconnected { client_id, internal_id: ev_internal }
                if *client_id == backend_id && *ev_internal == internal_id
        )));
    }

    #[test]
    fn test_ping_clients_prunes_stale_pending_entries() {
        let mut compositor = test_compositor();
        let mut state = CompositorState::new(None);
        let backend_id = make_backend_client_id();

        state.xdg.pending_pings.insert(
            42,
            (
                backend_id,
                1,
                Instant::now() - Duration::from_secs(11),
            ),
        );

        compositor.ping_clients(&mut state);

        assert!(state.xdg.pending_pings.is_empty());
    }
}
