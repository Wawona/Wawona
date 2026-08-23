//! UniFFI API Implementation
//! 
//! This module provides the FFI boundary for the Wawona compositor.
//! All platform-specific code (macOS, iOS, Android) interacts with the
//! compositor through this stable API.
//!
//! Key design principles:
//! - Platform code never directly accesses Wayland types or compositor internals
//! - All state is managed by Rust core
//! - Platform receives high-level events and provides rendering/windowing services

use std::sync::{Arc, RwLock, Mutex};
use std::collections::HashMap;
use std::hash::{Hash, Hasher};

/// Serializes Wayland server dispatch/flush across threads (main, compositor
/// queue, in-process client workers). Concurrent ProcessEvents corrupts client
/// connections on iOS.
static WAYLAND_DISPATCH_MUTEX: Mutex<()> = Mutex::new(());

/// Poison-recovering lock acquisition.
///
/// A panic inside an event handler (isolated by `catch_unwind`) poisons any
/// lock held at the time. The data is still structurally valid. Wawona's
/// state updates are individually small. So recovering the guard and moving
/// on is strictly better than latching the whole compositor into a dead
/// "faulted" state. Every lock site at this FFI boundary must go through
/// these helpers instead of `.unwrap()`.
trait LockRecoverExt<T: ?Sized> {
    fn lock_recover(&self) -> std::sync::MutexGuard<'_, T>;
}

impl<T: ?Sized> LockRecoverExt<T> for Mutex<T> {
    fn lock_recover(&self) -> std::sync::MutexGuard<'_, T> {
        self.lock().unwrap_or_else(|poisoned| {
            crate::wlog_hot!(
                crate::util::logging::FFI,
                "Recovered poisoned mutex at FFI boundary"
            );
            poisoned.into_inner()
        })
    }
}

trait RwRecoverExt<T: ?Sized> {
    fn read_recover(&self) -> std::sync::RwLockReadGuard<'_, T>;
    fn write_recover(&self) -> std::sync::RwLockWriteGuard<'_, T>;
}

impl<T: ?Sized> RwRecoverExt<T> for RwLock<T> {
    fn read_recover(&self) -> std::sync::RwLockReadGuard<'_, T> {
        self.read().unwrap_or_else(|poisoned| {
            crate::wlog_hot!(
                crate::util::logging::FFI,
                "Recovered poisoned rwlock (read) at FFI boundary"
            );
            poisoned.into_inner()
        })
    }

    fn write_recover(&self) -> std::sync::RwLockWriteGuard<'_, T> {
        self.write().unwrap_or_else(|poisoned| {
            crate::wlog_hot!(
                crate::util::logging::FFI,
                "Recovered poisoned rwlock (write) at FFI boundary"
            );
            poisoned.into_inner()
        })
    }
}

use crate::ffi::types;

use crate::core::{
    Compositor, CompositorConfig, CompositorEvent,
    Runtime,
    CompositorState,
};
use crate::core::wayland::policy::ProtocolProfile;

use wayland_server::Resource;

// Re-export types for convenience
pub use crate::ffi::types::*;
pub use crate::ffi::errors::*;

// ============================================================================
// Main Compositor Object
// ============================================================================

/// Main compositor object exposed via FFI
/// 
/// This is the primary interface between platform code and the Rust compositor core.
/// Platform code creates an instance, starts the compositor, and processes events.
/// 
/// # Thread Safety
/// All methods are thread-safe and can be called from any thread.
#[derive(uniffi::Object)]
pub struct WawonaCore {
    /// Core compositor (manages Wayland display and clients)
    compositor: Mutex<Option<Compositor>>,
    
    /// Runtime (event loop and frame timing)
    runtime: Mutex<Runtime>,
    
    /// Compositor state (surfaces, windows, etc.)
    state: Arc<RwLock<CompositorState>>,
    
    /// Output configuration (cached for FFI access)
    output_size: RwLock<(u32, u32, f32)>,

    /// Last (w, h, scale×1000) sent via [`Self::set_output_geometry_for_window`] per window.
    per_window_output_notify: RwLock<HashMap<u64, (u32, u32, u32)>>,

    /// Next host resize transaction id (monotonic).
    next_resize_transaction_id: Mutex<u64>,

    /// Latest pending resize transaction keyed by window id.
    pending_resize_transactions: RwLock<HashMap<u64, ResizeTransaction>>,
    
    /// Force server-side decorations
    force_ssd: RwLock<bool>,

    /// Whether to advertise zwp_fullscreen_shell_v1
    advertise_fullscreen_shell: RwLock<bool>,
    /// Active protocol profile for global registration policy.
    protocol_profile: RwLock<ProtocolProfile>,
    
    /// FFI window info cache
    ffi_windows: RwLock<HashMap<u64, WindowInfo>>,
    
    /// FFI surface state cache (internal_client_id, protocol_surface_id) -> SurfaceState
    ffi_surfaces: RwLock<HashMap<u32, SurfaceState>>,
    
    /// FFI client info cache
    ffi_clients: RwLock<HashMap<u32, ClientInfo>>,
    
    /// Texture cache (buffer_id -> texture_handle)
    textures: RwLock<HashMap<u64, TextureHandle>>,
    
    /// Keyboard configuration (rate Hz, delay ms)
    keyboard_config: RwLock<(i32, i32)>,
    
    /// Pending window events queue (for FFI polling)
    pending_window_events: RwLock<Vec<WindowEvent>>,
    
    /// Pending client events queue (for FFI polling)
    pending_client_events: RwLock<Vec<ClientEvent>>,
    
    /// Pending buffers to upload (platform pulls these)
    pending_buffers: RwLock<HashMap<types::WindowId, types::WindowBuffer>>,
    
    /// Pending redraw requests
    pending_redraws: RwLock<Vec<WindowId>>,
    
    /// IPC Server (for CLI tools)
    ipc_server: Mutex<Option<crate::core::ipc::IpcServer>>,

    /// Scene fingerprint used for redraw gating.
    last_scene_fingerprint: RwLock<u64>,

}

/// Translate AppKit/GTK view-local coordinates to wl_surface-local coordinates.
/// Delegates to the shared core transform (`view_to_surface_coords`) so host
/// input injection and scene hit-testing can never disagree about insets or
/// implicit HiDPI scaling.
fn apply_geometry_offset(
    state: &CompositorState,
    window_id: WindowId,
    x: f64,
    y: f64,
) -> (f64, f64) {
    let wid = window_id.id as u32;
    let Some(window_ref) = state.get_window(wid) else {
        return (x, y);
    };
    let (surface_id, view_w, view_h) = {
        let w = window_ref.read_recover();
        (w.surface_id, w.width.max(1) as f64, w.height.max(1) as f64)
    };
    state.view_to_surface_coords(surface_id, view_w, view_h, x, y)
}

/// macOS/iOS inject pointer in the host content view. Already window-local.
fn platform_pointer_surface_local(
    state: &CompositorState,
    window_id: WindowId,
    view_x: f64,
    view_y: f64,
) -> (f64, f64) {
    apply_geometry_offset(state, window_id, view_x, view_y)
}

/// Map compositor-global pointer coordinates to surface-local coordinates
/// for wl_pointer enter/motion events.
fn pointer_surface_local_coords(
    state: &mut CompositorState,
    global_x: f64,
    global_y: f64,
    focus_sid: Option<u32>,
) -> (f64, f64) {
    if let Some((sid, lx, ly)) = state.find_surface_at(global_x, global_y) {
        if focus_sid.is_none_or(|f| f == sid) {
            return (lx, ly);
        }
    }
    (global_x, global_y)
}

fn pointer_focus_origin(state: &CompositorState, surface_id: u32) -> smithay::utils::Point<f64, smithay::utils::Logical> {
    let origin = state
        .surface_to_window
        .get(&surface_id)
        .and_then(|wid| state.get_window(*wid))
        .and_then(|window| {
            let w = window.read().ok()?;
            Some((
                w.x as f64 + w.geometry_x as f64,
                w.y as f64 + w.geometry_y as f64,
            ))
        })
        .unwrap_or((0.0, 0.0));
    origin.into()
}

fn smithay_pointer_focus(
    state: &CompositorState,
    focus_sid: Option<u32>,
) -> Option<(
    wayland_server::protocol::wl_surface::WlSurface,
    smithay::utils::Point<f64, smithay::utils::Logical>,
)> {
    focus_sid.and_then(|sid| {
        state.surfaces.get(&sid).and_then(|surface| {
            let surface = surface.read().ok()?;
            let res = surface.resource.clone()?;
            Some((res, pointer_focus_origin(state, sid)))
        })
    })
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FrameCallbackFlushPoint {
    SurfaceCommitted,
    FramePresented,
    FrameComplete,
}

const PRESTABLE_MISMATCH_TOLERANCE_PX: i32 = 1;
const WESTON_FAMILY_PRESTABLE_TOLERANCE_PX: i32 = 80;
const STABLE_MISMATCH_WARN_PX: i32 = 64;

fn is_weston_family_app_id(app_id: &str) -> bool {
    app_id == "weston"
        || app_id.starts_with("weston-")
        || app_id.contains("weston")
}

/// Nested compositor process, not weston-terminal / flower / toys.
fn is_nested_compositor_app_id(app_id: &str) -> bool {
    let id = app_id.trim();
    if id.is_empty() {
        return false;
    }
    let lower = id.to_ascii_lowercase();
    lower == "weston"
        || lower == "org.freedesktop.weston"
        || lower == "niri"
        || lower.starts_with("niri.")
}

fn nested_compositor_output_scale(app_id: &str, global_scale: f32) -> f32 {
    if is_nested_compositor_app_id(app_id) {
        1.0
    } else if global_scale < 1.0 {
        1.0
    } else {
        global_scale
    }
}

fn buffer_size_mismatch_px(
    buf_w: u32,
    buf_h: u32,
    expected_w: u32,
    expected_h: u32,
    buffer_scale: u32,
) -> (i32, i32) {
    let bw = buf_w as i32;
    let bh = buf_h as i32;
    let ew = expected_w as i32;
    let eh = expected_h as i32;
    let tolerance = PRESTABLE_MISMATCH_TOLERANCE_PX;

    let matches = |bw: i32, bh: i32, ew: i32, eh: i32| {
        (bw - ew).abs() <= tolerance && (bh - eh).abs() <= tolerance
    };

    if matches(bw, bh, ew, eh) {
        return (0, 0);
    }

    let s = buffer_scale.max(1) as i32;
    if matches(bw, bh, ew * s, eh * s) {
        return (0, 0);
    }

    (
        (bw - ew).abs().min((bw - ew * s).abs()),
        (bh - eh).abs().min((bh - eh * s).abs()),
    )
}

fn should_flush_frame_callbacks(point: FrameCallbackFlushPoint) -> bool {
    matches!(
        point,
        FrameCallbackFlushPoint::SurfaceCommitted | FrameCallbackFlushPoint::FramePresented
    )
}

impl WawonaCore {
    fn begin_resize_transaction(
        &self,
        window_id: WindowId,
        configure_serial: u32,
        cause: WindowSizeCause,
        requested_size: Size,
        size_kind: GeometrySizeKind,
    ) -> ResizeTransaction {
        let mut next = self.next_resize_transaction_id.lock_recover();
        let txn = ResizeTransaction {
            id: *next,
            window_id,
            configure_serial,
            cause,
            requested_size,
            size_kind,
        };
        *next = next.wrapping_add(1);
        let replaced = self
            .pending_resize_transactions
            .write_recover()
            .insert(window_id.id, txn.clone());
        if let Some(prev) = replaced {
            crate::wtrace!(
                crate::util::logging::FFI,
                "Resize txn superseded: window={} prev_id={} prev_serial={} prev={}x{} prev_cause={:?} -> id={} serial={} req={}x{} cause={:?}",
                window_id.id,
                prev.id,
                prev.configure_serial,
                prev.requested_size.width,
                prev.requested_size.height,
                prev.cause,
                txn.id,
                txn.configure_serial,
                txn.requested_size.width,
                txn.requested_size.height,
                txn.cause
            );
        } else {
            crate::wtrace!(
                crate::util::logging::FFI,
                "Resize txn begin: id={} window={} serial={} req={}x{} cause={:?} size_kind={:?}",
                txn.id,
                window_id.id,
                txn.configure_serial,
                txn.requested_size.width,
                txn.requested_size.height,
                txn.cause,
                txn.size_kind
            );
        }
        txn
    }

    fn take_resize_transaction_for_size(
        &self,
        window_id: WindowId,
        width: u32,
        height: u32,
    ) -> Option<ResizeTransaction> {
        let mut pending = self.pending_resize_transactions.write_recover();
        let txn = pending.get(&window_id.id)?.clone();
        if txn.requested_size.width == width && txn.requested_size.height == height {
            let removed = pending.remove(&window_id.id);
            if let Some(ref matched) = removed {
                crate::wtrace!(
                    crate::util::logging::FFI,
                    "Resize txn matched: id={} window={} serial={} applied={}x{} cause={:?}",
                    matched.id,
                    window_id.id,
                    matched.configure_serial,
                    width,
                    height,
                    matched.cause
                );
            }
            return removed;
        }
        crate::wtrace!(
            crate::util::logging::FFI,
            "Resize txn pending mismatch: id={} window={} serial={} requested={}x{} observed={}x{} cause={:?}",
            txn.id,
            window_id.id,
            txn.configure_serial,
            txn.requested_size.width,
            txn.requested_size.height,
            width,
            height,
            txn.cause
        );
        None
    }
}

impl WawonaCore {
    #[cfg(not(any(target_os = "ios", target_os = "visionos", target_os = "watchos")))]
    pub fn pop_pending_gamma_apply(&self) -> Option<crate::core::state::GammaRampApply> {
        if !self.is_running() {
            return None;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::wlr::gamma_control::pop_pending_gamma_apply(&mut state)
    }

    #[cfg(any(target_os = "ios", target_os = "visionos", target_os = "watchos"))]
    pub fn pop_pending_gamma_apply(&self) -> Option<crate::core::state::GammaRampApply> {
        None
    }
}

#[uniffi::export]
impl WawonaCore {
    // =========================================================================
    // Lifecycle
    // =========================================================================
    
    /// Create a new compositor instance
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        crate::wlog!(crate::util::logging::FFI, "Creating Wawona compositor (FFI)");
        
        Arc::new(Self {
            compositor: Mutex::new(None),
            runtime: Mutex::new(Runtime::new()),
            state: Arc::new(RwLock::new(CompositorState::new(None))), // Default for now, updated in start()
            output_size: RwLock::new((1920, 1080, 1.0)),
            per_window_output_notify: RwLock::new(HashMap::new()),
            next_resize_transaction_id: Mutex::new(1),
            pending_resize_transactions: RwLock::new(HashMap::new()),
            force_ssd: RwLock::new(false),
            // Nested wlroots compositors (Weston, Sway, …) bind zwp_fullscreen_shell_v1.
            advertise_fullscreen_shell: RwLock::new(cfg!(any(
                target_os = "macos",
                target_os = "linux"
            ))),
            protocol_profile: RwLock::new(ProtocolProfile::default()),
            ffi_windows: RwLock::new(HashMap::new()),
            ffi_surfaces: RwLock::new(HashMap::new()),
            ffi_clients: RwLock::new(HashMap::new()),
            textures: RwLock::new(HashMap::new()),
            keyboard_config: RwLock::new((33, 500)),
            pending_window_events: RwLock::new(Vec::new()),
            pending_client_events: RwLock::new(Vec::new()),
            pending_buffers: RwLock::new(HashMap::new()),
            pending_redraws: RwLock::new(Vec::new()),
            ipc_server: Mutex::new(None),
            last_scene_fingerprint: RwLock::new(0),
        })
    }
    
    /// Start the compositor
    /// 
    /// # Arguments
    /// * `socket_name` - Optional Wayland socket name (defaults to "wayland-0")
    pub fn start(&self, socket_name: Option<String>) -> Result<()> {
        let mut compositor_guard = self.compositor.lock_recover();
        
        if compositor_guard.is_some() {
            return Err(CompositorError::AlreadyStarted);
        }
        
        let socket = socket_name.unwrap_or_else(|| "wayland-0".to_string());
        crate::wlog!(crate::util::logging::FFI, "Starting compositor on socket: {}", socket);
        
        // Create compositor configuration
        let (width, height, scale) = *self.output_size.read_recover();
        let (repeat_rate, repeat_delay) = *self.keyboard_config.read_recover();
        
        let config = CompositorConfig {
            socket_name: socket.clone(),
            force_ssd: *self.force_ssd.read_recover(),
            output_width: width,
            output_height: height,
            output_scale: scale,
            keyboard_repeat_rate: repeat_rate,
            keyboard_repeat_delay: repeat_delay,
            advertise_fullscreen_shell: *self.advertise_fullscreen_shell.read_recover(),
            protocol_profile: *self.protocol_profile.read_recover(),
        };
        
        // Create and start the compositor
        let mut compositor = Compositor::new(config.clone())
            .map_err(|e| CompositorError::initialization_failed(e.to_string()))?;
        
        // Synchronize output configuration into state
        let mut state = self.state.write_recover();
        state.update_primary_output(width, height, scale);
        state.advertise_fullscreen_shell = config.advertise_fullscreen_shell;
        state.protocol_profile = config.protocol_profile;
        state.decoration_policy = if config.force_ssd {
            crate::core::state::DecorationPolicy::ForceServer
        } else {
            crate::core::state::DecorationPolicy::default()
        };
        
        compositor.start(&mut state)
            .map_err(|e| CompositorError::initialization_failed(e.to_string()))?;
        
        drop(state);
        
        *compositor_guard = Some(compositor);
        
        // Start IPC server
        let ipc = crate::core::ipc::IpcServer::new(self.state.clone());
        *self.ipc_server.lock_recover() = Some(ipc);
        
        crate::wlog!(crate::util::logging::FFI, "Compositor started successfully");
        Ok(())
    }
    
    /// Set whether server-side decorations (SSD) should be forced
    pub fn set_force_ssd(&self, enabled: bool) {
        if *self.force_ssd.read_recover() == enabled {
            return;
        }

        let mut state = self.state.write_recover();

        crate::wlog!(crate::util::logging::FFI, "FFI: set_force_ssd({})", enabled);

        // 1. Update the GLOBAL default policy. Force SSD per-machine (#120):
        //    this is only the default for clients (machines) with no explicit
        //    per-client override; toggling the global Settings switch must NOT
        //    rewrite live machines that carry their own Force SSD setting.
        state.decoration_policy = if enabled {
            crate::core::state::DecorationPolicy::ForceServer
        } else {
            crate::core::state::DecorationPolicy::PreferClient
        };

        // 2. Update cached state
        *self.force_ssd.write_recover() = enabled;

        // Window ids belonging to clients that carry a per-machine override -
        // these must be left untouched by the global toggle below.
        let overridden_windows: std::collections::HashSet<u32> = state
            .xdg
            .toplevels
            .iter()
            .filter(|((client_id, _), _)| state.client_decoration_policy.contains_key(client_id))
            .map(|(_, tl)| tl.window_id)
            .collect();
        
        // 3. Notify existing decorations if protocol is active
        use wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode as XdgMode;
        use crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration::Mode as KdeMode;
        
        let target_xdg_mode = if enabled {
            XdgMode::ServerSide
        } else {
            XdgMode::ClientSide
        };

        let target_kde_mode = if enabled {
            KdeMode::Server
        } else {
            KdeMode::Client
        };

        let toplevel_updates: Vec<(u32, smithay::wayland::shell::xdg::ToplevelSurface)> = state
            .xdg
            .toplevels
            .values()
            .filter(|tl| !overridden_windows.contains(&tl.window_id))
            .filter_map(|tl| tl.toplevel_surface.clone().map(|s| (tl.window_id, s)))
            .collect();

        let kde_decorations: Vec<_> = state
            .xdg
            .decoration
            .decorations
            .values()
            .filter(|d| d.kde_resource.is_some() && !overridden_windows.contains(&d.window_id))
            .cloned()
            .collect();

        crate::wlog!(
            crate::util::logging::FFI,
            "Updating {} toplevel decorations ({} KDE)",
            toplevel_updates.len(),
            kde_decorations.len()
        );

        for (window_id, toplevel) in toplevel_updates {
            let xdg_mode = if enabled {
                target_xdg_mode
            } else {
                crate::core::wayland::xdg::decoration::preferred_xdg_decoration_mode(&state, window_id)
            };
            let new_mode =
                crate::core::wayland::xdg::decoration::decoration_mode_from_xdg(xdg_mode);
            toplevel.with_pending_state(|pending| {
                pending.decoration_mode = Some(xdg_mode);
            });
            let _ = toplevel.send_pending_configure();

            if let Some(window) = state.get_window(window_id) {
                let mut window = window.write_recover();
                if window.decoration_mode != new_mode {
                    window.decoration_mode = new_mode;
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::DecorationModeChanged {
                            window_id,
                            mode: new_mode,
                        },
                    );
                }
            }
        }

        for decoration in kde_decorations {
            let window_id = decoration.window_id;
            if let Some(res) = &decoration.kde_resource {
                res.mode(target_kde_mode);
            }
            let new_mode = if enabled {
                crate::core::window::DecorationMode::ServerSide
            } else {
                crate::core::window::DecorationMode::ClientSide
            };
            if let Some(window) = state.get_window(window_id) {
                let mut window = window.write_recover();
                if window.decoration_mode != new_mode {
                    window.decoration_mode = new_mode;
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::DecorationModeChanged {
                            window_id,
                            mode: new_mode,
                        },
                    );
                }
            }
        }
    }

    /// Stage the decoration policy for the **next** machine's Wayland client.
    ///
    /// Force SSD per-machine (#120): the host calls this immediately before
    /// launching a machine's client, passing that machine's resolved
    /// `forceSSD`. The first toplevel from the connecting client claims the
    /// staged policy and pins it, so concurrent machines (e.g. one CSD, one
    /// SSD) never stomp each other. Unlike [`set_force_ssd`], this does **not**
    /// touch the global default or any already-connected client.
    pub fn set_force_ssd_for_client_launch(&self, enabled: bool) {
        let mut state = self.state.write_recover();
        let policy = if enabled {
            crate::core::state::DecorationPolicy::ForceServer
        } else {
            crate::core::state::DecorationPolicy::PreferClient
        };
        crate::wlog!(
            crate::util::logging::FFI,
            "FFI: set_force_ssd_for_client_launch({}) -> pending {:?}",
            enabled,
            policy
        );
        state.pending_client_decoration_policy = Some(policy);
    }

    /// Mark whether `window_id` is hosted in its own independent OS
    /// window/scene (macOS NSWindow-per-toplevel, or one `UIWindowScene` per
    /// Wayland client on iPadOS/visionOS. See `ipad-scene-parity` /
    /// `vision-shell-parity`, #120).
    ///
    /// Independent windows are excluded from the shared-output resize sweep
    /// in `CompositorState::set_output_size`: without this, resizing the
    /// *primary* host window (Machines UI) would snap every fill-primary
    /// (maximized) client. Including ones now living in their own,
    /// differently-sized scene. To the primary window's size, producing
    /// visible resize glitches on the unrelated client window.
    pub fn set_window_host_scene_independent(&self, window_id: WindowId, independent: bool) {
        let wid = window_id.id as u32;
        crate::wlog!(
            crate::util::logging::FFI,
            "FFI: set_window_host_scene_independent(window={}, independent={})",
            wid,
            independent
        );
        self.state
            .write_recover()
            .set_window_host_scene_independent(wid, independent);
    }

    /// Set whether to advertise zwp_fullscreen_shell_v1
    pub fn set_advertise_fullscreen_shell(&self, enabled: bool) {
        crate::wlog!(crate::util::logging::FFI, "FFI: set_advertise_fullscreen_shell({})", enabled);
        *self.advertise_fullscreen_shell.write_recover() = enabled;
        
        let mut state = self.state.write_recover();
        state.advertise_fullscreen_shell = enabled;
    }

    /// Set protocol profile used for subsequent global registration.
    pub fn set_protocol_profile(&self, profile: String) {
        if let Some(parsed) = ProtocolProfile::from_str(profile.as_str()) {
            crate::wlog!(
                crate::util::logging::FFI,
                "FFI: set_protocol_profile({})",
                parsed.as_str()
            );
            *self.protocol_profile.write_recover() = parsed;
            self.state.write_recover().protocol_profile = parsed;
        } else {
            crate::wlog!(
                crate::util::logging::FFI,
                "FFI: ignored invalid protocol profile '{}'",
                profile
            );
        }
    }
    
    /// Stop the compositor
    pub fn stop(&self) -> Result<()> {
        let mut compositor_guard = self.compositor.lock_recover();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.stop()
            .map_err(|e| CompositorError::platform_error(e.to_string()))?;
        
        *compositor_guard = None;
        
        // Clear caches
        self.ffi_windows.write_recover().clear();
        self.ffi_surfaces.write_recover().clear();
        self.ffi_clients.write_recover().clear();
        self.textures.write_recover().clear();
        self.pending_window_events.write_recover().clear();
        self.pending_client_events.write_recover().clear();
        self.pending_buffers.write_recover().clear();
        self.pending_redraws.write_recover().clear();
        *self.last_scene_fingerprint.write_recover() = 0;
        
        // Stop IPC server
        *self.ipc_server.lock_recover() = None;
        
        crate::wlog!(crate::util::logging::FFI, "Compositor stopped");
        Ok(())
    }
    
    /// Check if compositor is running
    pub fn is_running(&self) -> bool {
        self.compositor
            .lock_recover()
            .as_ref()
            .map(|c| c.is_running())
            .unwrap_or(false)
    }
    
    /// Get the Wayland socket path
    pub fn get_socket_path(&self) -> String {
        self.compositor
            .lock_recover()
            .as_ref()
            .map(|c| c.socket_path().to_string())
            .unwrap_or_default()
    }
    
    /// Get the Wayland socket name
    pub fn get_socket_name(&self) -> String {
        self.compositor
            .lock_recover()
            .as_ref()
            .map(|c| c.socket_name().to_string())
            .unwrap_or_default()
    }
    
    // =========================================================================
    // Socket Management
    // =========================================================================
    
    /// Add an additional Unix domain socket for connections
    pub fn add_unix_socket(&self, path: String) -> Result<()> {
        let mut compositor_guard = self.compositor.lock_recover();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.add_unix_socket(&path)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Added Unix socket: {}", path);
        Ok(())
    }
    
    /// Add a vsock listener on the specified port
    pub fn add_vsock_listener(&self, port: u32) -> Result<()> {
        let mut compositor_guard = self.compositor.lock_recover();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.add_vsock_listener(port)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Added vsock listener on port: {}", port);
        Ok(())
    }
    
    /// Remove a socket by its path or identifier
    pub fn remove_socket(&self, identifier: String) -> Result<()> {
        let mut compositor_guard = self.compositor.lock_recover();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.remove_socket(&identifier)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Removed socket: {}", identifier);
        Ok(())
    }
    
    pub fn get_socket_paths(&self) -> Vec<String> {
        self.compositor.lock_recover()
            .as_ref()
            .map(|c| c.get_socket_paths())
            .unwrap_or_default()
    }
    

    
    // =========================================================================
    // Input Injection
    // =========================================================================

    /// Inject an input event into the compositor
    pub fn inject_input_event(&self, event: InputEvent) {
        let core_event = match event {
            InputEvent::PointerMotion { x, y, time_ms } => {
                crate::core::input::InputEvent::PointerMotion { x, y, time_ms }
            }
            InputEvent::PointerButton { button, state, time_ms } => {
                let core_state = match state {
                    ButtonState::Pressed => crate::core::input::KeyState::Pressed,
                    ButtonState::Released => crate::core::input::KeyState::Released,
                };
                crate::core::input::InputEvent::PointerButton { button, state: core_state, time_ms }
            }
            InputEvent::PointerAxis { horizontal, vertical, time_ms } => {
                crate::core::input::InputEvent::PointerAxis { horizontal, vertical, time_ms }
            }
            InputEvent::KeyboardKey { keycode, state, time_ms } => {
                let core_state = match state {
                    KeyState::Pressed => crate::core::input::KeyState::Pressed,
                    KeyState::Released => crate::core::input::KeyState::Released,
                };
                crate::core::input::InputEvent::KeyboardKey { keycode, state: core_state, time_ms }
            }
            InputEvent::KeyboardModifiers { depressed, latched, locked, group } => {
                crate::core::input::InputEvent::KeyboardModifiers { depressed, latched, locked, group }
            }
            InputEvent::TouchDown { id, x, y, time_ms } => {
                crate::core::input::InputEvent::TouchDown { id, x, y, time_ms }
            }
            InputEvent::TouchUp { id, time_ms } => {
                crate::core::input::InputEvent::TouchUp { id, time_ms }
            }
            InputEvent::TouchMotion { id, x, y, time_ms } => {
                crate::core::input::InputEvent::TouchMotion { id, x, y, time_ms }
            }
            InputEvent::TouchCancel => {
                crate::core::input::InputEvent::TouchCancel
            }
            InputEvent::TouchFrame => {
                crate::core::input::InputEvent::TouchFrame
            }
        };

        let mut state = self.state.write_recover();
        state.process_input_event(core_event);
    }
    
    // =========================================================================
    // Event Processing
    // =========================================================================
    
    /// Process pending Wayland events
    /// Returns true if events were processed
    pub fn process_events(&self) -> bool {
        let _dispatch_guard = WAYLAND_DISPATCH_MUTEX.lock_recover();

        let mut compositor_guard = self.compositor.lock_recover();
        let compositor = match compositor_guard.as_mut() {
            Some(c) => c,
            None => {
                crate::wlog_hot!(
                    crate::util::logging::FFI,
                    "ProcessEvents skipped: compositor not started"
                );
                return false;
            }
        };

        let mut runtime = self.runtime.lock_recover();

        // Collect events while holding the lock
        let events = {
            let mut state = self.state.write_recover();

            // Process events
            match runtime.poll(compositor, &mut state) {
                Ok(events) => {
                    // Flush pending feedback from fullscreen shell to avert wayland-backend hang
                    state.ext.fullscreen_shell.flush_pending_mode_feedbacks();
                    events
                }
                Err(e) => {
                    crate::wlog!(
                        crate::util::logging::FFI,
                        "ProcessEvents poll error: {}",
                        e
                    );
                    return false;
                }
            }
        }; // state lock released here

        // Flush client queues so deferred events (e.g. mode_successful from
        // fullscreen shell) reach the wire immediately rather than waiting for
        // the next poll cycle.  Without this, nested compositors like weston
        // time out waiting for the mode feedback and exit.
        let _ = compositor.flush();

        // Drop the other locks too before handling events
        drop(runtime);
        drop(compositor_guard);

        let event_count = events.len();
        for event in events {
            let handled = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.handle_compositor_event(event);
            }));
            if handled.is_err() {
                crate::wlog!(
                    crate::util::logging::FFI,
                    "ProcessEvents: compositor event handler panicked; skipping event"
                );
            }
        }

        self.flush_clients_locked();

        if event_count > 0 {
            crate::wlog_hot!(
                crate::util::logging::FFI,
                "ProcessEvents: handled {} compositor event(s)",
                event_count
            );
        }

        true
    }
    
    /// Dispatch pending events with timeout (milliseconds)
    /// Returns true if events were processed
    pub fn dispatch_events(&self, timeout_ms: u32) -> bool {
        let _dispatch_guard = WAYLAND_DISPATCH_MUTEX.lock_recover();

        let mut compositor_guard = self.compositor.lock_recover();
        let compositor = match compositor_guard.as_mut() {
            Some(c) => c,
            None => return false,
        };
        
        let mut runtime = self.runtime.lock_recover();
        let timeout = std::time::Duration::from_millis(timeout_ms as u64);
        
        // Collect events while holding the lock
        let events = {
            let mut state = self.state.write_recover();
            
            match runtime.dispatch(compositor, &mut state, timeout) {
                Ok(events) => {
                    state.ext.fullscreen_shell.flush_pending_mode_feedbacks();
                    events
                }
                Err(e) => {
                    crate::wlog!(crate::util::logging::FFI, "Event dispatch error: {}", e);
                    return false;
                }
            }
        }; // state lock released here
        
        // Flush so deferred events reach the wire immediately
        let _ = compositor.flush();

        // Drop other locks before handling events
        drop(runtime);
        drop(compositor_guard);
        
        // Handle events without holding any locks; a panicking handler must
        // not take down the dispatch loop.
        for event in events {
            let handled = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                self.handle_compositor_event(event);
            }));
            if handled.is_err() {
                crate::wlog!(
                    crate::util::logging::FFI,
                    "DispatchEvents: compositor event handler panicked; skipping event"
                );
            }
        }

        // Flush protocol events generated by event handlers (frame_done, etc.)
        self.flush_clients_locked();

        true
    }
    
    /// Flush client event queues (must not be called while holding WAYLAND_DISPATCH_MUTEX
    /// unless via flush_clients_locked).
    fn flush_clients_locked(&self) {
        let mut compositor_guard = self.compositor.lock_recover();
        if let Some(compositor) = compositor_guard.as_mut() {
            let _ = compositor.flush();
        }
    }

    /// Flush client event queues
    pub fn flush_clients(&self) {
        let _dispatch_guard = WAYLAND_DISPATCH_MUTEX.lock_recover();
        self.flush_clients_locked();
    }

    /// Report that a frame was presented
    /// 
    /// This should be called by the platform when the frame is actually displayed.
    /// It updates the frame clock and triggers presentation feedback events.
    pub fn frame_presented(&self, refresh_mhz: u32) {
        // 1. Update Frame Clock
        {
            let mut runtime = self.runtime.lock_recover();
            runtime.report_presentation(std::time::Instant::now(), refresh_mhz);
        }
        
        // 2. Fire presentation feedback events
        {
            let mut state = self.state.write_recover();
            state.report_presentation_feedback(std::time::Instant::now(), refresh_mhz);
        }
    }
}

// Internal methods (not exported via UniFFI)
impl WawonaCore {
    /// Remove FFI-side caches owned by a disconnected client.
    fn cleanup_client_ffi_state(&self, client_id: &wayland_server::backend::ClientId, internal_id: u32) {
        let disconnected_surface_ids: Vec<u32> = {
            let state = self.state.read_recover();
            state
                .surfaces
                .iter()
                .filter_map(|(sid, surf)| {
                    surf.read()
                        .ok()
                        .and_then(|s| (s.client_id.as_ref() == Some(client_id)).then_some(*sid))
                })
                .collect()
        };

        if disconnected_surface_ids.is_empty() {
            return;
        }

        {
            let mut ffi_surfaces = self.ffi_surfaces.write_recover();
            for sid in &disconnected_surface_ids {
                ffi_surfaces.remove(sid);
            }
        }

        let disconnected_surfaces: std::collections::HashSet<u32> =
            disconnected_surface_ids.iter().copied().collect();
        let mut disconnected_windows = std::collections::HashSet::new();
        {
            let mut pending = self.pending_buffers.write_recover();
            pending.retain(|window_id, wb| {
                let keep = !disconnected_surfaces.contains(&wb.surface_id.id);
                if !keep {
                    disconnected_windows.insert(*window_id);
                }
                keep
            });
        }
        if !disconnected_windows.is_empty() {
            let mut redraws = self.pending_redraws.write_recover();
            redraws.retain(|wid| !disconnected_windows.contains(wid));
        }

        crate::wlog!(
            crate::util::logging::FFI,
            "ClientDisconnected cleanup: internal_id={} surfaces_removed={}",
            internal_id,
            disconnected_surface_ids.len()
        );
    }

    /// Get next serial number (for input event correlation)
    fn next_serial(&self) -> u32 {
        let mut guard = self.compositor.lock_recover();
        if let Some(compositor) = guard.as_mut() {
            return compositor.next_serial();
        }
        0
    }

    fn internal_client_id(&self, client_id: &wayland_server::backend::ClientId) -> Option<u32> {
        self.compositor
            .lock_recover()
            .as_ref()
            .map(|c| c.client_id_to_internal(client_id.clone()))
    }
    
    /// Handle a compositor event (convert to FFI event)
    fn handle_compositor_event(&self, event: CompositorEvent) {
        match event {
            CompositorEvent::ClientConnected { client_id, pid } => {
                let Some(internal_id) = self.internal_client_id(&client_id) else {
                    return;
                };
                let client_info = ClientInfo {
                    id: ClientId { id: internal_id },
                    pid: pid.unwrap_or(0),
                    name: None,
                    surface_count: 0,
                    window_count: 0,
                };
                self.ffi_clients.write_recover().insert(internal_id, client_info);
                self.pending_client_events.write_recover().push(
                    ClientEvent::Connected { 
                        client_id: ClientId { id: internal_id }, 
                        pid: pid.unwrap_or(0) 
                    }
                );
            }
            CompositorEvent::ClientDisconnected { client_id, internal_id } => {
                self.cleanup_client_ffi_state(&client_id, internal_id);
                self.ffi_clients.write_recover().remove(&internal_id);
                self.pending_client_events.write_recover().push(
                    ClientEvent::Disconnected { 
                        client_id: ClientId { id: internal_id } 
                    }
                );
            }
            CompositorEvent::WindowMinimized { window_id, minimized } => {
                if minimized {
                    self.pending_window_events.write_recover().push(
                        WindowEvent::MinimizeRequested { 
                            window_id: WindowId { id: window_id as u64 } 
                        }
                    );
                }
            }
            CompositorEvent::WindowMaximized { window_id, maximized } => {
                if maximized {
                    self.pending_window_events.write_recover().push(
                        WindowEvent::MaximizeRequested { 
                            window_id: WindowId { id: window_id as u64 } 
                        }
                    );
                } else {
                    self.pending_window_events.write_recover().push(
                        WindowEvent::UnmaximizeRequested { 
                            window_id: WindowId { id: window_id as u64 } 
                        }
                    );
                }
            }
            CompositorEvent::WindowFullscreen { window_id, fullscreen } => {
                if fullscreen {
                    self.pending_window_events.write_recover().push(
                        WindowEvent::FullscreenRequested {
                            window_id: WindowId { id: window_id as u64 },
                        },
                    );
                } else {
                    self.pending_window_events.write_recover().push(
                        WindowEvent::UnfullscreenRequested {
                            window_id: WindowId { id: window_id as u64 },
                        },
                    );
                }
            }
            CompositorEvent::WindowHostLocked { window_id, width, height } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::HostLocked {
                        window_id: WindowId { id: window_id as u64 },
                        width,
                        height,
                    }
                );
            }
            CompositorEvent::WindowCreated {
                client_id,
                window_id,
                surface_id,
                title,
                width,
                height,
                decoration_mode,
                fullscreen_shell,
                host_locked,
            } => {
                let internal_client_id = self
                    .internal_client_id(&client_id)
                    .unwrap_or(0);
                if internal_client_id == 0 {
                    crate::wlog!(
                        crate::util::logging::FFI,
                        "WindowCreated: client not in map yet (window_id={}), using internal_id=0",
                        window_id
                    );
                }
                let ffi_decoration_mode = match decoration_mode {
                    crate::core::window::DecorationMode::ClientSide => DecorationMode::ClientSide,
                    crate::core::window::DecorationMode::ServerSide => DecorationMode::ServerSide,
                };
                let window_info = WindowInfo {
                    id: WindowId { id: window_id as u64 },
                    surface_id: SurfaceId { id: surface_id },
                    title: title.clone(),
                    app_id: String::new(),
                    width,
                    height,
                    decoration_mode: ffi_decoration_mode,
                    state: crate::ffi::types::WindowState::Normal,
                    activated: false,
                    resizing: false,
                };
                self.ffi_windows.write_recover().insert(window_id as u64, window_info.clone());

                let config = WindowConfig {
                    title,
                    app_id: String::new(),
                    width,
                    height,
                    min_width: None,
                    min_height: None,
                    max_width: None,
                    max_height: None,
                    decoration_mode: ffi_decoration_mode,
                    fullscreen_shell,
                    host_locked,
                    owner_client_internal_id: internal_client_id as u64,
                    state: crate::ffi::types::WindowState::Normal,
                    parent: None,
                };
                self.pending_window_events.write_recover().push(
                    WindowEvent::Created {
                        window_id: WindowId { id: window_id as u64 },
                        config,
                    }
                );
                crate::wlog!(
                    crate::util::logging::FFI,
                    "WindowCreated queued: window_id={} {}x{} host_locked={}",
                    window_id,
                    width,
                    height,
                    host_locked
                );
            }
            CompositorEvent::PopupCreated { client_id, window_id, surface_id, parent_id, x, y, width, height } => {
                let Some(internal_client_id) = self.internal_client_id(&client_id) else {
                    return;
                };
                let _config = WindowConfig {
                    title: String::new(),
                    app_id: String::new(),
                    width,
                    height,
                    min_width: None,
                    min_height: None,
                    max_width: None,
                    max_height: None,
                    decoration_mode: DecorationMode::ClientSide,
                    fullscreen_shell: false,
                    host_locked: false,
                    owner_client_internal_id: internal_client_id as u64,
                    state: crate::ffi::types::WindowState::Normal,
                    parent: if parent_id > 0 { Some(WindowId::new(parent_id as u64)) } else { None },
                };
                
                self.pending_window_events.write_recover().push(
                    WindowEvent::PopupCreated { 
                        window_id: WindowId { id: window_id as u64 }, 
                        parent_id: WindowId { id: parent_id as u64 },
                        x, y,
                        width,
                        height
                    }
                );
            }
            CompositorEvent::PopupRepositioned { window_id, x, y, width, height } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::PopupRepositioned { 
                        window_id: WindowId { id: window_id as u64 }, 
                        x, y,
                        width,
                        height
                    }
                );
            }
            CompositorEvent::WindowDestroyed { window_id } => {
                if let Some(txn) = self
                    .pending_resize_transactions
                    .write_recover()
                    .remove(&(window_id as u64))
                {
                    crate::wtrace!(
                        crate::util::logging::FFI,
                        "Resize txn dropped on destroy: id={} window={} serial={} req={}x{} cause={:?}",
                        txn.id,
                        txn.window_id.id,
                        txn.configure_serial,
                        txn.requested_size.width,
                        txn.requested_size.height,
                        txn.cause
                    );
                }
                self.ffi_windows.write_recover().remove(&(window_id as u64));
                self.pending_window_events.write_recover().push(
                    WindowEvent::Destroyed { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::WindowTitleChanged { window_id, title } => {
                if let Some(info) = self.ffi_windows.write_recover().get_mut(&(window_id as u64)) {
                    info.title = title.clone();
                }
                self.pending_window_events.write_recover().push(
                    WindowEvent::TitleChanged { 
                        window_id: WindowId { id: window_id as u64 }, 
                        title 
                    }
                );
            }
            CompositorEvent::WindowSizeChanged { window_id, width, height } => {
                if let Some(info) = self.ffi_windows.write_recover().get_mut(&(window_id as u64)) {
                    info.width = width;
                    info.height = height;
                }
                let window_id_ffi = WindowId { id: window_id as u64 };
                // #111: do NOT update per-window wl_output here on txn settle.
                // Settling mid-drag (whenever a nested compositor catches up)
                // applied intermittent mode changes out of step with the latest
                // host size and flashed niri/weston between before/after
                // framebuffers. Output geometry is pushed in lockstep with
                // xdg_toplevel.configure from inject_window_resize instead.
                let txn = self.take_resize_transaction_for_size(window_id_ffi, width, height);
                let (cause, size_kind, configure_serial, transaction_id) = if let Some(txn) = txn {
                    (txn.cause, txn.size_kind, txn.configure_serial, txn.id)
                } else {
                    crate::wtrace!(
                        crate::util::logging::FFI,
                        "WindowSizeChanged without matching txn: window={} size={}x{} (classifying as ClientCommit)",
                        window_id,
                        width,
                        height
                    );
                    (WindowSizeCause::ClientCommit, GeometrySizeKind::Content, 0, 0)
                };
                crate::wtrace!(
                    crate::util::logging::FFI,
                    "WindowSizeChanged dispatch: window={} size={}x{} cause={:?} kind={:?} serial={} txn={}",
                    window_id,
                    width,
                    height,
                    cause,
                    size_kind,
                    configure_serial,
                    transaction_id
                );
                self.pending_window_events.write_recover().push(
                    WindowEvent::SizeChanged {
                        window_id: window_id_ffi,
                        width,
                        height,
                        cause,
                        size_kind,
                        configure_serial,
                        transaction_id,
                    }
                );
            }
            CompositorEvent::DecorationModeChanged { window_id, mode } => {
                let ffi_mode = match mode {
                    crate::core::window::DecorationMode::ClientSide => DecorationMode::ClientSide,
                    crate::core::window::DecorationMode::ServerSide => DecorationMode::ServerSide,
                };
                if let Some(info) = self.ffi_windows.write_recover().get_mut(&(window_id as u64)) {
                    info.decoration_mode = ffi_mode;
                }
                self.pending_window_events.write_recover().push(
                    WindowEvent::DecorationModeChanged {
                        window_id: WindowId { id: window_id as u64 },
                        mode: ffi_mode,
                    }
                );
            }
            CompositorEvent::WindowActivationRequested { window_id } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::Activated { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::WindowCloseRequested { window_id } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::CloseRequested { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::RedrawNeeded { window_id } => {
                self.pending_redraws.write_recover().push(
                    WindowId { id: window_id as u64 }
                );
            }
            CompositorEvent::SurfaceCommitted { client_id, surface_id, buffer_id } => {
                let Some(internal_client_id) = self.internal_client_id(&client_id) else {
                    return;
                };
                // Track commits per surface
                thread_local! {
                    static SURFACE_COMMITS: std::cell::RefCell<std::collections::HashMap<(u32, u32), u32>> = Default::default();
                    static SURFACE_NO_BUFFER_COMMITS: std::cell::RefCell<std::collections::HashMap<(u32, u32), u32>> = Default::default();
                }
                let commit_count = SURFACE_COMMITS.with(|commits| {
                    let mut map = commits.borrow_mut();
                    let count = map.entry((internal_client_id, surface_id)).or_insert(0);
                    *count += 1;
                    *count
                });
                
                crate::wtrace!(crate::util::logging::FFI, "SurfaceCommitted client={}, surface={}, buffer_id={:?} (commit #{})", 
                    internal_client_id, surface_id, buffer_id, commit_count);
                
                let buffer_id = if let Some(bid) = buffer_id {
                    bid as u32
                } else {
                    let (flushed_count, no_buffer_count) = {
                        let mut state = self.state.write_recover();
                        let callback_count = state
                            .frame_callbacks
                            .get(&surface_id)
                            .map(|cbs| cbs.len())
                            .unwrap_or(0);
                        if callback_count > 0 {
                            // No buffer attached => no presentation callback will fire.
                            // Flush now so clients that use state-only commits don't stall.
                            state.flush_frame_callbacks(
                                surface_id,
                                Some(crate::core::state::CompositorState::get_timestamp_ms()),
                            );
                        }
                        let no_buffer_count = SURFACE_NO_BUFFER_COMMITS.with(|counts| {
                            let mut map = counts.borrow_mut();
                            let count = map.entry((internal_client_id, surface_id)).or_insert(0);
                            *count += 1;
                            *count
                        });
                        (callback_count, no_buffer_count)
                    };
                    crate::wlog_hot!(
                        crate::util::logging::FFI,
                        "SurfaceCommitted: surf={} buf=<none> frame_cbs_flushed={} no_buffer_commits={}",
                        surface_id,
                        flushed_count,
                        no_buffer_count
                    );
                    return;
                };
                
                // -------------------------------------------------------
                // Phase 1: Gather metadata and copy raw pixel bytes under
                // the state lock.  The memcpy is fast; the expensive
                // per-pixel alpha fixup is deferred to Phase 2.
                // -------------------------------------------------------
                
                // Intermediate result from Phase 1.
                enum RawCopy {
                    Shm {
                        raw_pixels: Vec<u8>,
                        width: u32,
                        height: u32,
                        stride: u32,
                        format: u32,
                        is_opaque: bool,
                    },
                    Iosurface { id: u32, width: u32, height: u32, format: u32 },
                    None,
                }
                
                let (
                    raw_copy,
                    target_window_id,
                    expected_toplevel_size_from_toplevel,
                    expected_window_size,
                    xdg_pending_serial,
                    window_app_id,
                ) = {
                    let mut state = self.state.write_recover();
                    
                    let buffer = state.buffers.get(&(client_id.clone(), buffer_id)).cloned();
                    crate::wtrace!(crate::util::logging::FFI, "Buffer {} for client {:?} found: {}", 
                        buffer_id, client_id, buffer.is_some());
                    
                    let is_opaque = if let Some(surface) = state.surfaces.get(&surface_id) {
                        let surface = surface.read_recover();
                        surface.current.opaque_region.as_ref().map(|r| !r.is_empty()).unwrap_or(false)
                    } else {
                        false
                    };
                    
                    let raw = if let Some(buffer) = buffer {
                        let buffer = buffer.read_recover();
                        match &buffer.buffer_type {
                            crate::core::surface::BufferType::Shm(shm) => {
                                crate::wtrace!(crate::util::logging::FFI, "SHM buffer {}x{}, pool={}, offset={}, fmt={}",
                                    shm.width, shm.height, shm.pool_id, shm.offset, shm.format);
                                let from_smithay = buffer.resource.as_ref().and_then(|wlbuf| {
                                    smithay::wayland::shm::with_buffer_contents(wlbuf, |ptr, pool_len, data| {
                                        let offset = data.offset as usize;
                                        let need = (data.height as usize)
                                            .saturating_mul(data.stride as usize);
                                        if offset.saturating_add(need) > pool_len {
                                            return None;
                                        }
                                        let raw_pixels = unsafe {
                                            std::slice::from_raw_parts(ptr.add(offset), need)
                                        }
                                        .to_vec();
                                        Some(RawCopy::Shm {
                                            raw_pixels,
                                            width: data.width as u32,
                                            height: data.height as u32,
                                            stride: data.stride as u32,
                                            format: crate::core::surface::buffer::wl_shm_format_to_legacy_u32(
                                                data.format,
                                            ),
                                            is_opaque,
                                        })
                                    })
                                    .ok()
                                    .flatten()
                                });
                                if let Some(r) = from_smithay {
                                    r
                                } else if let Some(pool) =
                                    state.shm_pools.get_mut(&(client_id.clone(), shm.pool_id))
                                {
                                    if let Some(ptr) = pool.map() {
                                        let offset = shm.offset as usize;
                                        let size = (shm.height * shm.stride) as usize;
                                        if offset + size <= pool.size {
                                            let raw_pixels = unsafe {
                                                std::slice::from_raw_parts(ptr.add(offset), size)
                                            }
                                            .to_vec();
                                            RawCopy::Shm {
                                                raw_pixels,
                                                width: shm.width as u32,
                                                height: shm.height as u32,
                                                stride: shm.stride as u32,
                                                format: shm.format,
                                                is_opaque,
                                            }
                                        } else {
                                            crate::wlog!(crate::util::logging::FFI, "Buffer out of bounds: offset={} size={} pool_size={}", offset, size, pool.size);
                                            RawCopy::None
                                        }
                                    } else {
                                        crate::wlog!(crate::util::logging::FFI, "Failed to map SHM pool {}", shm.pool_id);
                                        RawCopy::None
                                    }
                                } else {
                                    crate::wlog!(crate::util::logging::FFI, "SHM pool {} not found", shm.pool_id);
                                    RawCopy::None
                                }
                            },
                            crate::core::surface::BufferType::Native(native) => {
                                crate::wlog_hot!(crate::util::logging::FFI, "FFI: IOSurface buffer id={} {}x{}", 
                                    native.id, native.width, native.height);
                                RawCopy::Iosurface {
                                    id: native.id as u32,
                                    width: native.width as u32,
                                    height: native.height as u32,
                                    format: native.format,
                                }
                            },
                            _ => {
                                crate::wlog_hot!(crate::util::logging::FFI, "FFI: Non-SHM buffer type, skipping");
                                RawCopy::None
                            }
                        }
                    } else {
                        crate::wlog_hot!(crate::util::logging::FFI, "FFI: Buffer {} not found in state.buffers", buffer_id);
                        RawCopy::None
                    };
                    
                    // Resolve surface → window mapping (including subsurface chains)
                    let mut target_window_id = state.surface_to_window.get(&surface_id).copied();
                    if target_window_id.is_none() {
                        if let Some(subsurface) = state.get_subsurface(surface_id) {
                            let mut parent_id = subsurface.parent_id;
                            let mut path = format!("{}->{}", surface_id, parent_id);
                            for _ in 0..10 {
                                if let Some(wid) = state.surface_to_window.get(&parent_id) {
                                    crate::wlog_hot!(crate::util::logging::FFI, "Resolved subsurface path: {} -> Window {}", path, wid);
                                    target_window_id = Some(*wid);
                                    break;
                                }
                                if let Some(parent_sub) = state.get_subsurface(parent_id) {
                                    parent_id = parent_sub.parent_id;
                                    path.push_str(&format!("->{}", parent_id));
                                } else {
                                    crate::wlog_hot!(crate::util::logging::FFI, "Subsurface path dead end: {} (parent {} has no window)", path, parent_id);
                                    break;
                                }
                            }
                        }
                    }
                    
                    let xdg_pending_serial = state
                        .xdg
                        .surfaces
                        .values()
                        .find(|s| s.surface_id == surface_id)
                        .map(|s| s.pending_serial)
                        .unwrap_or(0);
                    let expected_toplevel_size_from_toplevel = state
                        .xdg
                        .toplevels
                        .values()
                        .find(|tl| tl.surface_id == surface_id)
                        .map(|tl| (tl.width, tl.height));
                    let expected_window_size = target_window_id
                        .and_then(|wid| state.windows.get(&wid))
                        .map(|w| {
                            let w = w.read_recover();
                            (w.width as u32, w.height as u32)
                        });
                    let window_app_id = target_window_id
                        .and_then(|wid| state.windows.get(&wid))
                        .and_then(|w| w.read().ok())
                        .map(|w| w.app_id.clone());

                    (
                        raw,
                        target_window_id,
                        expected_toplevel_size_from_toplevel,
                        expected_window_size,
                        xdg_pending_serial,
                        window_app_id,
                    )
                }; // state write-lock released
                
                // -------------------------------------------------------
                // Phase 2: Expensive per-pixel work OUTSIDE the lock.
                // For a 1920×1080 XRGB buffer this iterates ~2M pixels;
                // doing it without holding the state lock avoids blocking
                // the IPC server and other readers.
                // -------------------------------------------------------
                let buffer_data = match raw_copy {
                    RawCopy::Shm { mut raw_pixels, width, height, stride, format, is_opaque } => {
                        let (fmt, mut needs_alpha_fix) = match format {
                            0 => (types::BufferFormat::Argb8888, is_opaque),
                            1 => (types::BufferFormat::Xrgb8888, true),
                            _ => (types::BufferFormat::Argb8888, is_opaque),
                        };
                        // Pixman/Weston often commit ARGB8888 with zero alpha and
                        // no wl_surface opaque region, which makes CALayer treat
                        // the buffer as fully transparent on iOS.
                        if !needs_alpha_fix && format == 0 && raw_pixels.len() >= 4 {
                            let sample = stride as usize * height as usize;
                            let sample = sample.min(raw_pixels.len());
                            needs_alpha_fix = raw_pixels[..sample]
                                .chunks_exact(4)
                                .all(|px| px[3] == 0);
                        }
                        if needs_alpha_fix {
                            for chunk in raw_pixels.chunks_exact_mut(4) {
                                chunk[3] = 0xFF;
                            }
                        }
                        Some(types::BufferData::Shm {
                            pixels: raw_pixels,
                            width,
                            height,
                            format: fmt,
                            stride,
                        })
                    },
                    RawCopy::Iosurface { id, width, height, format } => {
                        Some(types::BufferData::Iosurface { id, width, height, format })
                    },
                    RawCopy::None => None,
                };
                
                // -------------------------------------------------------
                // Phase 3: Enqueue result and flush callbacks (fast, brief
                // lock acquisition).
                // -------------------------------------------------------
                {
                    let mut state = self.state.write_recover();
                    let mut queued_for_presentation = false;
                    
                    if let Some(data) = buffer_data {
                        let surface_buffer_scale = state
                            .surfaces
                            .get(&surface_id)
                            .map(|s| s.read_recover().current.scale.max(1) as u32)
                            .unwrap_or(1);
                        let output_scale = {
                            let (_, _, scale) = *self.output_size.read_recover();
                            scale.round().max(1.0) as u32
                        };
                        // Nested compositors (e.g. Weston) often commit at output
                        // scale while wl_surface.scale stays at 1.
                        let effective_buffer_scale = surface_buffer_scale.max(output_scale);
                        let current_expected_size = expected_toplevel_size_from_toplevel
                            .filter(|(w, h)| *w > 0 && *h > 0)
                            .or(expected_window_size);
                        let toplevel_size_is_zero = expected_toplevel_size_from_toplevel
                            .map(|(w, h)| w == 0 || h == 0)
                            .unwrap_or(true);
                        let expected_source = if expected_toplevel_size_from_toplevel
                            .map(|(w, h)| w > 0 && h > 0)
                            .unwrap_or(false)
                        {
                            "xdg_toplevel"
                        } else if expected_window_size.is_some() {
                            "window_cache"
                        } else {
                            "none"
                        };
                        let pre_stable_gate_active = xdg_pending_serial != 0 || toplevel_size_is_zero;
                        let prestable_tolerance_px = if pre_stable_gate_active
                            && window_app_id
                                .as_deref()
                                .map(is_weston_family_app_id)
                                .unwrap_or(false)
                        {
                            WESTON_FAMILY_PRESTABLE_TOLERANCE_PX
                        } else {
                            PRESTABLE_MISMATCH_TOLERANCE_PX
                        };

                        // Drop only during the configure handshake (pending serial or
                        // zero-sized toplevel). Post-stable mismatches are accepted
                        // and scaled by the platform layer. Required for fixed-size
                        // demos like weston-smoke (always 200×200, ignores resize).
                        let should_drop_size_mismatch = current_expected_size
                            .map(|(expected_w, expected_h)| {
                                let (dw, dh) = buffer_size_mismatch_px(
                                    data.width(),
                                    data.height(),
                                    expected_w,
                                    expected_h,
                                    effective_buffer_scale,
                                );
                                pre_stable_gate_active
                                    && (dw > prestable_tolerance_px || dh > prestable_tolerance_px)
                            })
                            .unwrap_or(false);
                        let mismatch_tuple = current_expected_size.map(|(expected_w, expected_h)| {
                            buffer_size_mismatch_px(
                                data.width(),
                                data.height(),
                                expected_w,
                                expected_h,
                                effective_buffer_scale,
                            )
                        });
                        if pre_stable_gate_active
                            || should_drop_size_mismatch
                            || mismatch_tuple
                                .map(|(dw, dh)| dw > STABLE_MISMATCH_WARN_PX || dh > STABLE_MISMATCH_WARN_PX)
                                .unwrap_or(false)
                        {
                            crate::wlog_hot!(
                                crate::util::logging::FFI,
                                "SurfaceCommit decision: surf={} win={:?} buf={}x{} pending_serial={} toplevel={:?} window={:?} expected_src={} expected={:?} mismatch={:?} prestable={} drop={}",
                                surface_id,
                                target_window_id,
                                data.width(),
                                data.height(),
                                xdg_pending_serial,
                                expected_toplevel_size_from_toplevel,
                                expected_window_size,
                                expected_source,
                                current_expected_size,
                                mismatch_tuple,
                                pre_stable_gate_active,
                                should_drop_size_mismatch
                            );
                        }

                        if should_drop_size_mismatch {
                            if let Some((expected_w, expected_h)) = current_expected_size {
                                crate::wtrace!(
                                    crate::util::logging::FFI,
                                    "Dropping mismatched commit: surf={} buf={} committed={}x{} expected={}x{} pending_serial={} toplevel_zero={} expected_src={} tolerance_px={}",
                                    surface_id,
                                    buffer_id,
                                    data.width(),
                                    data.height(),
                                    expected_w,
                                    expected_h,
                                    xdg_pending_serial,
                                    toplevel_size_is_zero,
                                    expected_source,
                                    PRESTABLE_MISMATCH_TOLERANCE_PX
                                );
                            }
                            state.release_buffer(client_id.clone(), buffer_id);
                            state.flush_frame_callbacks(
                                surface_id,
                                Some(crate::core::state::CompositorState::get_timestamp_ms()),
                            );
                        } else if let Some(window_id) = target_window_id {
                            let win_id = types::WindowId { id: window_id as u64 };
                            crate::wtrace!(crate::util::logging::FFI, "FFI: Queuing buffer for window {}", win_id.id);
                            if let (false, Some((dw, dh))) = (pre_stable_gate_active, mismatch_tuple) {
                                if dw > STABLE_MISMATCH_WARN_PX || dh > STABLE_MISMATCH_WARN_PX {
                                    crate::wlog!(
                                        crate::util::logging::FFI,
                                        "Large post-stable mismatch accepted: surf={} buf={} win={} mismatch={}x{} expected_src={}",
                                        surface_id,
                                        buffer_id,
                                        win_id.id,
                                        dw,
                                        dh,
                                        expected_source
                                    );
                                }
                            }
                            
                            let mut pending = self.pending_buffers.write_recover();
                            let new_buffer = types::WindowBuffer {
                                window_id: win_id,
                                surface_id: types::SurfaceId { id: surface_id },
                                buffer: types::Buffer {
                                    id: types::BufferId { id: buffer_id as u64 },
                                    data: data.clone()
                                }
                            };
                            
                            if let Some(old_buffer) = pending.insert(win_id, new_buffer) {
                                if old_buffer.buffer.id.id != buffer_id as u64 {
                                    state.release_buffer(client_id.clone(), old_buffer.buffer.id.id as u32);
                                }
                            }
                            
                            self.pending_redraws.write_recover().push(win_id);
                            queued_for_presentation = true;

                            // Update FFI surface state cache
                            let surf_state = types::SurfaceState {
                                id: types::SurfaceId { id: surface_id },
                                buffer_id: Some(types::BufferId { id: buffer_id as u64 }),
                                buffer_x: 0,
                                buffer_y: 0,
                                buffer_width: data.width(),
                                buffer_height: data.height(),
                                buffer_scale: 1.0,
                                buffer_transform: types::OutputTransform::Normal,
                                damage: Vec::new(),
                                opaque_region: Vec::new(),
                                input_region: Vec::new(),
                                role: types::SurfaceRole::Toplevel,
                            };
                            self.ffi_surfaces.write_recover().insert(surface_id, surf_state);
                        } else {
                            // If the surface has not been mapped to a host window yet,
                            // do not hold wl_surface.frame callbacks indefinitely.
                            // This keeps clients like weston-simple-shm animating once
                            // window mapping catches up.
                            crate::wlog_hot!(
                                crate::util::logging::FFI,
                                "FFI: No window for surface {} in SurfaceCommitted; releasing buffer {} and flushing callbacks",
                                surface_id,
                                buffer_id
                            );
                            state.release_buffer(client_id.clone(), buffer_id);
                            state.flush_frame_callbacks(
                                surface_id,
                                Some(crate::core::state::CompositorState::get_timestamp_ms()),
                            );
                        }
                    } else {
                        // Buffer extraction/import failed. Avoid client stalls by
                        // advancing frame callbacks even when we cannot present.
                        crate::wlog!(
                            crate::util::logging::FFI,
                            "FFI: SurfaceCommitted surf={} buf={} had no presentable buffer; flushing callbacks",
                            surface_id,
                            buffer_id
                        );
                        state.flush_frame_callbacks(
                            surface_id,
                            Some(crate::core::state::CompositorState::get_timestamp_ms()),
                        );
                    }
                    
                    let callback_count = state
                        .frame_callbacks
                        .get(&surface_id)
                        .map(|cbs| cbs.len())
                        .unwrap_or(0);
                    // Frame callbacks for queued buffers are flushed from
                    // notify_frame_presented() after release. Flushing at
                    // commit time races SHM double-buffering (nested Weston)
                    // and stalls once both pool buffers are in flight.
                    crate::wlog_hot!(crate::util::logging::FFI,
                        "SurfaceCommitted: surf={} buf={} frame_cbs_pending={} queued_for_presentation={}",
                        surface_id, buffer_id, callback_count, queued_for_presentation);
                }
            }
            CompositorEvent::LayerSurfaceCommitted { client_id, surface_id, buffer_id } => {
                let internal_client_id = format!("{:?}", client_id);
                crate::wlog_hot!(
                    crate::util::logging::FFI,
                    "LayerSurfaceCommitted client={}, surface={}, buffer_id={:?}",
                    internal_client_id,
                    surface_id,
                    buffer_id
                );

                // Queue layer buffers for presentation (DesktopHost / Android
                // scene quads). Synthetic window id keeps pending_buffers unique
                // without colliding with xdg toplevel ids.
                const LAYER_WINDOW_FLAG: u64 = 1u64 << 63;
                let Some(bid) = buffer_id else {
                    let mut state = self.state.write_recover();
                    state.flush_frame_callbacks(
                        surface_id,
                        Some(crate::core::state::CompositorState::get_timestamp_ms()),
                    );
                    return;
                };
                let buffer_id_u32 = bid as u32;

                enum LayerRaw {
                    Shm {
                        pixels: Vec<u8>,
                        width: u32,
                        height: u32,
                        stride: u32,
                        format: u32,
                    },
                    Iosurface {
                        id: u32,
                        width: u32,
                        height: u32,
                        format: u32,
                    },
                    None,
                }

                let raw = {
                    let mut state = self.state.write_recover();
                    let auth = state
                        .buffers
                        .get(&(client_id.clone(), buffer_id_u32))
                        .cloned()
                        .or_else(|| {
                            state
                                .buffers
                                .iter()
                                .find(|(_, b)| b.read_recover().id == buffer_id_u32)
                                .map(|(_, b)| b.clone())
                        });
                    match auth {
                        Some(auth_buffer) => {
                            let buffer = auth_buffer.read_recover();
                            match &buffer.buffer_type {
                                crate::core::surface::BufferType::Shm(shm) => {
                                    if let Some(pool) =
                                        state.shm_pools.get_mut(&(client_id.clone(), shm.pool_id))
                                    {
                                        if let Some(ptr) = pool.map() {
                                            let offset = shm.offset as usize;
                                            let size = (shm.height * shm.stride) as usize;
                                            if offset + size <= pool.size {
                                                let raw_pixels = unsafe {
                                                    std::slice::from_raw_parts(ptr.add(offset), size)
                                                }
                                                .to_vec();
                                                LayerRaw::Shm {
                                                    pixels: raw_pixels,
                                                    width: shm.width as u32,
                                                    height: shm.height as u32,
                                                    stride: shm.stride as u32,
                                                    format: shm.format,
                                                }
                                            } else {
                                                LayerRaw::None
                                            }
                                        } else {
                                            LayerRaw::None
                                        }
                                    } else {
                                        LayerRaw::None
                                    }
                                }
                                crate::core::surface::BufferType::Native(native) => {
                                    LayerRaw::Iosurface {
                                        id: native.id as u32,
                                        width: native.width as u32,
                                        height: native.height as u32,
                                        format: native.format,
                                    }
                                }
                                _ => LayerRaw::None,
                            }
                        }
                        None => LayerRaw::None,
                    }
                };

                let buffer_data = match raw {
                    LayerRaw::Shm {
                        mut pixels,
                        width,
                        height,
                        stride,
                        format,
                    } => {
                        let (fmt, needs_alpha) = match format {
                            0 => (types::BufferFormat::Argb8888, false),
                            1 => (types::BufferFormat::Xrgb8888, true),
                            _ => (types::BufferFormat::Argb8888, false),
                        };
                        if needs_alpha {
                            for chunk in pixels.chunks_exact_mut(4) {
                                chunk[3] = 0xFF;
                            }
                        }
                        Some(types::BufferData::Shm {
                            pixels,
                            width,
                            height,
                            format: fmt,
                            stride,
                        })
                    }
                    LayerRaw::Iosurface {
                        id,
                        width,
                        height,
                        format,
                    } => Some(types::BufferData::Iosurface {
                        id,
                        width,
                        height,
                        format,
                    }),
                    LayerRaw::None => None,
                };

                if let Some(data) = buffer_data {
                    let layer_win = types::WindowId {
                        id: LAYER_WINDOW_FLAG | (surface_id as u64),
                    };
                    let mut pending = self.pending_buffers.write_recover();
                    let new_buffer = types::WindowBuffer {
                        window_id: layer_win,
                        surface_id: types::SurfaceId { id: surface_id },
                        buffer: types::Buffer {
                            id: types::BufferId { id: bid },
                            data: data.clone(),
                        },
                    };
                    if let Some(old_buffer) = pending.insert(layer_win, new_buffer) {
                        if old_buffer.buffer.id.id != bid {
                            let mut state = self.state.write_recover();
                            state.release_buffer(client_id.clone(), old_buffer.buffer.id.id as u32);
                        }
                    }
                    self.pending_redraws.write_recover().push(layer_win);
                    let surf_state = types::SurfaceState {
                        id: types::SurfaceId { id: surface_id },
                        buffer_id: Some(types::BufferId { id: bid }),
                        buffer_x: 0,
                        buffer_y: 0,
                        buffer_width: data.width(),
                        buffer_height: data.height(),
                        buffer_scale: 1.0,
                        buffer_transform: types::OutputTransform::Normal,
                        damage: Vec::new(),
                        opaque_region: Vec::new(),
                        input_region: Vec::new(),
                        role: types::SurfaceRole::None,
                    };
                    self.ffi_surfaces.write_recover().insert(surface_id, surf_state);
                    crate::wlog_hot!(
                        crate::util::logging::FFI,
                        "LayerSurfaceCommitted queued surf={} buf={} {}x{}",
                        surface_id,
                        bid,
                        data.width(),
                        data.height()
                    );
                } else {
                    let mut state = self.state.write_recover();
                    state.release_buffer(client_id.clone(), buffer_id_u32);
                    state.flush_frame_callbacks(
                        surface_id,
                        Some(crate::core::state::CompositorState::get_timestamp_ms()),
                    );
                }
            }
            CompositorEvent::CursorCommitted { client_id, surface_id, buffer_id, hotspot_x, hotspot_y } => {
                let internal_client_id = format!("{:?}", client_id);
                crate::wlog_hot!(crate::util::logging::FFI, "CursorCommitted client={}, surface={}, buffer_id={:?}, hotspot=({}, {})", 
                    internal_client_id, surface_id, buffer_id, hotspot_x, hotspot_y);
                
                // Process cursor buffer exactly like a window buffer so the
                // platform can render the Wayland-provided cursor image.
                if let Some(bid) = buffer_id {
                    let buffer_id_u32 = bid as u32;

                    // Phase 1: copy raw pixel data under the state lock
                    enum CursorRaw {
                        Shm { pixels: Vec<u8>, width: u32, height: u32, stride: u32, format: u32 },
                        Iosurface { id: u32, width: u32, height: u32, format: u32 },
                        None,
                    }

                    let raw = {
                        let mut state = self.state.write_recover();

                        // Extract buffer metadata first so we can drop the
                        // immutable borrow before mutably borrowing shm_pools.
                        enum BufInfo {
                            Shm { pool_id: u32, offset: usize, size: usize, width: u32, height: u32, stride: u32, format: u32 },
                            Native { id: u32, width: u32, height: u32, format: u32 },
                            None,
                        }

                        let (info, wl_buffer) = if let Some(buf_ref) = state.buffers.get(&(client_id.clone(), buffer_id_u32)) {
                            let buf = buf_ref.read_recover();
                            let info = match &buf.buffer_type {
                                crate::core::surface::BufferType::Shm(shm) => BufInfo::Shm {
                                    pool_id: shm.pool_id,
                                    offset: shm.offset as usize,
                                    size: (shm.height * shm.stride) as usize,
                                    width: shm.width as u32,
                                    height: shm.height as u32,
                                    stride: shm.stride as u32,
                                    format: shm.format as u32,
                                },
                                crate::core::surface::BufferType::Native(native) => BufInfo::Native {
                                    id: native.id as u32,
                                    width: native.width as u32,
                                    height: native.height as u32,
                                    format: native.format,
                                },
                                _ => BufInfo::None,
                            };
                            (info, buf.resource.clone())
                        } else { (BufInfo::None, None) };

                        match info {
                            BufInfo::Shm { pool_id, offset, size, width, height, stride, format } => {
                                // Smithay owns wl_shm pool state; read pixels
                                // through it first. The internal shm_pools map
                                // only covers legacy paths.
                                let from_smithay = wl_buffer.as_ref().and_then(|wlbuf| {
                                    smithay::wayland::shm::with_buffer_contents(wlbuf, |ptr, pool_len, data| {
                                        let off = data.offset as usize;
                                        let need = (data.height as usize)
                                            .saturating_mul(data.stride as usize);
                                        if off.saturating_add(need) > pool_len {
                                            return None;
                                        }
                                        let pixels = unsafe {
                                            std::slice::from_raw_parts(ptr.add(off), need)
                                        }
                                        .to_vec();
                                        Some(CursorRaw::Shm {
                                            pixels,
                                            width: data.width as u32,
                                            height: data.height as u32,
                                            stride: data.stride as u32,
                                            format: crate::core::surface::buffer::wl_shm_format_to_legacy_u32(
                                                data.format,
                                            ),
                                        })
                                    })
                                    .ok()
                                    .flatten()
                                });
                                if let Some(raw) = from_smithay {
                                    raw
                                } else if let Some(pool) = state.shm_pools.get_mut(&(client_id.clone(), pool_id)) {
                                    if let Some(ptr) = pool.map() {
                                        if offset + size <= pool.size {
                                            let pixels = unsafe {
                                                std::slice::from_raw_parts(ptr.add(offset), size)
                                            }.to_vec();
                                            CursorRaw::Shm { pixels, width, height, stride, format }
                                        } else { CursorRaw::None }
                                    } else { CursorRaw::None }
                                } else { CursorRaw::None }
                            }
                            BufInfo::Native { id, width, height, format } => {
                                CursorRaw::Iosurface { id, width, height, format }
                            }
                            BufInfo::None => CursorRaw::None,
                        }
                    };

                    // Phase 2: alpha fixup outside lock
                    let cursor_buffer = match raw {
                        CursorRaw::Shm { mut pixels, width, height, stride, format } => {
                            let (fmt, needs_fix) = match format {
                                0 => (types::BufferFormat::Argb8888, false),
                                1 => (types::BufferFormat::Xrgb8888, true),
                                _ => (types::BufferFormat::Argb8888, false),
                            };
                            if needs_fix {
                                for chunk in pixels.chunks_exact_mut(4) {
                                    chunk[3] = 0xFF;
                                }
                            }
                            Some(types::BufferData::Shm { pixels, width, height, format: fmt, stride })
                        }
                        CursorRaw::Iosurface { id, width, height, format } => {
                            Some(types::BufferData::Iosurface { id, width, height, format })
                        }
                        CursorRaw::None => None,
                    };

                // Phase 3: enqueue cursor buffer for the platform
                    if let Some(data) = cursor_buffer {
                        // Use a sentinel window ID (u64::MAX) to tag cursor buffers
                        let cursor_win_id = types::WindowId { id: u64::MAX };
                        let mut pending = self.pending_buffers.write_recover();
                        let new_buffer = types::WindowBuffer {
                            window_id: cursor_win_id,
                            surface_id: types::SurfaceId { id: surface_id },
                            buffer: types::Buffer {
                                id: types::BufferId { id: bid },
                                data,
                            },
                        };
                        if let Some(old) = pending.insert(cursor_win_id, new_buffer) {
                            if old.buffer.id.id != bid {
                                let mut state = self.state.write_recover();
                                state.release_buffer(client_id.clone(), old.buffer.id.id as u32);
                            }
                        }
                    }
                }

                // Always flush frame callbacks so the client can keep rendering
                {
                    let mut state = self.state.write_recover();
                    state.ext.fullscreen_shell.flush_pending_mode_feedbacks();
                    state.flush_frame_callbacks(surface_id, Some(crate::core::state::CompositorState::get_timestamp_ms()));
                }
                self.flush_clients();
            }
            CompositorEvent::WindowMoveRequested { window_id, seat_id: _, serial } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::MoveRequested { 
                        window_id: WindowId { id: window_id as u64 }, 
                        serial 
                    }
                );
            }
            CompositorEvent::WindowResizeRequested { window_id, seat_id: _, serial, edges } => {
                self.pending_window_events.write_recover().push(
                    WindowEvent::ResizeRequested { 
                        window_id: WindowId { id: window_id as u64 }, 
                        serial,
                        edge: crate::ffi::types::ResizeEdge::from_u32(edges)
                    }
                );
            }
            CompositorEvent::CursorShapeChanged { shape } => {
                crate::wlog!(crate::util::logging::FFI, "CursorShapeChanged shape={}", shape);
                self.pending_window_events.write_recover().push(
                    WindowEvent::CursorShapeChanged { shape }
                );
            }
            CompositorEvent::SystemBell { client_id, surface_id } => {
                let internal_client_id = format!("{:?}", client_id);
                crate::wlog!(crate::util::logging::FFI, "SystemBell client={}, surface={}", internal_client_id, surface_id);
                self.pending_window_events.write_recover().push(
                    WindowEvent::SystemBell { surface_id }
                );
            }
        }
    }
}

fn smithay_pointer_handle(
    state: &CompositorState,
) -> Option<smithay::input::pointer::PointerHandle<CompositorState>> {
    state
        .smithay_runtime
        .seat
        .as_ref()
        .and_then(|seat| seat.get_pointer())
}

/// Deliver pointer motion through Smithay's grab/focus pipeline (enter/leave/motion/frame).
#[allow(dead_code)]
fn smithay_dispatch_pointer_motion(
    state: &mut CompositorState,
    timestamp_ms: u32,
    serial: u32,
) -> bool {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return false;
    };
    let focus = smithay_pointer_focus(state, state.seat.pointer.focus);
    let event = smithay::input::pointer::MotionEvent {
        location: smithay::utils::Point::<_, smithay::utils::Logical>::from((
            state.seat.pointer.x,
            state.seat.pointer.y,
        )),
        serial: serial.into(),
        time: timestamp_ms,
    };
    pointer.motion(state, focus, &event);
    pointer.frame(state);
    true
}

/// Deliver pointer button through Smithay (uses last motion location for hit testing).
fn smithay_dispatch_pointer_button(
    state: &mut CompositorState,
    serial: u32,
    timestamp_ms: u32,
    button: u32,
    wl_state: wayland_server::protocol::wl_pointer::ButtonState,
) -> bool {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return false;
    };
    use smithay::backend::input::ButtonState as SmithayButtonState;
    let smithay_state = match wl_state {
        wayland_server::protocol::wl_pointer::ButtonState::Pressed => SmithayButtonState::Pressed,
        wayland_server::protocol::wl_pointer::ButtonState::Released => SmithayButtonState::Released,
        _ => return false,
    };
    let event = smithay::input::pointer::ButtonEvent {
        serial: serial.into(),
        time: timestamp_ms,
        button,
        state: smithay_state,
    };
    pointer.button(state, &event);
    pointer.frame(state);
    true
}

fn smithay_pointer_count(state: &CompositorState, client: &wayland_server::Client) -> usize {
    smithay_pointer_handle(state)
        .map(|pointer| pointer.client_pointers(client).count())
        .unwrap_or(0)
}

fn smithay_send_pointer_enter(
    state: &CompositorState,
    client: &wayland_server::Client,
    serial: u32,
    surface: &wayland_server::protocol::wl_surface::WlSurface,
    lx: f64,
    ly: f64,
) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    for ptr in pointer.client_pointers(client) {
        ptr.enter(serial, surface, lx, ly);
        sent += 1;
    }
    sent
}

fn smithay_send_pointer_leave(
    state: &CompositorState,
    client: &wayland_server::Client,
    serial: u32,
    surface: &wayland_server::protocol::wl_surface::WlSurface,
) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    for ptr in pointer.client_pointers(client) {
        ptr.leave(serial, surface);
        sent += 1;
    }
    sent
}

fn smithay_send_pointer_motion(
    state: &CompositorState,
    client: &wayland_server::Client,
    time: u32,
    lx: f64,
    ly: f64,
) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    for ptr in pointer.client_pointers(client) {
        ptr.motion(time, lx, ly);
        sent += 1;
    }
    sent
}

fn smithay_send_pointer_button(
    state: &CompositorState,
    client: &wayland_server::Client,
    serial: u32,
    time: u32,
    button: u32,
    wl_state: wayland_server::protocol::wl_pointer::ButtonState,
) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    for ptr in pointer.client_pointers(client) {
        ptr.button(serial, time, button, wl_state);
        sent += 1;
    }
    sent
}

/// Deliver `wl_pointer.axis` the same way as buttons: via `client_pointers()`,
/// not smithay's grab focus. Motion/enter already bypass smithay's internal
/// focus (`deliver_pointer_motion_to_clients`), so `pointer.axis()` would
/// often target `None` and silently drop scroll (terminals never scroll).
fn smithay_send_pointer_axis(
    state: &CompositorState,
    client: &wayland_server::Client,
    time: u32,
    axis: wayland_server::protocol::wl_pointer::Axis,
    value: f64,
    source: wayland_server::protocol::wl_pointer::AxisSource,
    discrete: i32,
) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    for ptr in pointer.client_pointers(client) {
        if ptr.version() >= 5 {
            let src = if ptr.version() < 6 {
                match source {
                    wayland_server::protocol::wl_pointer::AxisSource::WheelTilt => {
                        wayland_server::protocol::wl_pointer::AxisSource::Wheel
                    }
                    other => other,
                }
            } else {
                source
            };
            ptr.axis_source(src);
            if discrete != 0 {
                ptr.axis_discrete(axis, discrete);
            }
        }
        ptr.axis(time, axis, value);
        sent += 1;
    }
    sent
}

fn smithay_send_pointer_frame(state: &CompositorState, client: &wayland_server::Client) -> usize {
    let Some(pointer) = smithay_pointer_handle(state) else {
        return 0;
    };
    let mut sent = 0;
    // Smithay's own seat path gates this; client_pointers() does not.
    // Opcode 5 (`frame`) is since wl_pointer v5. See broadcast_frame.
    for ptr in pointer.client_pointers(client) {
        if ptr.version() >= 5 {
            ptr.frame();
            sent += 1;
        }
    }
    sent
}

/// Deliver wl_pointer motion/frame to Wayland clients.
///
/// Prefer explicit `client_pointers()` delivery so clients that bind wl_pointer
/// after an early injectPointerEnter still receive enter+motion. Smithay's
/// internal grab can miss enter when motion is injected before bind.
fn deliver_pointer_motion_to_clients(
    state: &mut CompositorState,
    timestamp_ms: u32,
    lx: f64,
    ly: f64,
) {
    let focused_client = state.focused_pointer_client();
    if let Some(client) = focused_client.as_ref() {
        let mut sent = smithay_send_pointer_motion(state, client, timestamp_ms, lx, ly);
        if sent == 0 {
            if let Some(sid) = state.seat.pointer.focus {
                if let Some(surface) = state.surfaces.get(&sid).cloned() {
                    let surface = surface.read_recover();
                    if let Some(res) = &surface.resource {
                        let enter_serial = state.next_serial();
                        sent = smithay_send_pointer_enter(state, client, enter_serial, res, lx, ly);
                        if sent > 0 {
                            state.seat.pointer.last_enter_serial = enter_serial;
                            sent = smithay_send_pointer_motion(state, client, timestamp_ms, lx, ly);
                        }
                    }
                }
            }
        }
        if sent > 0 {
            smithay_send_pointer_frame(state, client);
            return;
        }
    }
    if state.seat.pointer.resources.is_empty() {
        return;
    }
    state
        .seat
        .broadcast_pointer_motion(timestamp_ms, lx, ly, focused_client.as_ref());
    state
        .seat
        .broadcast_pointer_frame(focused_client.as_ref());
}

/// Push a pointer motion at the seat's current global position so clients
/// (e.g. nested Weston desktop-shell) see coordinates before button events.
fn dispatch_pointer_motion_at_seat(
    state: &mut CompositorState,
    timestamp_ms: u32,
    _serial: u32,
) {
    let focus_sid = state.seat.pointer.focus;
    let sx = state.seat.pointer.x;
    let sy = state.seat.pointer.y;
    let (lx, ly) = pointer_surface_local_coords(state, sx, sy, focus_sid);
    state.seat.pointer.focus_x = lx;
    state.seat.pointer.focus_y = ly;
    deliver_pointer_motion_to_clients(state, timestamp_ms, lx, ly);
}

/// Ensure pointer focus matches the window the platform says events are
/// coming from.  If the current `seat.pointer.focus` points to a different
/// surface, sends leave/enter events to update it.  This makes focus
/// tracking robust against missed `mouseEntered:` / `mouseExited:`
/// callbacks on macOS.
fn ensure_pointer_focus(
    state: &mut crate::core::state::CompositorState,
    window_id: WindowId,
    serial_fn: &dyn Fn() -> u32,
) {
    let target_sid = state.surface_to_window.iter()
        .find(|(_, &wid)| wid as u64 == window_id.id)
        .map(|(sid, _)| *sid);

    let target_sid = match target_sid {
        Some(sid) => sid,
        None => return,
    };

    if state.seat.pointer.focus == Some(target_sid) {
        return;
    }

    let old_sid = state.seat.pointer.focus;

    state.seat.pointer.focus = Some(target_sid);
    let x = state.seat.pointer.x;
    let y = state.seat.pointer.y;
    let (lx, ly) = pointer_surface_local_coords(state, x, y, Some(target_sid));
    state.seat.pointer.focus_x = lx;
    state.seat.pointer.focus_y = ly;

    let serial = serial_fn();
    state.seat.pointer.last_enter_serial = serial;

    if let Some(old_sid) = old_sid {
        if let Some(surface) = state.surfaces.get(&old_sid).cloned() {
            let surface = surface.read_recover();
            if let Some(res) = &surface.resource {
                if let Some(client) = res.client() {
                    if smithay_send_pointer_leave(state, &client, serial, res) == 0 {
                        state.seat.broadcast_pointer_leave(serial, res);
                    }
                }
            }
        }
    }

    if let Some(surface) = state.surfaces.get(&target_sid).cloned() {
        let surface = surface.read_recover();
        if let Some(res) = &surface.resource {
            if let Some(client) = res.client() {
                let sent = smithay_send_pointer_enter(state, &client, serial, res, lx, ly);
                if sent > 0 {
                    smithay_send_pointer_frame(state, &client);
                } else {
                    state.seat.broadcast_pointer_enter(serial, res, lx, ly);
                }
            }
        }
    }
    deliver_pointer_motion_to_clients(state, 0, lx, ly);
}

#[uniffi::export]
impl WawonaCore {
    // =========================================================================
    // Platform Event Polling
    // =========================================================================
    
    /// Get pending window events (platform polls for these)
    pub fn poll_window_events(&self) -> Vec<WindowEvent> {
        std::mem::take(&mut *self.pending_window_events.write_recover())
    }
    
    /// Get pending client events (platform polls for these)
    pub fn poll_client_events(&self) -> Vec<ClientEvent> {
        std::mem::take(&mut *self.pending_client_events.write_recover())
    }
    
    /// Pop a single pending window event
    pub fn pop_window_event(&self) -> Option<WindowEvent> {
        let mut events = self.pending_window_events.write_recover();
        if events.is_empty() {
            None
        } else {
            Some(events.remove(0))
        }
    }

    pub fn pending_window_event_count(&self) -> u32 {
        self.pending_window_events.read_recover().len() as u32
    }
    
    /// Pop a single pending buffer (platform pulls these one by one)
    pub fn pop_pending_buffer(&self) -> Option<types::WindowBuffer> {
        let mut pending = self.pending_buffers.write_recover();
        let key = *pending.keys().next()?;
        let popped = pending.remove(&key);
        if let Some(buf) = &popped {
            crate::wtrace!(
                crate::util::logging::FFI,
                "Popped buffer: win={} surf={} buf={} {}x{} pending_left={}",
                buf.window_id.id,
                buf.surface_id.id,
                buf.buffer.id.id,
                buf.buffer.data.width(),
                buf.buffer.data.height(),
                pending.len()
            );
        }
        popped
    }

    /// Pop pending gamma restore (platform restores original tables)
    pub fn pop_pending_gamma_restore(&self) -> Option<u32> {
        if !self.is_running() {
            return None;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::wlr::gamma_control::pop_pending_gamma_restore(&mut state)
    }

    /// Get the first pending screencopy (platform writes ARGB8888 pixels to ptr, then calls screencopy_done)
    pub fn get_pending_screencopy(&self) -> Option<types::ScreencopyRequest> {
        if !self.is_running() {
            return None;
        }
        let state = self.state.read_recover();
        crate::core::wayland::wlr::screencopy::get_pending_screencopy(&state).map(
            |(capture_id, ptr, width, height, stride, size)| types::ScreencopyRequest {
                capture_id,
                ptr: ptr as u64,
                width,
                height,
                stride,
                size: size as u64,
            },
        )
    }

    /// Notify screencopy capture complete (platform has written pixels to the buffer)
    pub fn screencopy_done(&self, capture_id: u64) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::wlr::screencopy::complete_screencopy(&mut state, capture_id);
    }

    /// Notify screencopy capture failed
    pub fn screencopy_failed(&self, capture_id: u64) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::wlr::screencopy::fail_screencopy(&mut state, capture_id);
    }

    /// Notify that a frame has been presented
    pub fn notify_frame_presented(&self, surface_id: SurfaceId, buffer_id: Option<BufferId>, timestamp: u32) {
        let mut state = self.state.write_recover();
        
        let client_id = state.surfaces.get(&surface_id.id)
            .and_then(|s| s.read_recover().client_id.clone());

        let callback_count = state
            .frame_callbacks
            .get(&surface_id.id)
            .map(|cbs| cbs.len())
            .unwrap_or(0);
        let pending_releases = state.pending_buffer_releases.len();
            
        thread_local! {
            static SURFACE_PRESENTED_COUNTS: std::cell::RefCell<std::collections::HashMap<u32, u32>> = Default::default();
            static SURFACE_RELEASE_COUNTS: std::cell::RefCell<std::collections::HashMap<u32, u32>> = Default::default();
        }
        let presented_count = SURFACE_PRESENTED_COUNTS.with(|counts| {
            let mut map = counts.borrow_mut();
            let count = map.entry(surface_id.id).or_insert(0);
            *count += 1;
            *count
        });

        let timestamp_ns = (timestamp as u64) * 1_000_000;
        let refresh_ns: u64 = 1_000_000_000 / 60;
        let seq = state.ext.presentation.next_seq;
        state.ext.presentation.next_seq += 1;
        state.ext.presentation.send_presented_events(timestamp_ns, refresh_ns, seq);

        // Flush queued buffer releases from handle_surface_commit. This is the
        // correct time: the frame has been rendered and the old buffer's texture
        // is no longer needed. Keep releases before frame callbacks so
        // double-buffered clients (weston-simple-shm) always observe at least
        // one free buffer when redraw callback fires.
        state.flush_buffer_releases();

        if let Some(buf_id) = buffer_id {
            if let Some(cid) = client_id {
                let buffer_id_u32 = buf_id.id as u32;
                state.release_buffer(cid, buffer_id_u32);
                let release_count = SURFACE_RELEASE_COUNTS.with(|counts| {
                    let mut map = counts.borrow_mut();
                    let count = map.entry(surface_id.id).or_insert(0);
                    *count += 1;
                    *count
                });
                crate::wtrace!(crate::util::logging::FFI,
                    "FramePresented: surf={} buf={} released=true callbacks_flushed={} callback_count={} presented_total={} release_total={} pending_releases_before={}",
                    surface_id.id, buf_id.id, callback_count > 0, callback_count, presented_count, release_count, pending_releases);
            } else {
                crate::wtrace!(crate::util::logging::FFI,
                    "FramePresented: surf={} buf={}. No client_id, buffer NOT released",
                    surface_id.id, buf_id.id);
            }
        } else {
            crate::wtrace!(
                crate::util::logging::FFI,
                "FramePresented: surf={} buf=<none> callbacks_flushed={} callback_count={} presented_total={} pending_releases_before={}",
                surface_id.id,
                callback_count > 0,
                callback_count,
                presented_count,
                pending_releases
            );
        }

        if should_flush_frame_callbacks(FrameCallbackFlushPoint::FramePresented) {
            crate::wtrace!(
                crate::util::logging::FFI,
                "FramePresented callback flush: surf={} timestamp={} callbacks_before={}",
                surface_id.id,
                timestamp,
                callback_count
            );
            state.flush_frame_callbacks(surface_id.id, Some(timestamp));
        }
    }
    
    /// Get windows that need redraw
    pub fn poll_redraw_requests(&self) -> Vec<WindowId> {
        std::mem::take(&mut *self.pending_redraws.write_recover())
    }
    
    /// Notify that a buffer has been uploaded, providing the texture handle
    pub fn notify_buffer_uploaded(&self, buffer_id: BufferId, texture: TextureHandle) {
        self.textures.write_recover().insert(buffer_id.id, texture);
    }
    
    /// Notify that a texture has been released
    pub fn notify_texture_released(&self, texture: TextureHandle) {
        self.textures.write_recover().retain(|_, t| t.handle != texture.handle);
    }
    
    // =========================================================================
    // Window Management
    // =========================================================================

    /// Start a compositor-initiated (server) DnD grab.
    ///
    /// Called when the host OS reports a drag entered the Wayland window.
    /// Sets up Smithay's `ServerDnDGrab`, which intercepts pointer events
    /// and sends `wl_data_device.enter/motion/leave/drop` to the focused
    /// Wayland client.
    pub fn inject_drag_enter(&self, window_id: WindowId, x: f64, y: f64, mime_types: String) {
        if let Ok(mut state) = self.state.write() {
            // Store the offered MIME types so `ServerDndGrabHandler::send` can
            // serve the right content when the client calls `wl_data_offer.receive`.
            if let Ok(mut bridge) = state.dnd_bridge.write() {
                bridge.active_mime_types = mime_types.split(',').map(|s| s.trim().to_string()).collect();
                bridge.active = true;
                bridge.pending_drop_data = None;
                tracing::debug!(
                    "DnD enter: window={}, pos=({}, {}), mimes={:?}",
                    window_id.id, x, y, bridge.active_mime_types
                );
            }

            let dh = if let Some(ref d) = state.smithay_runtime.display_handle {
                d.clone()
            } else {
                return;
            };
            if let Some(ref seat) = state.smithay_runtime.seat.clone() {
                let focus = state.get_window(window_id.id.try_into().unwrap())
                    .and_then(|w| state.get_surface(w.read().unwrap().surface_id))
                    .and_then(|s| s.read().unwrap().resource.clone());

                if let Some(surface) = focus {
                    use smithay::input::pointer::GrabStartData as PointerGrabStartData;
                    use smithay::wayland::selection::data_device::{start_dnd, SourceMetadata};
                    use wayland_server::protocol::wl_data_device_manager::DndAction;

                    let parsed_mimes: Vec<String> = mime_types
                        .split(',')
                        .map(|s| s.trim().to_string())
                        .filter(|s| !s.is_empty())
                        .collect();

                    let metadata = SourceMetadata {
                        mime_types: parsed_mimes,
                        dnd_action: DndAction::Copy,
                    };

                    let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                    let time_ms = {
                        use std::time::{SystemTime, UNIX_EPOCH};
                        SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .map(|d| d.as_millis() as u32)
                            .unwrap_or(0)
                    };
                    let (sx, sy) = platform_pointer_surface_local(&state, window_id, x, y);

                    let start_data = PointerGrabStartData {
                        // The coordinate system is relative to (0.0, 0.0) for this window's surface
                        focus: Some((surface, (0.0, 0.0).into())),
                        button: 0x110, // BTN_LEFT — matches the button the grab tracks
                        location: (sx, sy).into(),
                    };

                    start_dnd(
                        &dh,
                        seat,
                        &mut *state,
                        serial,
                        Some(start_data),
                        None,
                        metadata,
                    );
                } else {
                    tracing::warn!("DnD enter: no surface found for window {}", window_id.id);
                }
            }
        }
        // Flush so the client receives the enter event + data offer immediately,
        // giving it a chance to call set_actions before the drop arrives.
        self.flush_clients();
    }

    /// Forward pointer motion during an active host DnD drag.
    ///
    /// The active `ServerDnDGrab` intercepts this and sends
    /// `wl_data_device.motion` to the client.
    pub fn inject_drag_motion(&self, window_id: WindowId, x: f64, y: f64) {
        let mut state = self.state.write_recover();
        
        let focus = state.get_window(window_id.id.try_into().unwrap())
            .and_then(|w| state.get_surface(w.read().unwrap().surface_id))
            .and_then(|s| s.read().unwrap().resource.clone());

        let seat = state.smithay_runtime.seat.clone().unwrap();
        let pointer = seat.get_pointer().unwrap();

        let time_ms = {
            use std::time::{SystemTime, UNIX_EPOCH};
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as u32)
                .unwrap_or(0)
        };
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();

        let (sx, sy) = platform_pointer_surface_local(&state, window_id, x, y);

        let event = smithay::input::pointer::MotionEvent {
            location: (sx, sy).into(),
            serial,
            time: time_ms,
        };

        if let Some(surface) = focus {
            pointer.motion(&mut *state, Some((surface, (0.0, 0.0).into())), &event);
        } else {
            pointer.motion(&mut *state, None, &event);
        }
        drop(state);
        self.flush_clients();
    }

    /// Complete the host DnD drop.
    ///
    /// Stores the drop data (URI list, text, etc.) in `DndBridge` so that
    /// `ServerDndGrabHandler::send` can write it into the client's fd when
    /// the client calls `wl_data_offer.receive`.  Then releases the virtual
    /// button to trigger Smithay's `ServerDnDGrab::unset` → `drop()`.
    pub fn inject_drag_drop(&self, _window_id: WindowId, data: String) {
        tracing::debug!("DnD drop: data len={}", data.len());
        let mut state = self.state.write_recover();
        if let Ok(mut bridge) = state.dnd_bridge.write() {
            bridge.pending_drop_data = Some(data);
        }
        if let Some(seat) = state.smithay_runtime.seat.clone() {
            if let Some(pointer) = seat.get_pointer() {
                let time_ms = {
                    use std::time::{SystemTime, UNIX_EPOCH};
                    SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map(|d| d.as_millis() as u32)
                        .unwrap_or(0)
                };
                let serial = smithay::utils::SERIAL_COUNTER.next_serial();
                let event = smithay::input::pointer::ButtonEvent {
                    button: 0x110, // BTN_LEFT — must match start_data.button
                    state: smithay::backend::input::ButtonState::Released,
                    serial,
                    time: time_ms,
                };
                pointer.button(&mut *state, &event);
            }
        }
        drop(state);
        self.flush_clients();
    }

    /// Cancel/leave a host DnD drag without dropping.
    pub fn inject_drag_leave(&self, _window_id: WindowId) {
        let mut state = self.state.write_recover();
        if let Ok(mut bridge) = state.dnd_bridge.write() {
            bridge.active = false;
        }

        let seat = state.smithay_runtime.seat.clone().unwrap();
        let pointer = seat.get_pointer().unwrap();
        let time_ms = {
            use std::time::{SystemTime, UNIX_EPOCH};
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as u32)
                .unwrap_or(0)
        };
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();

        // Send a motion event with no focus to make the grab send a leave event to the client
        let motion_event = smithay::input::pointer::MotionEvent {
            location: (0.0, 0.0).into(),
            serial,
            time: time_ms,
        };
        pointer.motion(&mut *state, None, &motion_event);

        // Then release the button to unset the grab
        let rel_event = smithay::input::pointer::ButtonEvent {
            button: 0x110,
            state: smithay::backend::input::ButtonState::Released,
            serial: smithay::utils::SERIAL_COUNTER.next_serial(),
            time: time_ms,
        };
        pointer.button(&mut *state, &rel_event);

        drop(state);
        self.flush_clients();
    }

    pub fn resize_window(&self, window_id: WindowId, width: u32, height: u32) {
        if !self.is_running() {
            return;
        }
        if width == 0 || height == 0 {
            crate::wlog!(
                crate::util::logging::FFI,
                "Window resize ignored: window={} invalid size={}x{}",
                window_id.id,
                width,
                height
            );
            return;
        }

        let wid = window_id.id as u32;

        // Find the specific toplevel associated with this window.
        let target_toplevel: Option<(wayland_server::backend::ClientId, u32)> = {
            let state = self.state.read_recover();
            state
                .xdg_toplevel_key_for_window(wid)
                .or_else(|| {
                    state
                        .xdg
                        .toplevels
                        .iter()
                        .find(|(_, data)| data.window_id == wid)
                        .map(|(key, _)| key.clone())
                })
        };

        // Do NOT change the global output size here *for xdg_toplevels*.  The output
        // represents the physical display (set by setOutputWidth:
        // height:scale: on the platform side).  Changing it per-
        // window would broadcast wl_output.mode to all clients and
        // cause unrelated windows to resize in sympathy.  The
        // toplevel configure below carries the correct per-window
        // dimensions to the target client.
        // 
        // HOWEVER: fullscreen_shell surfaces do not receive xdg_toplevel.configure
        // events. Their only way to know their sizing is via global wl_output mode.
        // If a fullscreen_shell surface is resized (e.g. nested compositor running
        // in a Force SSD window), we MUST update the global output mode so it
        // readjusts its virtual display bounds.
        let mut is_fullscreen_shell = false;
        if target_toplevel.is_none() {
            let state = self.state.read_recover();
            is_fullscreen_shell = state.ext.fullscreen_shell.presented_window_id == Some(wid);
        }

        if let Some(tid) = target_toplevel {
            // #111: push per-window wl_output/xdg_output in lockstep with
            // xdg_toplevel.configure. Nested compositors (niri) size their
            // framebuffer from output mode; updating only on txn-settle made
            // mode lag/lead the host and flash before/after sizes mid-drag.
            // set_output_geometry_for_window is per-client and deduped.
            // Nested weston/niri follow xdg in points at scale 1. Direct
            // clients keep the global HiDPI scale.
            let scale = {
                let global = {
                    let cur = self.output_size.read_recover();
                    cur.2
                };
                let state = self.state.read_recover();
                let app_id = state
                    .get_window(wid)
                    .map(|w| w.read_recover().app_id.clone())
                    .unwrap_or_default();
                nested_compositor_output_scale(&app_id, global)
            };
            self.set_output_geometry_for_window(window_id, width, height, scale);

            crate::wlog!(crate::util::logging::FFI,
                "Window resize: window={} {}x{}, reconfiguring toplevel {:?}",
                wid, width, height, tid.1);

            let mut state = self.state.write_recover();
            let sent_serial = state.send_toplevel_configure(tid.0.clone(), tid.1, width, height);
            if let Some(serial) = sent_serial {
                let txn = self.begin_resize_transaction(
                    WindowId { id: window_id.id },
                    serial,
                    WindowSizeCause::HostConfigure,
                    Size { width, height },
                    GeometrySizeKind::Content,
                );
                if let Some(window) = state.get_window(wid) {
                    let mut window = window.write_recover();
                    window.width = width as i32;
                    window.height = height as i32;
                    let decision = window
                        .size_authority
                        .clone()
                        .on_host_resize_request(width, height, txn.id)
                        .authority
                        .on_configure_sent(serial);
                    window.size_authority = decision;
                }
                crate::wlog!(
                    crate::util::logging::FFI,
                    "Resize transaction started: id={} window={} serial={} requested={}x{} size_auth=Host",
                    txn.id,
                    window_id.id,
                    txn.configure_serial,
                    txn.requested_size.width,
                    txn.requested_size.height
                );
            } else {
                // Configure not sent yet. Still mark host authoritative so
                // lagging commits cannot yank size while we wait.
                if let Some(window) = state.get_window(wid) {
                    let mut window = window.write_recover();
                    window.width = width as i32;
                    window.height = height as i32;
                    let decision = window
                        .size_authority
                        .clone()
                        .on_host_resize_request(width, height, 0);
                    window.size_authority = decision.authority;
                }
                crate::wtrace!(
                    crate::util::logging::FFI,
                    "Window resize: configure deferred until client acks pending xdg_surface serial (window={} {}x{})",
                    window_id.id,
                    width,
                    height
                );
            }
        } else if is_fullscreen_shell {
            crate::wlog!(crate::util::logging::FFI,
                "Window resize: window={} {}x{}, fullscreen_shell - updating global output mode",
                wid, width, height);
            {
                let state = self.state.write_recover();
                if let Some(window) = state.get_window(wid) {
                    let mut window = window.write_recover();
                    window.width = width as i32;
                    window.height = height as i32;
                    window.size_authority = window
                        .size_authority
                        .clone()
                        .on_host_resize_request(width, height, 0)
                        .authority;
                }
            }
            let scale = {
                let cur = self.output_size.read_recover();
                cur.2
            };
            self.set_output_size(width, height, scale);
        } else {
            crate::wlog!(crate::util::logging::FFI,
                "Window resize: window={} {}x{}, no toplevel/fullscreen_shell found to reconfigure",
                wid, width, height);
            let state = self.state.write_recover();
            if let Some(window) = state.get_window(wid) {
                let mut window = window.write_recover();
                window.width = width as i32;
                window.height = height as i32;
                window.size_authority = window
                    .size_authority
                    .clone()
                    .on_host_resize_request(width, height, 0)
                    .authority;
            }
        }
    }

    /// Begin an interactive resize session (host SSD live-drag or CSD
    /// `xdg_toplevel.resize` grab). Sets `xdg_toplevel.state.resizing` on the
    /// next configure and keeps it set for mid-drag `resize_window` calls.
    pub fn begin_interactive_resize(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        let wid = window_id.id as u32;
        let (tid, width, height, already) = {
            let state = self.state.read_recover();
            let Some(tid) = state.xdg_toplevel_key_for_window(wid).or_else(|| {
                state
                    .xdg
                    .toplevels
                    .iter()
                    .find(|(_, data)| data.window_id == wid)
                    .map(|(key, _)| key.clone())
            }) else {
                return;
            };
            let Some(tl) = state.xdg.toplevels.get(&tid) else {
                return;
            };
            let w = if tl.width > 0 {
                tl.width
            } else if let Some(window) = state.get_window(wid) {
                window.read_recover().width.max(0) as u32
            } else {
                0
            };
            let h = if tl.height > 0 {
                tl.height
            } else if let Some(window) = state.get_window(wid) {
                window.read_recover().height.max(0) as u32
            } else {
                0
            };
            (tid, w, h, tl.interactive_resize)
        };
        if already {
            return;
        }
        crate::wlog!(
            crate::util::logging::FFI,
            "begin_interactive_resize: window={} size={}x{}",
            wid,
            width,
            height
        );
        {
            let mut state = self.state.write_recover();
            if let Some(tl) = state.xdg.toplevels.get_mut(&tid) {
                tl.interactive_resize = true;
            }
            if width > 0 && height > 0 {
                let sent_serial = state.send_toplevel_configure(tid.0.clone(), tid.1, width, height);
                if let Some(serial) = sent_serial {
                    let txn = self.begin_resize_transaction(
                        window_id,
                        serial,
                        WindowSizeCause::HostConfigure,
                        Size { width, height },
                        GeometrySizeKind::Content,
                    );
                    if let Some(window) = state.get_window(wid) {
                        let mut window = window.write_recover();
                        let decision = window
                            .size_authority
                            .clone()
                            .on_host_resize_request(width, height, txn.id)
                            .authority
                            .on_configure_sent(serial);
                        window.size_authority = decision;
                    }
                }
            }
        }
        self.flush_clients();
    }

    /// End an interactive resize session: clear `xdg_toplevel.state.resizing`
    /// and emit a settle configure (even when size is unchanged). `width` /
    /// `height` of 0 keep the last toplevel size.
    pub fn end_interactive_resize(&self, window_id: WindowId, width: u32, height: u32) {
        if !self.is_running() {
            return;
        }
        let wid = window_id.id as u32;
        let (tid, final_w, final_h, was_active) = {
            let state = self.state.read_recover();
            let Some(tid) = state.xdg_toplevel_key_for_window(wid).or_else(|| {
                state
                    .xdg
                    .toplevels
                    .iter()
                    .find(|(_, data)| data.window_id == wid)
                    .map(|(key, _)| key.clone())
            }) else {
                return;
            };
            let Some(tl) = state.xdg.toplevels.get(&tid) else {
                return;
            };
            let w = if width > 0 {
                width
            } else if tl.width > 0 {
                tl.width
            } else if let Some(window) = state.get_window(wid) {
                window.read_recover().width.max(1) as u32
            } else {
                1
            };
            let h = if height > 0 {
                height
            } else if tl.height > 0 {
                tl.height
            } else if let Some(window) = state.get_window(wid) {
                window.read_recover().height.max(1) as u32
            } else {
                1
            };
            (tid, w.max(1), h.max(1), tl.interactive_resize)
        };
        crate::wlog!(
            crate::util::logging::FFI,
            "end_interactive_resize: window={} size={}x{} was_active={}",
            wid,
            final_w,
            final_h,
            was_active
        );
        {
            let mut state = self.state.write_recover();
            if let Some(tl) = state.xdg.toplevels.get_mut(&tid) {
                tl.interactive_resize = false;
            }
            let app_id = state
                .get_window(wid)
                .map(|w| w.read_recover().app_id.clone())
                .unwrap_or_default();
            let global = {
                let cur = self.output_size.read_recover();
                cur.2
            };
            let scale = nested_compositor_output_scale(&app_id, global);
            // Keep per-window output geometry in lockstep with the settle
            // configure (nested compositors size from output mode).
            drop(state);
            self.set_output_geometry_for_window(window_id, final_w, final_h, scale);
            let mut state = self.state.write_recover();
            let sent_serial =
                state.send_toplevel_configure(tid.0.clone(), tid.1, final_w, final_h);
            if let Some(serial) = sent_serial {
                let txn = self.begin_resize_transaction(
                    window_id,
                    serial,
                    WindowSizeCause::HostConfigure,
                    Size {
                        width: final_w,
                        height: final_h,
                    },
                    GeometrySizeKind::Content,
                );
                if let Some(window) = state.get_window(wid) {
                    let mut window = window.write_recover();
                    window.width = final_w as i32;
                    window.height = final_h as i32;
                    let decision = window
                        .size_authority
                        .clone()
                        .on_host_resize_request(final_w, final_h, txn.id)
                        .authority
                        .on_configure_sent(serial);
                    window.size_authority = decision;
                }
            } else if let Some(window) = state.get_window(wid) {
                let mut window = window.write_recover();
                window.width = final_w as i32;
                window.height = final_h as i32;
                window.size_authority = window
                    .size_authority
                    .clone()
                    .on_host_resize_request(final_w, final_h, 0)
                    .authority;
            }
        }
        self.flush_clients();
    }

    /// Native host entered or left fullscreen. Update xdg toplevel state.
    pub fn apply_host_window_fullscreen(
        &self,
        window_id: WindowId,
        fullscreen: bool,
        width: u32,
        height: u32,
    ) {
        if !self.is_running() {
            return;
        }
        let wid = window_id.id as u32;
        let sent = {
            let mut state = self.state.write_recover();
            state.apply_host_window_fullscreen(wid, fullscreen, width, height)
        };
        // Host-initiated state changes are resize requests too: open a
        // transaction so the resulting WindowSizeChanged carries the serial
        // and transaction id instead of classifying as an untracked
        // ClientCommit (which platform bridges ignore after first sync).
        if let Some((serial, w, h)) = sent {
            self.begin_resize_transaction(
                window_id,
                serial,
                WindowSizeCause::HostConfigure,
                Size { width: w, height: h },
                GeometrySizeKind::Content,
            );
        }
    }

    /// Native host zoomed or unzoomed. Update xdg toplevel maximized state.
    pub fn apply_host_window_maximized(
        &self,
        window_id: WindowId,
        maximized: bool,
        width: u32,
        height: u32,
    ) {
        if !self.is_running() {
            return;
        }
        let wid = window_id.id as u32;
        let sent = {
            let mut state = self.state.write_recover();
            state.apply_host_window_maximized(wid, maximized, width, height)
        };
        if let Some((serial, w, h)) = sent {
            self.begin_resize_transaction(
                window_id,
                serial,
                WindowSizeCause::HostConfigure,
                Size { width: w, height: h },
                GeometrySizeKind::Content,
            );
        }
    }

    /// Update compositor-side window dimensions without sending configure/output events.
    ///
    /// Used by Linux/GTK when a fullscreen-shell companion surface is embedded inside
    /// another host window. We want scene geometry to track the host allocation, but
    /// must avoid driving a second resize protocol path for the companion itself.
    pub fn set_window_size_local(&self, window_id: WindowId, width: u32, height: u32) {
        if !self.is_running() {
            return;
        }
        if width == 0 || height == 0 {
            crate::wlog!(
                crate::util::logging::FFI,
                "Local window size sync ignored: window={} invalid size={}x{}",
                window_id.id,
                width,
                height
            );
            return;
        }

        let wid = window_id.id as u32;
        let mut state = self.state.write_recover();
        if let Some(window) = state.get_window(wid) {
            let mut window = window.write_recover();
            window.width = width as i32;
            window.height = height as i32;
            crate::wlog!(
                crate::util::logging::FFI,
                "Local window size sync: window={} {}x{}",
                window_id.id,
                width,
                height
            );
        }
    }

    /// Set window activation state.
    ///
    /// When `send_configure` is false the flag is stored but no
    /// xdg_toplevel/xdg_surface configure pair is emitted.  The caller
    /// is expected to trigger a configure shortly after (e.g. via
    /// `resize_window`) which will pick up the new activation state.
    pub fn set_window_activated(&self, window_id: WindowId, active: bool, send_configure: bool) {
        if !self.is_running() {
            return;
        }

        crate::wlog!(crate::util::logging::FFI, "Set window activation: window={} active={}", window_id.id, active);

        let mut state = self.state.write_recover();
        let wid = window_id.id as u32;

        // Update core window state
        if let Some(window) = state.get_window(wid) {
             let mut window = window.write_recover();
             window.activated = active;
        }

        // Find associated surface and toplevel
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &w)| w == wid)
            .map(|(s, _)| *s);

        if let Some(sid) = surface_id {
             let toplevel_id = state.xdg.toplevels.iter()
                 .find(|(_, data)| data.surface_id == sid)
                 .map(|(id, _)| id.clone());

             if let Some(tid) = toplevel_id {
                 let (mut w, mut h) = if let Some(td) = state.xdg.toplevels.get_mut(&tid) {
                     td.activated = active;
                     (td.width, td.height)
                 } else {
                     return;
                 };

                 if w == 0 && h == 0 {
                     if let Some(window) = state.get_window(wid) {
                         let ww = window.read_recover();
                         if ww.width > 0 && ww.height > 0 {
                             w = ww.width as u32;
                             h = ww.height as u32;
                         }
                     }
                 }

                 if send_configure {
                     if w == 0 && h == 0 {
                         crate::wlog!(
                             crate::util::logging::FFI,
                             "Set window activation: skip configure (no size yet) window={}",
                             window_id.id
                         );
                     } else {
                         state.send_toplevel_configure(tid.0.clone(), tid.1, w, h);
                     }
                 }
             }
        }
    }

    // =========================================================================
    // Input Injection
    // =========================================================================

    /// Resolve the topmost window under compositor-global pointer coordinates.
    pub fn window_id_at_point(&self, x: f64, y: f64) -> Option<WindowId> {
        if !self.is_running() {
            return None;
        }

        let mut state = self.state.write_recover();
        state
            .find_surface_at(x, y)
            .and_then(|(surface_id, _, _)| state.surface_to_window.get(&surface_id).copied())
            .map(|wid| WindowId { id: wid as u64 })
    }

    /// Inject pointer motion event
    pub fn inject_pointer_motion(
        &self,
        window_id: WindowId,
        x: f64,
        y: f64,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let mut state = self.state.write_recover();
        state.seat.cleanup_resources();
        
        let (sx, sy) = platform_pointer_surface_local(&state, window_id, x, y);

        state.seat.pointer.x = sx;
        state.seat.pointer.y = sy;

        // Auto-correct focus if the platform is routing events for a
        // different window than the one currently focused.
        ensure_pointer_focus(&mut state, window_id, &|| self.next_serial());
        let (lx, ly) = (sx, sy);
        state.seat.pointer.focus_x = lx;
        state.seat.pointer.focus_y = ly;

        deliver_pointer_motion_to_clients(&mut *state, timestamp_ms, lx, ly);
    }
    
    /// Inject pointer button event
    pub fn inject_pointer_button(
        &self,
        window_id: WindowId,
        button: PointerButton,
        state: ButtonState,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let wl_state = match state {
            ButtonState::Released => wayland_server::protocol::wl_pointer::ButtonState::Released,
            ButtonState::Pressed => wayland_server::protocol::wl_pointer::ButtonState::Pressed,
        };
        
        let button_code = match button {
            PointerButton::Left => 0x110,   // BTN_LEFT
            PointerButton::Right => 0x111,  // BTN_RIGHT
            PointerButton::Middle => 0x112, // BTN_MIDDLE
            PointerButton::Back => 0x116,   // BTN_BACK
            PointerButton::Forward => 0x115, // BTN_FORWARD
            PointerButton::Other(b) => b,
        };

        let mut state = self.state.write_recover();
        state.seat.cleanup_resources();

        // Auto-correct pointer focus to the window the platform says
        // this click targets.
        ensure_pointer_focus(&mut state, window_id, &|| self.next_serial());

        // Weston desktop-shell tracks the launcher via wl_pointer motion +
        // button in the same frame; sync position immediately before click.
        let motion_serial = self.next_serial();
        let motion_ts = timestamp_ms.saturating_sub(1);
        dispatch_pointer_motion_at_seat(&mut state, motion_ts, motion_serial);
        
        match wl_state {
            wayland_server::protocol::wl_pointer::ButtonState::Pressed => {
                state.seat.pointer.button_count += 1;
            },
            wayland_server::protocol::wl_pointer::ButtonState::Released => {
                state.seat.pointer.button_count = state.seat.pointer.button_count.saturating_sub(1);
            },
            _ => {}
        }

        let focused_client = state.focused_pointer_client();
        if let Some(client) = focused_client.as_ref() {
            let sent = smithay_send_pointer_button(
                &state,
                client,
                serial,
                timestamp_ms,
                button_code,
                wl_state,
            );
            if sent > 0 {
                smithay_send_pointer_frame(&state, client);
                return;
            }
        }
        if smithay_dispatch_pointer_button(
            &mut *state,
            serial,
            timestamp_ms,
            button_code,
            wl_state,
        ) {
            return;
        }
        if !state.seat.pointer.resources.is_empty() {
            state.seat.broadcast_pointer_button(
                serial,
                timestamp_ms,
                button_code,
                wl_state,
                focused_client.as_ref(),
            );
            state.seat.broadcast_pointer_frame(focused_client.as_ref());
        }
    }
    
    /// Inject pointer axis (scroll) event
    pub fn inject_pointer_axis(
        &self,
        window_id: WindowId,
        axis: PointerAxis,
        value: f64,
        discrete: i32,
        source: AxisSource,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        state.seat.cleanup_resources();

        // Scroll is delivered at the virtual cursor. Ensure focus and sync
        // motion first (same pattern as pointer buttons).
        ensure_pointer_focus(&mut state, window_id, &|| self.next_serial());
        dispatch_pointer_motion_at_seat(&mut state, timestamp_ms.saturating_sub(1), 0);

        let focused_client = state.focused_pointer_client();
        let wl_axis = match axis {
            PointerAxis::Vertical => wayland_server::protocol::wl_pointer::Axis::VerticalScroll,
            PointerAxis::Horizontal => wayland_server::protocol::wl_pointer::Axis::HorizontalScroll,
        };
        let wl_source = match source {
            AxisSource::Wheel => wayland_server::protocol::wl_pointer::AxisSource::Wheel,
            AxisSource::Finger => wayland_server::protocol::wl_pointer::AxisSource::Finger,
            AxisSource::Continuous => wayland_server::protocol::wl_pointer::AxisSource::Continuous,
            AxisSource::WheelTilt => wayland_server::protocol::wl_pointer::AxisSource::WheelTilt,
        };

        // Prefer explicit client_pointers delivery (matches inject_pointer_button).
        // smithay pointer.axis() only reaches the grab's focused surface; our
        // motion path does not update that focus, so axis would be dropped.
        if let Some(client) = focused_client.as_ref() {
            let sent = smithay_send_pointer_axis(
                &state,
                client,
                timestamp_ms,
                wl_axis,
                value,
                wl_source,
                discrete,
            );
            if sent > 0 {
                smithay_send_pointer_frame(&state, client);
                return;
            }
        }

        if let Some(pointer) = state
            .smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_pointer())
        {
            // Last resort: sync smithay focus then use the grab path.
            let _ = smithay_dispatch_pointer_motion(
                &mut *state,
                timestamp_ms.saturating_sub(1),
                self.next_serial(),
            );
            let smithay_axis = match axis {
                PointerAxis::Vertical => smithay::backend::input::Axis::Vertical,
                PointerAxis::Horizontal => smithay::backend::input::Axis::Horizontal,
            };
            let smithay_source = match source {
                AxisSource::Wheel => smithay::backend::input::AxisSource::Wheel,
                AxisSource::Finger => smithay::backend::input::AxisSource::Finger,
                AxisSource::Continuous => smithay::backend::input::AxisSource::Continuous,
                AxisSource::WheelTilt => smithay::backend::input::AxisSource::WheelTilt,
            };
            let mut frame = smithay::input::pointer::AxisFrame::new(timestamp_ms)
                .source(smithay_source)
                .value(smithay_axis, value);
            if discrete != 0 {
                frame = frame.v120(smithay_axis, discrete);
            }
            pointer.axis(&mut *state, frame);
            pointer.frame(&mut *state);
            return;
        }
        state.seat.broadcast_pointer_axis(
            timestamp_ms,
            wl_axis,
            value,
            wl_source,
            focused_client.as_ref(),
        );
        state.seat.broadcast_pointer_frame(focused_client.as_ref());
    }
    
    /// Inject pointer frame event
    pub fn inject_pointer_frame(&self, _window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        if let Some(pointer) = state
            .smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_pointer())
        {
            pointer.frame(&mut *state);
            return;
        }
        state.seat.broadcast_pointer_frame(None);
    }

    /// Push text copied on the native platform (NSPasteboard / UIPasteboard /
    /// ClipboardManager) into the compositor so Wayland clients can paste it.
    /// Makes the compositor the active `wl_data_device` selection source;
    /// `SelectionHandler::send_selection` serves this text out when a client
    /// requests it. See `ClipboardBridge`.
    pub fn set_clipboard_text(&self, text: String) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        if let Ok(mut bridge) = state.clipboard_bridge.write() {
            bridge.outgoing_to_client = Some(text);
        }
        let Some(dh) = state.smithay_runtime.display_handle.clone() else {
            return;
        };
        let Some(seat) = state.smithay_runtime.seat.clone() else {
            return;
        };
        let mime_types = vec![
            "text/plain;charset=utf-8".to_string(),
            "text/plain".to_string(),
            "UTF8_STRING".to_string(),
        ];
        smithay::wayland::selection::data_device::set_data_device_selection(
            &dh, &seat, mime_types, (),
        );
    }

    /// Pop the most recent text a Wayland client copied to the clipboard
    /// (queued by `SelectionHandler::new_selection`), clearing it. Returns
    /// `None` if nothing new has been copied since the last poll. The
    /// native platform layer should push the result into its pasteboard.
    pub fn poll_clipboard_text(&self) -> Option<String> {
        if !self.is_running() {
            return None;
        }
        let state = self.state.write_recover();
        state
            .clipboard_bridge
            .write()
            .ok()
            .and_then(|mut bridge| bridge.pending_from_client.take())
    }

    /// Inject pointer enter event
    pub fn inject_pointer_enter(
        &self,
        window_id: WindowId,
        x: f64,
        y: f64,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write_recover();
        state.seat.cleanup_resources();
        
        let (sx, sy) = platform_pointer_surface_local(&state, window_id, x, y);
        state.seat.pointer.x = sx;
        state.seat.pointer.y = sy;

        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            if state.seat.pointer.button_count > 0 {
                return;
            }

            state.seat.pointer.focus = Some(sid);
            let (lx, ly) = (sx, sy);
            state.seat.pointer.focus_x = lx;
            state.seat.pointer.focus_y = ly;
            state.seat.pointer.last_enter_serial = serial;

            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                let surface = surface.read_recover();
                if let Some(res) = &surface.resource {
                    if let Some(client) = res.client() {
                        let ptr_count = smithay_pointer_count(&state, &client);
                        let sent =
                            smithay_send_pointer_enter(&state, &client, serial, res, lx, ly);
                        if sent > 0 {
                            smithay_send_pointer_frame(&state, &client);
                        } else {
                            crate::wlog!(
                                crate::util::logging::FFI,
                                "pointer enter: no smithay wl_pointer for client (bound={}) surface={}",
                                ptr_count,
                                sid
                            );
                            state.seat.broadcast_pointer_enter(serial, res, lx, ly);
                        }
                    }
                    deliver_pointer_motion_to_clients(&mut *state, timestamp_ms, lx, ly);
                }
            }
        }
    }
    
    /// Inject pointer leave event
    pub fn inject_pointer_leave(&self, window_id: WindowId, _timestamp_ms: u32) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write_recover();
        
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            if state.seat.pointer.button_count > 0 {
                return;
            }

            state.seat.pointer.focus = None;

            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                let surface = surface.read_recover();
                if let Some(res) = &surface.resource {
                    if let Some(client) = res.client() {
                        if smithay_send_pointer_leave(&state, &client, serial, res) == 0 {
                            state.seat.broadcast_pointer_leave(serial, res);
                        }
                    }
                }
            }
        }
    }

    // ... (key injection methods also need similar fix) ...


    
    /// Inject keyboard key event.
    ///
    /// Processes the key through the server-side XKB state machine so that
    /// modifier tracking (pressed_keys, depressed/latched/locked) stays in
    /// sync.  If the key event causes a modifier change, a
    /// wl_keyboard.modifiers event is broadcast automatically.
    pub fn inject_key(&self, keycode: u32, key_state: KeyState, timestamp_ms: u32) {
        if !self.is_running() {
            return;
        }
        
        // Pre-generate both serials outside the state lock to avoid
        // holding the state RwLock while locking the compositor mutex.
        let key_serial = self.next_serial();
        let mod_serial = self.next_serial();
        let pressed = matches!(key_state, KeyState::Pressed);
        let wl_state = match key_state {
            KeyState::Released => wayland_server::protocol::wl_keyboard::KeyState::Released,
            KeyState::Pressed => wayland_server::protocol::wl_keyboard::KeyState::Pressed,
        };
        
        let mut state = self.state.write_recover();
        if let Some(keyboard) = state
            .smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_keyboard())
        {
            // Every native layer (macOS/iOS/tvOS/visionOS/watchOS/Android/X11)
            // emits Linux evdev scancodes. Smithay's keyboard.input() expects
            // the XKB keycode domain (evdev + 8): KeysymHandle::raw_code() is
            // documented as "raw code in X keycode system (shifted by 8)" and
            // Smithay sends raw_code()-8 to the client. So the +8 offset is
            // unconditional on ALL platforms (previously macOS-only, which left
            // every other platform off-by-8 and mapping the wrong symbols).
            let smithay_keycode = keycode.saturating_add(8);

            let smithay_state = match key_state {
                KeyState::Released => smithay::backend::input::KeyState::Released,
                KeyState::Pressed => smithay::backend::input::KeyState::Pressed,
            };
            keyboard.input(
                &mut *state,
                smithay_keycode.into(),
                smithay_state,
                key_serial.into(),
                timestamp_ms,
                |_, _, _| smithay::input::keyboard::FilterResult::<()>::Forward,
            );
            drop(state);
            self.flush_clients();
            return;
        }
        state.seat.cleanup_resources();
        
        // Process through XKB to update server-side modifier state and
        // pressed_keys.  This is essential for correct Shift/Ctrl/Alt/Super
        // tracking. Without it the server's cached modifier mask would
        // never update from key events alone, and capital letters (among
        // other shifted symbols) would not be recognised.
        let mods_changed = state.seat.keyboard.process_key(keycode, pressed)
            .map_or(false, |r| r.modifiers_changed);
        
        let focused_client = state.focused_keyboard_client();
        state.seat.broadcast_key(key_serial, timestamp_ms, keycode, wl_state, focused_client.as_ref());
        
        // If XKB detected a modifier change, broadcast the new state so
        // the client's modifier mask is always up to date.
        if mods_changed {
            let (d, la, lo, g) = (
                state.seat.keyboard.mods_depressed,
                state.seat.keyboard.mods_latched,
                state.seat.keyboard.mods_locked,
                state.seat.keyboard.mods_group,
            );
            state.seat.broadcast_modifiers(mod_serial, d, la, lo, g, focused_client.as_ref());
        }
    }
    
    /// Inject keyboard modifiers directly (e.g. from platform modifier
    /// flags).  Also keeps the server-side XKB state in sync via
    /// `update_mask`.
    pub fn inject_modifiers(&self, modifiers: KeyboardModifiers) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write_recover();
        if let Some(keyboard) = state
            .smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_keyboard())
        {
            let mut smithay_mods = keyboard.modifier_state();
            smithay_mods.serialized.depressed = modifiers.mods_depressed;
            smithay_mods.serialized.latched = modifiers.mods_latched;
            smithay_mods.serialized.locked = modifiers.mods_locked;
            smithay_mods.serialized.layout_effective = modifiers.group;
            let _ = keyboard.set_modifier_state(smithay_mods);
            return;
        }
        state.seat.cleanup_resources();
        
        state.seat.keyboard.mods_depressed = modifiers.mods_depressed;
        state.seat.keyboard.mods_latched = modifiers.mods_latched;
        state.seat.keyboard.mods_locked = modifiers.mods_locked;
        state.seat.keyboard.mods_group = modifiers.group;
        
        // Keep the XKB state machine in sync so that subsequent
        // process_key() calls see the correct modifier baseline.
        if let Some(xkb) = &state.seat.keyboard.xkb_state {
            if let Ok(mut xkb_state) = xkb.lock() {
                xkb_state.update_mask(
                    modifiers.mods_depressed,
                    modifiers.mods_latched,
                    modifiers.mods_locked,
                    modifiers.group,
                );
            }
        }
        
        let focused_client = state.focused_keyboard_client();
        state.seat.broadcast_modifiers(serial, modifiers.mods_depressed, modifiers.mods_latched, modifiers.mods_locked, modifiers.group, focused_client.as_ref());
    }
    
    /// Inject keyboard enter event
    pub fn inject_keyboard_enter(&self, window_id: WindowId, pressed_keys: Vec<u32>) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write_recover();
        
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            crate::wlog!(crate::util::logging::FFI, "Keyboard enter: window={}, surface={}", 
                window_id.id, sid);
            
            // DIAGNOSTIC: Log keyboard state
            let smithay_keyboard_count = usize::from(
                state
                    .smithay_runtime
                    .seat
                    .as_ref()
                    .and_then(|seat| seat.get_keyboard())
                    .is_some(),
            );
            crate::wlog!(
                crate::util::logging::FFI,
                "Keyboards available: legacy={} smithay={}",
                state.seat.keyboard.resources.len(),
                smithay_keyboard_count
            );
            for (idx, kbd) in state.seat.keyboard.resources.iter().enumerate() {
                crate::wlog!(crate::util::logging::FFI, "  Keyboard {}: alive={}, version={}", 
                    idx, kbd.is_alive(), kbd.version());
            }
            
            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                 let surface = surface.read_recover();
                 if let Some(res) = &surface.resource {
                     crate::wlog!(crate::util::logging::FFI, "Broadcasting keyboard enter to surface {} ({} keyboards bound)", sid, state.seat.keyboard.resources.len());
                     state.seat.keyboard.pressed_keys = pressed_keys.clone();
                     state.seat.keyboard.focus = Some(sid);
                     if let Some(keyboard) = state
                         .smithay_runtime
                         .seat
                         .as_ref()
                         .and_then(|seat| seat.get_keyboard())
                     {
                         keyboard.set_focus(&mut *state, Some(res.clone()), serial.into());
                     } else {
                         state.seat.broadcast_keyboard_enter(serial, res, &pressed_keys);
                     }

                     // Also send text-input-v3 enter so IME / emoji
                     // commits reach this surface's text-input instance.
                     state.ext.text_input.enter(res, Some(sid));
                 } else {
                 crate::wlog!(crate::util::logging::FFI, "WARNING: Surface {} has no resource for keyboard enter", 
                     sid);
                 }
            } else {
                crate::wlog!(crate::util::logging::FFI, "WARNING: Surface {} not found for keyboard enter", 
                    sid);
            }
        } else {
            state.pending_keyboard_focus_window = Some(window_id.id);
            crate::wlog!(
                crate::util::logging::FFI,
                "Deferring keyboard enter for window {} until surface is registered",
                window_id.id
            );
        }
    }
    
    /// Inject keyboard leave event
    pub fn inject_keyboard_leave(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let had_keyboard_focus = {
            let mut state = self.state.write_recover();
            
            let surface_id = state.surface_to_window.iter()
                .find(|(_, &wid)| wid as u64 == window_id.id)
                .map(|(sid, _)| *sid);
                
            if let Some(sid) = surface_id {
                let had = state.seat.keyboard.focus == Some(sid);
                if had {
                    if let Some(surface) = state.surfaces.get(&sid).cloned() {
                        let surface = surface.read_recover();
                        if let Some(res) = &surface.resource {
                            state.ext.text_input.leave(res);
                            if let Some(keyboard) = state
                                .smithay_runtime
                                .seat
                                .as_ref()
                                .and_then(|seat| seat.get_keyboard())
                            {
                                keyboard.set_focus(&mut *state, None, serial.into());
                            } else {
                                state.seat.broadcast_keyboard_leave(serial, res);
                            }
                        }
                    }
                    state.seat.keyboard.focus = None;
                    state.focus.set_keyboard_focus(None);
                }
                had
            } else {
                false
            }
        };

        if had_keyboard_focus {
            let mut windows = self.ffi_windows.write_recover();
            if let Some(info) = windows.get_mut(&window_id.id) {
                if info.activated {
                    info.activated = false;
                    drop(windows);
                    self.pending_window_events.write_recover().push(
                        WindowEvent::Deactivated { window_id }
                    );
                }
            }
        }
    }

    /// Move keyboard focus to a host window's toplevel surface: `wl_keyboard.leave` on the
    /// previous focus (if any), then `enter` with currently pressed keys. Updates activation
    /// state to match (nested compositor / platform parity with macOS `becomeKeyWindow`).
    pub fn apply_keyboard_focus_for_window(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }

        let leave_serial = self.next_serial();
        let enter_serial = self.next_serial();

        let mut state = self.state.write_recover();
        state.seat.cleanup_resources();

        let new_sid = match state
            .surface_to_window
            .iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid)
        {
            Some(s) => s,
            None => {
                crate::wlog!(
                    crate::util::logging::FFI,
                    "apply_keyboard_focus: no surface for window {}",
                    window_id.id
                );
                return;
            }
        };

        if state.seat.keyboard.focus == Some(new_sid) {
            return;
        }

        if let Some(old_sid) = state.seat.keyboard.focus {
            if let Some(surface) = state.surfaces.get(&old_sid).cloned() {
                let surface = surface.read_recover();
                if let Some(res) = &surface.resource {
                    state.ext.text_input.leave(res);
                    state.seat.broadcast_keyboard_leave(leave_serial, res);
                }
            }
            state.seat.keyboard.focus = None;
        }

        if let Some(surface) = state.surfaces.get(&new_sid).cloned() {
            let surface = surface.read_recover();
            if let Some(res) = &surface.resource {
                let keys: Vec<u32> = state.seat.keyboard.pressed_keys.clone();
                state.seat.keyboard.focus = Some(new_sid);
                state
                    .focus
                    .set_keyboard_focus(Some(window_id.id as u32));
                crate::wlog!(
                    crate::util::logging::FFI,
                    "Keyboard enter (focus transition): window={} surface={} keys={}",
                    window_id.id,
                    new_sid,
                    keys.len()
                );
                if let Some(keyboard) = state
                    .smithay_runtime
                    .seat
                    .as_ref()
                    .and_then(|seat| seat.get_keyboard())
                {
                    keyboard.set_focus(&mut *state, Some(res.clone()), enter_serial.into());
                } else {
                    state.seat.broadcast_keyboard_enter(enter_serial, res, &keys);
                }
                state.ext.text_input.enter(res, Some(new_sid));
            }
        }

        drop(state);

        crate::wlog!(crate::util::logging::FFI, "Focus window (keyboard): {}", window_id.id);
        {
            let mut windows = self.ffi_windows.write_recover();
            for (_, info) in windows.iter_mut() {
                info.activated = false;
            }
            if let Some(info) = windows.get_mut(&window_id.id) {
                info.activated = true;
            }
        }
        self.pending_window_events
            .write_recover()
            .push(WindowEvent::Activated { window_id });
    }
    
    /// Inject touch down event
    pub fn inject_touch_down(
        &self,
        window_id: WindowId,
        touch_id: i32,
        x: f64,
        y: f64,
        timestamp_ms: u32,
    ) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }

        let mut state = self.state.write_recover();
        let serial = state.next_serial();

        // Find the surface for this window
        if let Some(window) = state.get_window(window_id.id as u32) {
            let window = window.read_recover();
            let surface_id = window.surface_id;

            // Track the touch point
            state.seat.touch.touch_down(touch_id, surface_id, x, y);

            // Broadcast to client
            if let Some(surface) = state.get_surface(surface_id) {
                let surface = surface.read_recover();
                if let Some(res) = &surface.resource {
                    state.seat.touch.broadcast_down(serial, timestamp_ms, res, touch_id, x, y);
                }
            }
        }

        state.ext.idle_notify.record_activity();
        Ok(())
    }

    /// Inject touch up event
    pub fn inject_touch_up(&self, touch_id: i32, timestamp_ms: u32) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }

        let mut state = self.state.write_recover();
        let serial = state.next_serial();

        // Get the client before removing the touch point
        let client = state.seat.touch.get_touch_surface(touch_id).and_then(|sid| {
            state.get_surface(sid).and_then(|sf| {
                let sf = sf.read_recover();
                sf.resource.as_ref().and_then(|r| r.client())
            })
        });

        state.seat.touch.broadcast_up(serial, timestamp_ms, touch_id, client.as_ref());
        state.seat.touch.touch_up(touch_id);
        state.ext.idle_notify.record_activity();
        Ok(())
    }

    /// Inject touch motion event
    pub fn inject_touch_motion(
        &self,
        touch_id: i32,
        x: f64,
        y: f64,
        timestamp_ms: u32,
    ) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }

        let mut state = self.state.write_recover();

        let client = state.seat.touch.get_touch_surface(touch_id).and_then(|sid| {
            state.get_surface(sid).and_then(|sf| {
                let sf = sf.read_recover();
                sf.resource.as_ref().and_then(|r| r.client())
            })
        });

        state.seat.touch.broadcast_motion(timestamp_ms, touch_id, x, y, client.as_ref());
        state.seat.touch.touch_motion(touch_id, x, y);
        state.ext.idle_notify.record_activity();
        Ok(())
    }

    /// Inject touch frame event
    pub fn inject_touch_frame(&self) {
        if !self.is_running() {
            return;
        }
        let state = self.state.read_recover();
        // Send frame to all clients with active touch points
        let surface_ids: Vec<u32> = state.seat.touch.active_points.values()
            .map(|p| p.surface_id)
            .collect();
        for sid in surface_ids {
            let client = state.get_surface(sid).and_then(|sf| {
                let sf = sf.read_recover();
                sf.resource.as_ref().and_then(|r| r.client())
            });
            state.seat.touch.broadcast_frame(client.as_ref());
        }
    }

    /// Inject touch cancel event
    pub fn inject_touch_cancel(&self) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        // Send cancel to all clients with active touch points
        let surface_ids: Vec<u32> = state.seat.touch.active_points.values()
            .map(|p| p.surface_id)
            .collect();
        for sid in &surface_ids {
            let client = state.get_surface(*sid).and_then(|sf| {
                let sf = sf.read_recover();
                sf.resource.as_ref().and_then(|r| r.client())
            });
            state.seat.touch.broadcast_cancel(client.as_ref());
        }
        state.seat.touch.touch_cancel();
    }
    
    // =========================================================================
    // Text Input (IME / Emoji)
    // =========================================================================

    /// Commit a string through text-input-v3 to the focused Wayland client.
    ///
    /// This is the primary path for emoji, composed text, and IME output
    /// on Apple and Android platforms.  The string must be valid UTF-8.
    pub fn text_input_commit_string(&self, text: &str) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::INPUT, "text_input commit: {:?}", text);
        let mut state = self.state.write_recover();
        state.ext.text_input.commit_string(text);
    }

    /// Send a preedit (composition preview) string through text-input-v3.
    ///
    /// `cursor_begin` and `cursor_end` are byte offsets into `text`
    /// indicating the cursor/highlight range.  Pass (0, 0) if not applicable.
    pub fn text_input_preedit_string(&self, text: &str, cursor_begin: i32, cursor_end: i32) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::INPUT, "text_input preedit: {:?}", text);
        let mut state = self.state.write_recover();
        state.ext.text_input.preedit_string(text, cursor_begin, cursor_end);
    }

    /// Delete surrounding text relative to the cursor through text-input-v3.
    pub fn text_input_delete_surrounding(&self, before_length: u32, after_length: u32) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        state.ext.text_input.delete_surrounding_text(before_length, after_length);
    }

    /// Inject gesture event
    pub fn inject_gesture(&self, gesture: GestureEvent) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::INPUT, "Gesture: {:?} {:?} fingers={}", 
            gesture.gesture_type, gesture.state, gesture.finger_count);
        // TODO: Send pointer_gestures protocol events
    }
    
    // =========================================================================
    // Rendering
    // =========================================================================
    
    /// Get the current render scene
    pub fn get_render_scene(&self) -> RenderScene {
        if !self.is_running() {
            return RenderScene::empty();
        }
        
        let (width, height, scale) = *self.output_size.read_recover();
        
        // 1. Build the internal scene graph
        let mut state = self.state.write_recover();
        state.build_scene();
        
        let flattened_scene = state.scene.flatten();
        state.scene_damage.clear();
        for surface in &flattened_scene {
            let consumed_damage = if let Some(surface_ref) = state.get_surface(surface.surface_id) {
                let mut surf = surface_ref.write_recover();
                if surf.current.damage.is_empty() {
                    None
                } else {
                    Some(std::mem::take(&mut surf.current.damage))
                }
            } else {
                None
            };

            if let Some(surface_damage) = consumed_damage {
                state.scene_damage.add_surface_damage(
                    surface.x,
                    surface.y,
                    surface.scale,
                    &surface_damage,
                );
            }
        }
        let global_damage = state.scene_damage.global_damage.clone();
        state.scene_damage.clear();
        
        // 2. Map internal FlattenedSurface to FFI RenderNode
        let mut ffi_nodes = Vec::new();
        let ffi_textures = self.textures.read_recover();
        let mut current_anchor: (u32, i32, i32) = (0, 0, 0);
        let mut scene_hasher = std::collections::hash_map::DefaultHasher::new();
        flattened_scene.len().hash(&mut scene_hasher);
        
        for surface in flattened_scene {
            // Resolve window ID (walks subsurface tree for subsurfaces)
            let window_id = state.resolve_window_id_for_surface(surface.surface_id).unwrap_or(0);
            
            // Update anchor when we hit a surface that owns a window (toplevel or popup)
            if state.surface_to_window.get(&surface.surface_id).is_some() {
                current_anchor = (window_id, surface.x, surface.y);
            }
            
            // Texture cache is keyed by wl_buffer id (not surface id).
            let texture_handle = if let Some(surf_ref) = state.get_surface(surface.surface_id) {
                let surf = surf_ref.read_recover();
                let buffer_id = surf.current.buffer_id.unwrap_or(0) as u64;
                if let Some(handle) = ffi_textures.get(&buffer_id) {
                    *handle
                } else {
                    // ClientId doesn't easily map to an integer anymore.
                    // We just use 0 for FFI TextureHandle client grouping, since
                    // it's mostly unused by the platform side renderer.
                    let internal_client_id = 0;
                    TextureHandle::new(
                        buffer_id,
                        types::ClientId { id: internal_client_id }
                    )
                }
            } else {
                TextureHandle::null()
            };

            let mut node = RenderNode::new(
                WindowId::new(window_id as u64),
                SurfaceId::new(surface.surface_id),
                texture_handle,
            );
            
            node.x = surface.x;
            node.y = surface.y;
            node.width = surface.width;
            node.height = surface.height;


            node.scale = surface.scale;
            node.opacity = surface.opacity;
            node.visible = true; // Visibility is baked into flatten() results
            node.anchor_output_x = current_anchor.1;
            node.anchor_output_y = current_anchor.2;
            node.content_rect = surface.content_rect;

            window_id.hash(&mut scene_hasher);
            surface.surface_id.hash(&mut scene_hasher);
            surface.x.hash(&mut scene_hasher);
            surface.y.hash(&mut scene_hasher);
            surface.width.hash(&mut scene_hasher);
            surface.height.hash(&mut scene_hasher);
            surface.opacity.to_bits().hash(&mut scene_hasher);
            surface.scale.to_bits().hash(&mut scene_hasher);
            node.texture.handle.hash(&mut scene_hasher);
            
            ffi_nodes.push(node);
        }
        let scene_fingerprint = scene_hasher.finish();
        let mut last_fingerprint = self.last_scene_fingerprint.write_recover();
        let scene_changed = scene_fingerprint != *last_fingerprint;
        *last_fingerprint = scene_fingerprint;
        let has_damage = !global_damage.is_empty();
        
        RenderScene {
            nodes: ffi_nodes,
            width,
            height,
            scale,
            needs_redraw: scene_changed || has_damage,
            damage: global_damage.into_iter().map(|r| Rect::new(r.x, r.y, r.width, r.height)).collect(),
        }
    }
    
    /// Notify the compositor that a frame has been presented to the user.
    /// 
    /// # Arguments
    /// * `timestamp_ns` - The timestamp when the frame was actually displayed (nanoseconds)
    /// * `seq` - The frame sequence number
    pub fn commit_frame(&self, timestamp_ns: u64, seq: u64) {
        if !self.is_running() {
            return;
        }
        
        let mut state = self.state.write_recover();
        
        // 1. Send wp_presentation feedback events.
        // wl_surface.frame callbacks are emitted per-surface from
        // notify_frame_presented() to keep callback timing aligned with actual
        // surface presentation.
        let refresh_ns = 1_000_000_000 / 60; // TODO: Use actual refresh rate from output
        state.ext.presentation.send_presented_events(timestamp_ns, refresh_ns, seq);
        
        // 2. Flush buffer releases
        state.flush_buffer_releases();
        
        // 3. Update runtime timing
        let mut runtime = self.runtime.lock_recover();
        runtime.end_frame();
    }

    /// Get render scene for a specific window
    pub fn get_window_render_scene(&self, window_id: WindowId) -> RenderScene {
        if !self.is_running() {
            return RenderScene::empty();
        }
        
        let windows = self.ffi_windows.read_recover();
        if let Some(info) = windows.get(&window_id.id) {
            let mut scene = RenderScene::new(info.width, info.height, 1.0);
            scene.needs_redraw = true;
            scene
        } else {
            RenderScene::empty()
        }
    }
    
    /// Notify compositor that frame rendering is complete
    pub fn notify_frame_complete(&self) {
        if !self.is_running() {
            return;
        }
        
        // Mark frame complete in runtime
        self.runtime.lock_recover().end_frame();
        
        // Frame callbacks are flushed from notify_frame_presented(), not here.
    }
    
    /// Notify frame complete for specific window
    pub fn notify_window_frame_complete(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog_hot!(crate::util::logging::FFI, "Window frame complete: window={}", window_id.id);
        
        // Callbacks are now flushed from notify_frame_presented(surface, ...),
        // which is aligned to actual presentation timing.
    }
    
    /// Flush frame callbacks immediately
    pub fn flush_frame_callbacks(&self) {
        if !self.is_running() {
            return;
        }
        self.state.write_recover().flush_all_frame_callbacks();
    }
    
    // =========================================================================
    // Configuration
    // =========================================================================
    
    /// Set output size and scale.
    ///
    /// When the size actually changes (e.g. device rotation on iOS) this:
    /// 1. Updates the internal output state
    /// 2. Sends wl_output.mode / .geometry / .done to all bound output resources
    /// 3. Sends xdg_output logical_size changes
    ///
    /// Does **not** emit `xdg_toplevel.configure` for every surface: each window keeps
    /// its own dimensions via [`resize_window`](Self::resize_window) / initial setup.
    /// Broadcasting one global size to all toplevels broke multi-window macOS sessions
    /// (e.g. opening a second client forced every existing client to the new output size).
    pub fn set_output_size(&self, width: u32, height: u32, scale: f32) {
        let safe_scale = if scale < 1.0 { 1.0 } else { scale };

        let (prev_w, prev_h, prev_s) = {
            let cur = self.output_size.read_recover();
            (cur.0, cur.1, cur.2)
        };

        if prev_w == width && prev_h == height && (prev_s - safe_scale).abs() < 0.001 {
            return;
        }

        crate::wlog!(crate::util::logging::FFI, "Output size: {}x{} @ {}x", width, height, safe_scale);
        *self.output_size.write_recover() = (width, height, safe_scale);

        let output_id;

        {
            let mut state = self.state.write_recover();
            state.set_output_size(width, height, safe_scale);
            output_id = state.outputs.first().map(|o| o.id).unwrap_or(0);
        }

        if prev_w != width || prev_h != height || (prev_s - safe_scale).abs() > 0.001 {
            let state = self.state.read_recover();

            crate::core::wayland::wayland::output::notify_output_change(&state, output_id);

            crate::wlog!(crate::util::logging::FFI,
                "Output resized {}x{}@{}x → {}x{}@{}x (wl_output broadcast; toplevels unchanged)",
                prev_w, prev_h, prev_s, width, height, safe_scale);
        }
    }

    /// Like [`set_output_size`](Self::set_output_size), but notifies **only** the Wayland
    /// client that owns `window_id` of `wl_output` / `xdg_output` changes.
    ///
    /// Used on macOS when placing a nested compositor in a smaller host window: the
    /// owning process must see `wl_output.mode` match its drawable area, without
    /// pushing that mode change to every other connected client.
    pub fn set_output_geometry_for_window(&self, window_id: WindowId, width: u32, height: u32, scale: f32) {
        let safe_scale = if scale < 1.0 { 1.0 } else { scale };
        let wid = window_id.id as u32;
        let wkey = window_id.id;
        let scale_key = (safe_scale * 1000.0).round() as u32;

        {
            let cache = self.per_window_output_notify.read_recover();
            if let Some(&(pw, ph, pk)) = cache.get(&wkey) {
                if pw == width && ph == height && pk == scale_key {
                    return;
                }
            }
        }

        crate::wlog!(
            crate::util::logging::FFI,
            "Output geometry (for window {}): {}x{} @ {}x (per-client wl_output only)",
            wid,
            width,
            height,
            safe_scale
        );
        // No resize transaction here: this is an output-geometry notification,
        // not a size request. Beginning one would clobber any real pending
        // HostConfigure transaction for the window (one txn slot per window).

        let (output_id, owner_client) = {
            let state = self.state.read_recover();
            let oid = state.outputs.first().map(|o| o.id).unwrap_or(0);
            let cid = state
                .xdg
                .toplevels
                .iter()
                .find(|(_, d)| d.window_id == wid)
                .map(|(k, _)| k.0.clone());
            (oid, cid)
        };

        if let Some(ref cid) = owner_client {
            let state = self.state.read_recover();
            crate::core::wayland::wayland::output::notify_output_change_for_client_override(
                &state,
                output_id,
                cid,
                width,
                height,
                safe_scale,
            );
            crate::wlog!(
                crate::util::logging::FFI,
                "wl_output/xdg_output override → client {:?} only ({}x{} @ {}x); global output unchanged",
                cid,
                width,
                height,
                safe_scale
            );
        } else {
            // Keep this API strictly per-window.
            //
            // If the owner toplevel is not yet discoverable (early startup ordering),
            // do NOT fall back to global output mutation here. A global wl_output change
            // can reconfigure unrelated clients and create visible size oscillation loops.
            crate::wtrace!(
                crate::util::logging::FFI,
                "Output geometry override deferred: no toplevel owner yet for window {} ({}x{} @ {}x)",
                wid,
                width,
                height,
                safe_scale
            );
            return;
        }

        self.per_window_output_notify
            .write_recover()
            .insert(wkey, (width, height, scale_key));
    }
    
    /// Set platform safe area insets on the primary output.
    /// On iOS these correspond to the notch, home indicator, and rounded corners.
    pub fn set_safe_area_insets(&self, top: i32, right: i32, bottom: i32, left: i32) {
        crate::wlog!(crate::util::logging::FFI, "Safe area insets: top={} right={} bottom={} left={}", top, right, bottom, left);
        let mut state = self.state.write_recover();
        state.set_safe_area_insets(top, right, bottom, left);
    }
    
    /// Configure output
    pub fn configure_output(&self, output: OutputInfo) {
        crate::wlog!(crate::util::logging::FFI, "Configure output: {}", output.name);
        // TODO: Register output with Wayland display
    }
    
    
    /// Set keyboard repeat rate
    pub fn set_keyboard_repeat(&self, rate: i32, delay: i32) {
        crate::wlog!(crate::util::logging::FFI, "Keyboard repeat: rate={} Hz, delay={} ms", rate, delay);
        *self.keyboard_config.write_recover() = (rate, delay);
        
        // Update state
        {
            let mut state = self.state.write_recover();
            state.keyboard_repeat_rate = rate;
            state.keyboard_repeat_delay = delay;
        }
        // TODO: Send wl_keyboard::repeat_info
    }
    
    // =========================================================================
    // Window Management
    // =========================================================================
    
    /// Get list of window IDs
    pub fn get_windows(&self) -> Vec<WindowId> {
        self.ffi_windows
            .read_recover()
            .keys()
            .map(|id| WindowId::new(*id))
            .collect()
    }
    
    /// Get window info
    pub fn get_window_info(&self, window_id: WindowId) -> Option<WindowInfo> {
        self.ffi_windows.read_recover().get(&window_id.id).cloned()
    }
    
    /// Set window focus
    pub fn focus_window(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::FFI, "Focus window: {}", window_id.id);
        
        // Update state
        self.state.write_recover().set_focused_window(Some(window_id.id as u32));
        
        // Update FFI window info
        {
            let mut windows = self.ffi_windows.write_recover();
            // Deactivate all windows first
            for (_, info) in windows.iter_mut() {
                info.activated = false;
            }
            // Activate the focused window
            if let Some(info) = windows.get_mut(&window_id.id) {
                info.activated = true;
            }
        }
        
        self.pending_window_events.write_recover().push(
            WindowEvent::Activated { window_id }
        );
    }
    
    /// Unfocus all windows
    pub fn unfocus_all(&self) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::FFI, "Unfocus all windows");
        
        // Update state
        self.state.write_recover().set_focused_window(None);
        
        // Deactivate all windows
        let mut windows = self.ffi_windows.write_recover();
        for (id, info) in windows.iter_mut() {
            if info.activated {
                info.activated = false;
                self.pending_window_events.write_recover().push(
                    WindowEvent::Deactivated { window_id: WindowId::new(*id) }
                );
            }
        }
    }
    
    /// Ask the Wayland client to close this toplevel (`xdg_toplevel.close`) and flush.
    /// Returns `true` if a matching xdg_toplevel was found.
    pub fn request_window_close(&self, window_id: WindowId) -> bool {
        if !self.is_running() {
            return false;
        }
        crate::wlog!(
            crate::util::logging::FFI,
            "Request window close (xdg_toplevel.close): {}",
            window_id.id
        );
        let sent = self
            .state
            .write_recover()
            .send_toplevel_close_for_window(window_id.id as u32);
        self.flush_clients();
        sent
    }

    /// Host dismissed a popup (click-away, Escape, parent teardown). Tell the
    /// client via `xdg_popup.popup_done` so it can destroy the popup cleanly.
    pub fn notify_popup_dismissed(&self, window_id: WindowId) -> bool {
        if !self.is_running() {
            return false;
        }
        crate::wlog!(
            crate::util::logging::FFI,
            "Popup dismissed by host (xdg_popup.popup_done): {}",
            window_id.id
        );
        let sent = self
            .state
            .write_recover()
            .send_popup_done_for_window(window_id.id as u32);
        self.flush_clients();
        sent
    }

    /// Tear down compositor-side window state immediately (no `xdg_toplevel.close`).
    /// Drains `pending_compositor_events` from `destroy_window` so FFI/host state stays consistent.
    /// Use when soft close stalls (client assert/hang/ignore).
    pub fn force_destroy_host_window(&self, window_id: WindowId) -> bool {
        if !self.is_running() {
            return false;
        }
        let wid = window_id.id as u32;
        crate::wlog!(
            crate::util::logging::FFI,
            "Force destroy host window: {}",
            window_id.id
        );
        let pending = {
            let mut state = self.state.write_recover();
            if state.get_window(wid).is_none() {
                return false;
            }
            state.destroy_window(wid);
            std::mem::take(&mut state.pending_compositor_events)
        };
        for event in pending {
            self.handle_compositor_event(event);
        }
        self.flush_clients();
        true
    }
    
    /// Start interactive move
    pub fn start_window_move(&self, window_id: WindowId, serial: u32) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Start window move: window={}, serial={}", window_id.id, serial);
        
        self.pending_window_events.write_recover().push(
            WindowEvent::MoveRequested { window_id, serial }
        );
    }
    
    /// Start interactive resize
    pub fn start_window_resize(&self, window_id: WindowId, serial: u32, edge: ResizeEdge) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Start window resize: window={}, serial={}, edge={:?}", 
            window_id.id, serial, edge);
        
        self.pending_window_events.write_recover().push(
            WindowEvent::ResizeRequested { window_id, serial, edge }
        );
    }
    
    // =========================================================================
    // Client Management
    // =========================================================================
    
    /// Get connected client count
    pub fn get_client_count(&self) -> u32 {
        self.compositor.lock_recover()
            .as_ref()
            .map(|c| c.client_count() as u32)
            .unwrap_or(0)
    }
    
    /// Get list of connected clients
    pub fn get_clients(&self) -> Vec<ClientInfo> {
        self.ffi_clients.read_recover().values().cloned().collect()
    }
    
    /// Disconnect a client
    pub fn disconnect_client(&self, client_id: ClientId) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Disconnect client: {}", client_id.id);
        if let Some(compositor) = self.compositor.lock_recover().as_mut() {
            if compositor.disconnect_client_by_internal(client_id.id as u32) {
                // Drive cleanup promptly; natural callbacks will still reconcile.
                let mut state = self.state.write_recover();
                let _ = compositor.dispatch(&mut state);
            }
        }
    }

    /// Disconnect all connected Wayland clients (ends in-process client threads).
    pub fn disconnect_all_clients(&self) -> u32 {
        if !self.is_running() {
            return 0;
        }
        let mut compositor_guard = self.compositor.lock_recover();
        let Some(compositor) = compositor_guard.as_mut() else {
            return 0;
        };
        let count = compositor.disconnect_all_clients();
        if count > 0 {
            crate::wlog!(
                crate::util::logging::FFI,
                "Disconnected {} in-process Wayland client(s)",
                count
            );
            let mut state = self.state.write_recover();
            let _ = compositor.dispatch(&mut state);
        }
        count as u32
    }
    
    // =========================================================================
    // Surface Management
    // =========================================================================
    
    /// Get surface state
    pub fn get_surface_state(&self, surface_id: SurfaceId) -> Option<SurfaceState> {
        self.ffi_surfaces.read_recover().get(&surface_id.id).cloned()
    }
    
    // =========================================================================
    // Debug/IPC
    // =========================================================================
    
    /// Execute debug command
    pub fn execute_debug_command(&self, command: DebugCommand) -> String {
        match command {
            DebugCommand::DumpState => {
                let (width, height, scale) = *self.output_size.read_recover();
                let state = self.state.read_recover();
                format!(
                    "Compositor State:\n\
                     Running: {}\n\
                     Socket: {}\n\
                     Output: {}x{} @ {}x\n\
                     Windows: {}\n\
                     Surfaces: {}\n\
                     Clients: {}\n\
                     Focused: {:?}",
                    self.is_running(),
                    self.get_socket_name(),
                    width, height, scale,
                    state.windows.len(),
                    state.surfaces.len(),
                    self.get_client_count(),
                    state.focus.keyboard_focus
                )
            }
            DebugCommand::DumpSurfaces => {
                let state = self.state.read_recover();
                let mut output = format!("Surfaces ({}):\n", state.surfaces.len());
                for (id, surface) in state.surfaces.iter() {
                    let s = surface.read_recover();
                    output.push_str(&format!(
                        "  Surface {}: size={}x{}\n",
                        id, s.current.width, s.current.height
                    ));
                }
                output
            }
            DebugCommand::DumpWindows => {
                let state = self.state.read_recover();
                let mut output = format!("Windows ({}):\n", state.windows.len());
                for (id, window) in state.windows.iter() {
                    let w = window.read_recover();
                    output.push_str(&format!(
                        "  Window {}: title=\"{}\", size={}x{}\n",
                        id, w.title, w.width, w.height
                    ));
                }
                output
            }
            DebugCommand::DumpClients => {
                let clients = self.ffi_clients.read_recover();
                let mut output = format!("Clients ({}):\n", clients.len());
                for (id, info) in clients.iter() {
                    output.push_str(&format!(
                        "  Client {}: pid={}, surfaces={}, windows={}\n",
                        id, info.pid, info.surface_count, info.window_count
                    ));
                }
                output
            }
            DebugCommand::SetLogLevel { level } => {
                crate::wlog!(crate::util::logging::MAIN, "Set log level: {}", level);
                format!("Log level set to: {}", level)
            }
            DebugCommand::ForceRedraw => {
                let windows = self.ffi_windows.read_recover();
                let window_ids: Vec<WindowId> = windows.keys().map(|id| WindowId::new(*id)).collect();
                let count = window_ids.len();
                self.pending_redraws.write_recover().extend(window_ids);
                self.runtime.lock_recover().request_redraw();
                format!("Forced redraw for {} windows", count)
            }
        }
    }
    
    /// Get compositor statistics
    pub fn get_stats(&self) -> String {
        let (width, height, scale) = *self.output_size.read_recover();
        let (rate, delay) = *self.keyboard_config.read_recover();
        let fps = self.runtime.lock_recover().fps();
        
        format!(
            "Wawona Compositor Statistics\n\
             ============================\n\
             Version: {}\n\
             Running: {}\n\
             Socket: {}\n\
             FPS: {:.1}\n\
             \n\
             Output:\n\
               Size: {}x{}\n\
               Scale: {}\n\
             \n\
             Input:\n\
               Keyboard repeat: {} Hz, {} ms delay\n\
             \n\
             Objects:\n\
               Windows: {}\n\
               Surfaces: {}\n\
               Clients: {}\n\
               Textures: {}",
            version(),
            self.is_running(),
            self.get_socket_name(),
            fps,
            width, height,
            scale,
            rate, delay,
            self.ffi_windows.read_recover().len(),
            self.ffi_surfaces.read_recover().len(),
            self.get_client_count(),
            self.textures.read_recover().len(),
        )
    }

}

// ============================================================================
// Image copy capture (ext-image-copy-capture-v1). Desktop-protocols only
// Exported only when feature enabled; c_api has stubs when disabled
// ============================================================================
#[cfg(feature = "desktop-protocols")]
#[uniffi::export]
impl WawonaCore {
    /// Get the first pending image copy capture (ext-image-copy-capture-v1; same flow as screencopy)
    pub fn get_pending_image_copy_capture(&self) -> Option<types::ScreencopyRequest> {
        if !self.is_running() {
            return None;
        }
        let state = self.state.read_recover();
        crate::core::wayland::ext::image_copy_capture::get_pending_image_copy_capture(&state).map(
            |(capture_id, ptr, width, height, stride, size)| types::ScreencopyRequest {
                capture_id,
                ptr: ptr as u64,
                width,
                height,
                stride,
                size: size as u64,
            },
        )
    }

    /// Notify image copy capture complete (platform has written pixels)
    pub fn image_copy_capture_done(&self, capture_id: u64) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::ext::image_copy_capture::complete_image_copy_capture(&mut state, capture_id);
    }

    /// Notify image copy capture failed
    pub fn image_copy_capture_failed(&self, capture_id: u64) {
        if !self.is_running() {
            return;
        }
        let mut state = self.state.write_recover();
        crate::core::wayland::ext::image_copy_capture::fail_image_copy_capture(&mut state, capture_id);
    }
}

// ============================================================================
// Methods NOT exported via UniFFI (C API only. Tuples / non-Record types)
// ============================================================================
impl WawonaCore {
    /// True when a focused `zwp_text_input_v3` instance has committed `enable`.
    /// Host platforms poll this for IME routing (commit_string vs key inject).
    pub fn text_input_is_enabled(&self) -> bool {
        if !self.is_running() {
            return false;
        }
        let state = self.state.read_recover();
        state.ext.text_input.committed_enabled()
    }

    /// Soft OSK should expand: committed TI enable OR terminal-focus synthesis.
    pub fn text_entry_wanted(&self) -> bool {
        if !self.is_running() {
            return false;
        }
        let state = self.state.read_recover();
        crate::core::wayland::ext::text_input::text_entry_wanted(&state)
    }

    /// Read the surrounding text and cursor position reported by the focused
    /// Wayland client via `set_surrounding_text`.  Returns `(text, cursor, anchor)`.
    /// The platform can use this to seed its native IME context for autocorrect.
    pub fn text_input_get_surrounding(&self) -> (String, i32, i32) {
        if !self.is_running() {
            return (String::new(), 0, 0);
        }
        let state = self.state.read_recover();
        if let Some(instance) = state.ext.text_input.focused_enabled_instance() {
            return (
                instance.surrounding_text.clone(),
                instance.surrounding_cursor,
                instance.surrounding_anchor,
            );
        }
        (String::new(), 0, 0)
    }

    /// Read the cursor rectangle reported by the focused Wayland client
    /// via `set_cursor_rectangle`.  Returns `(x, y, width, height)` in
    /// surface-local coordinates.  The platform should use this to position
    /// IME candidate windows and emoji pickers near the text cursor.
    pub fn text_input_get_cursor_rect(&self) -> (i32, i32, i32, i32) {
        if !self.is_running() {
            return (0, 0, 0, 0);
        }
        let state = self.state.read_recover();
        if let Some(instance) = state.ext.text_input.focused_enabled_instance() {
            return instance.cursor_rect;
        }
        (0, 0, 0, 0)
    }

    /// Read the content type hint reported by the focused Wayland client
    /// via `set_content_type`.  Returns `(hint, purpose)`.
    /// The platform can use this to configure the native keyboard appropriately.
    pub fn text_input_get_content_type(&self) -> (u32, u32) {
        if !self.is_running() {
            return (0, 0);
        }
        let state = self.state.read_recover();
        if let Some(instance) = state.ext.text_input.focused_enabled_instance() {
            return (
                instance.content_type.hint,
                instance.content_type.purpose,
            );
        }
        (0, 0)
    }

    /// Get cursor rendering information for the C API.
    ///
    /// Returns the pointer position, hotspot, and buffer metadata for the
    /// cursor surface set by the Wayland client via wl_pointer.set_cursor.
    pub fn get_cursor_render_info(&self) -> types::CursorRenderInfo {
        let state = self.state.read_recover();
        let pointer = &state.seat.pointer;

        let cursor_sid = match pointer.cursor_surface {
            Some(sid) => sid,
            None => return types::CursorRenderInfo::default(),
        };

        // Look up the surface's current buffer
        let buffer_id = if let Some(surface_ref) = state.surfaces.get(&cursor_sid) {
            let surface = surface_ref.read_recover();
            surface.current.buffer_id.unwrap_or(0) as u64
        } else {
            return types::CursorRenderInfo::default();
        };

        if buffer_id == 0 {
            return types::CursorRenderInfo::default();
        }

        // Look up buffer metadata
        let (width, height, stride, format, iosurface_id) =
            if let Some(surface_ref) = state.surfaces.get(&cursor_sid) {
                let surface = surface_ref.read_recover();
                let Some(client_id) = surface.client_id.clone() else {
                    return types::CursorRenderInfo::default();
                };
                if let Some(buf_ref) = state.buffers.get(&(client_id, buffer_id as u32)) {
                    let buf = buf_ref.read_recover();
                    match &buf.buffer_type {
                        crate::core::surface::BufferType::Shm(shm) => (
                            shm.width as u32,
                            shm.height as u32,
                            shm.stride as u32,
                            shm.format as u32,
                            0u32,
                        ),
                        crate::core::surface::BufferType::Native(native) => (
                            native.width as u32,
                            native.height as u32,
                            0u32,
                            native.format,
                            native.id as u32,
                        ),
                        _ => (0, 0, 0, 0, 0),
                    }
                } else {
                    (0, 0, 0, 0, 0)
                }
            } else {
                (0, 0, 0, 0, 0)
            };

        types::CursorRenderInfo {
            has_cursor: true,
            x: pointer.x as f32,
            y: pointer.y as f32,
            hotspot_x: pointer.cursor_hotspot_x as f32,
            hotspot_y: pointer.cursor_hotspot_y as f32,
            surface_id: cursor_sid,
            buffer_id,
            width,
            height,
            stride,
            format,
            iosurface_id,
        }
    }

    /// Helper for C API to lookup buffer info for a scene node
    /// Returns BufferRenderInfo
    pub fn get_buffer_render_info(&self, texture: TextureHandle) -> BufferRenderInfo {
        let buffer_id = texture.handle;
        if buffer_id == 0 {
            return BufferRenderInfo { stride: 0, format: 0, iosurface_id: 0, width: 0, height: 0 };
        }

        let buffer_id_u32 = buffer_id as u32;

        // Resolve the client id (if any) while holding only the `compositor`
        // lock, then acquire `state` afterwards. This preserves the
        // compositor-before-state lock order used everywhere else (e.g.
        // process_events()); acquiring `state` first and then `compositor`
        // (as this function previously did) is the reverse order and can
        // deadlock against any thread that holds `compositor` while waiting
        // on `state` (see process_events(), invoked from each client's own
        // event-loop thread for in-process native clients like
        // weston-terminal).
        let client_id = self
            .compositor
            .lock_recover()
            .as_ref()
            .and_then(|c| c.internal_to_client_id(texture.client_id.id));

        let state = self.state.read_recover();
        let auth_buffer = client_id
            .and_then(|client_id| state.buffers.get(&(client_id, buffer_id_u32)).cloned())
            .or_else(|| {
                state
                    .buffers
                    .iter()
                    .find(|(_, b)| b.read_recover().id == buffer_id_u32)
                    .map(|(_, b)| b.clone())
            });

        if let Some(auth_buffer) = auth_buffer {
            let buffer = auth_buffer.read_recover();
            match &buffer.buffer_type {
                crate::core::surface::BufferType::Shm(shm) => BufferRenderInfo {
                    stride: shm.stride as u32,
                    format: shm.format as u32,
                    iosurface_id: 0,
                    width: shm.width as u32,
                    height: shm.height as u32,
                },
                crate::core::surface::BufferType::Native(native) => BufferRenderInfo {
                    stride: 0,
                    format: native.format,
                    iosurface_id: native.id as u32,
                    width: native.width as u32,
                    height: native.height as u32,
                },
                _ => BufferRenderInfo {
                    stride: 0,
                    format: 0,
                    iosurface_id: 0,
                    width: 0,
                    height: 0,
                },
            }
        } else {
            BufferRenderInfo {
                stride: 0,
                format: 0,
                iosurface_id: 0,
                width: 0,
                height: 0,
            }
        }
    }
}

// ============================================================================
// Free Functions
// ============================================================================

/// Get library version
#[uniffi::export]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Get build information
#[uniffi::export]
pub fn build_info() -> String {
    format!(
        "Wawona Compositor v{}\n\
         Built with Rust {}\n\
         Target: {}",
        env!("CARGO_PKG_VERSION"),
        "1.75+",
        std::env::consts::ARCH,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_callbacks_flush_on_commit_and_presentation_points() {
        assert!(should_flush_frame_callbacks(
            FrameCallbackFlushPoint::SurfaceCommitted
        ));
        assert!(should_flush_frame_callbacks(
            FrameCallbackFlushPoint::FramePresented
        ));
        assert!(!should_flush_frame_callbacks(
            FrameCallbackFlushPoint::FrameComplete
        ));
    }

    #[test]
    fn apply_geometry_offset_respects_inset_for_server_side() {
        use crate::core::window::DecorationMode;
        let mut state = CompositorState::new(None);
        let wid = 42u32;
        let mut window = crate::core::window::Window::new(wid, 1);
        window.decoration_mode = DecorationMode::ServerSide;
        window.geometry_x = 10;
        window.geometry_y = 32;
        state.windows.insert(
            wid,
            std::sync::Arc::new(std::sync::RwLock::new(window)),
        );
        state.surface_to_window.insert(1, wid);
        let (x, y) = apply_geometry_offset(&state, WindowId { id: wid as u64 }, 100.0, 50.0);
        assert_eq!(x, 110.0);
        assert_eq!(y, 82.0);
    }

    #[test]
    fn buffer_size_mismatch_accepts_logical_and_physical() {
        assert_eq!(buffer_size_mismatch_px(420, 912, 420, 912, 3), (0, 0));
        assert_eq!(buffer_size_mismatch_px(1260, 2736, 420, 912, 3), (0, 0));
        assert_eq!(buffer_size_mismatch_px(1260, 2430, 420, 912, 3), (0, 306));
    }
}

// Note: UniFFI scaffolding is generated in lib.rs
