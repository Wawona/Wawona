//! Wayland Protocol Implementation
//!
//! This module organizes the various Wayland protocol implementations into
//! logical categories for better maintainability.

use smithay::reexports::wayland_server::Resource;

pub mod protocol;
pub mod wayland;
pub mod xdg;
pub mod wlr;
pub mod plasma;
pub mod ext;

impl smithay::wayland::buffer::BufferHandler for crate::core::state::CompositorState {
    fn buffer_destroyed(
        &mut self,
        _buffer: &smithay::reexports::wayland_server::protocol::wl_buffer::WlBuffer,
    ) {
        // Wawona keeps explicit buffer lifecycle bookkeeping in its own render paths.
    }
}

impl smithay::wayland::shm::ShmHandler for crate::core::state::CompositorState {
    fn shm_state(&self) -> &smithay::wayland::shm::ShmState {
        self.smithay_runtime
            .shm
            .as_ref()
            .expect("smithay shm state must be initialized before dispatch")
    }
}

smithay::delegate_shm!(crate::core::state::CompositorState);

impl smithay::wayland::output::OutputHandler for crate::core::state::CompositorState {}

smithay::delegate_output!(crate::core::state::CompositorState);

impl smithay::wayland::compositor::CompositorHandler for crate::core::state::CompositorState {
    fn compositor_state(&mut self) -> &mut smithay::wayland::compositor::CompositorState {
        self.smithay_runtime
            .compositor
            .as_mut()
            .expect("smithay compositor state must be initialized before dispatch")
    }

    fn client_compositor_state<'a>(
        &self,
        _client: &'a smithay::reexports::wayland_server::Client,
    ) -> &'a smithay::wayland::compositor::CompositorClientState {
        // Wawona currently shares one compositor client state across clients until
        // per-client state cutover is completed.
        unsafe {
            // SAFETY: This extends the borrow to match Smithay's trait shape while
            // pointing to stable compositor-owned storage for the process lifetime.
            &*(&self.smithay_runtime.client_compositor_state
                as *const smithay::wayland::compositor::CompositorClientState)
        }
    }

    fn new_surface(
        &mut self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) {
        let Some(client_id) = surface.client().map(|c| c.id()) else {
            return;
        };
        self.ensure_internal_surface_mapping(client_id, surface);
    }

    fn new_subsurface(
        &mut self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
        parent: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) {
        let Some(client_id) = surface.client().map(|c| c.id()) else {
            return;
        };
        let surface_id = self.ensure_internal_surface_mapping(client_id.clone(), surface);
        let parent_id = self.ensure_internal_surface_mapping(client_id, parent);
        if !self.subsurfaces.contains_key(&surface_id) {
            self.add_subsurface(surface_id, parent_id);
        }
    }

    fn commit(
        &mut self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) {
        use smithay::wayland::compositor::{BufferAssignment, Damage, SurfaceAttributes, with_states};
        use smithay::wayland::shm::with_buffer_contents;

        let Some(client_id) = surface.client().map(|c| c.id()) else {
            return;
        };
        let surface_id = self.ensure_internal_surface_mapping(client_id.clone(), surface);

        let attrs = with_states(surface, |states| {
            let mut cache_guard = states.cached_state.get::<SurfaceAttributes>();
            let attrs = cache_guard.current();
            (
                attrs.buffer.take(),
                attrs.buffer_delta.take(),
                attrs.buffer_scale,
                attrs.buffer_transform,
                attrs.input_region.clone(),
                attrs.opaque_region.clone(),
                std::mem::take(&mut attrs.damage),
                std::mem::take(&mut attrs.frame_callbacks),
            )
        });

        let (
            buffer_assignment,
            buffer_delta,
            buffer_scale,
            buffer_transform,
            input_region,
            opaque_region,
            damage,
            frame_callbacks,
        ) = attrs;

        if let Some(surface_ref) = self.get_surface(surface_id) {
            let mut surface_state = surface_ref.write().unwrap();

            surface_state.pending.scale = buffer_scale;
            surface_state.pending.transform = buffer_transform;
            if let Some(delta) = buffer_delta {
                surface_state.pending.offset = (delta.x, delta.y);
            }

            surface_state.pending.input_region = input_region.map(|region| {
                region
                    .rects
                    .into_iter()
                    .filter_map(|(kind, rect)| {
                        matches!(kind, smithay::wayland::compositor::RectangleKind::Add).then_some(
                            crate::core::surface::damage::DamageRegion::new(
                                rect.loc.x,
                                rect.loc.y,
                                rect.size.w,
                                rect.size.h,
                            ),
                        )
                    })
                    .collect()
            });

            surface_state.pending.opaque_region = opaque_region.map(|region| {
                region
                    .rects
                    .into_iter()
                    .filter_map(|(kind, rect)| {
                        matches!(kind, smithay::wayland::compositor::RectangleKind::Add).then_some(
                            crate::core::surface::damage::DamageRegion::new(
                                rect.loc.x,
                                rect.loc.y,
                                rect.size.w,
                                rect.size.h,
                            ),
                        )
                    })
                    .collect()
            });
            surface_state.pending.opaque = surface_state.pending.opaque_region.is_some();

            for item in damage {
                match item {
                    Damage::Surface(rect) => surface_state.pending.damage.push(
                        crate::core::surface::damage::DamageRegion::new(
                            rect.loc.x,
                            rect.loc.y,
                            rect.size.w,
                            rect.size.h,
                        ),
                    ),
                    Damage::Buffer(rect) => surface_state.pending.buffer_damage.push(
                        crate::core::surface::damage::DamageRegion::new(
                            rect.loc.x,
                            rect.loc.y,
                            rect.size.w,
                            rect.size.h,
                        ),
                    ),
                }
            }

            if let Some(assignment) = buffer_assignment {
                match assignment {
                    BufferAssignment::Removed => {
                        surface_state.pending.buffer = crate::core::surface::BufferType::None;
                        surface_state.pending.buffer_id = None;
                    }
                    BufferAssignment::NewBuffer(buffer_resource) => {
                        let buffer_id = buffer_resource.id().protocol_id();
                        surface_state.pending.buffer_id = Some(buffer_id);

                        if let Some(buffer_ref) = self.get_buffer(client_id.clone(), buffer_id) {
                            let mut buf = buffer_ref.write().unwrap();
                            buf.released = false;
                            buf.resource = Some(buffer_resource.clone());
                            surface_state.pending.buffer = buf.buffer_type.clone();
                        } else if let Ok((width, height, stride, offset, format)) =
                            with_buffer_contents(&buffer_resource, |_, _, data| {
                                (
                                    data.width,
                                    data.height,
                                    data.stride,
                                    data.offset,
                                    crate::core::surface::buffer::wl_shm_format_to_legacy_u32(data.format),
                                )
                            })
                        {
                            let shm = crate::core::surface::buffer::ShmBufferData {
                                width,
                                height,
                                stride,
                                format,
                                offset,
                                pool_id: 0,
                            };
                            self.add_buffer(
                                client_id.clone(),
                                crate::core::surface::Buffer::new(
                                    buffer_id,
                                    crate::core::surface::BufferType::Shm(shm.clone()),
                                    Some(buffer_resource.clone()),
                                ),
                            );
                            surface_state.pending.buffer = crate::core::surface::BufferType::Shm(shm);
                        } else {
                            surface_state.pending.buffer = crate::core::surface::BufferType::None;
                        }

                        if let Some((w, h)) = surface_state.pending.buffer.dimensions() {
                            surface_state.pending.width = w;
                            surface_state.pending.height = h;
                        }
                    }
                }
            }
        }

        for callback in frame_callbacks {
            self.queue_frame_callback(surface_id, callback);
        }

        self.handle_surface_commit(surface_id);
    }

    fn destroyed(
        &mut self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) {
        let Some(client_id) = surface.client().map(|c| c.id()) else {
            return;
        };
        let protocol_id = surface.id().protocol_id();
        if let Some(surface_id) = self
            .protocol_to_internal_surface
            .remove(&(client_id, protocol_id))
        {
            self.remove_surface(surface_id);
        }
    }
}

smithay::delegate_compositor!(crate::core::state::CompositorState);

impl smithay::input::SeatHandler for crate::core::state::CompositorState {
    type KeyboardFocus = smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
    type PointerFocus = smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
    type TouchFocus = smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;

    fn seat_state(&mut self) -> &mut smithay::input::SeatState<Self> {
        self.smithay_runtime
            .seat_state
            .as_mut()
            .expect("smithay seat state must be initialized before dispatch")
    }
}

impl smithay::wayland::selection::SelectionHandler for crate::core::state::CompositorState {
    type SelectionUserData = ();
}

impl smithay::wayland::selection::data_device::ClientDndGrabHandler
    for crate::core::state::CompositorState
{
}

impl smithay::wayland::selection::data_device::ServerDndGrabHandler
    for crate::core::state::CompositorState
{
}

impl smithay::wayland::selection::data_device::DataDeviceHandler
    for crate::core::state::CompositorState
{
    fn data_device_state(&self) -> &smithay::wayland::selection::data_device::DataDeviceState {
        self.smithay_runtime
            .data_device
            .as_ref()
            .expect("smithay data device state must be initialized before dispatch")
    }
}

smithay::delegate_seat!(crate::core::state::CompositorState);
smithay::delegate_data_device!(crate::core::state::CompositorState);
pub mod smithay_runtime {
    //! Runtime Smithay protocol ownership boundary.
    //!
    //! This module owns the runtime state objects that register Smithay-backed
    //! globals used by Wawona. The canonical interface map is retained for CI
    //! contract checks.

    use wayland_server::DisplayHandle;

    use crate::core::state::CompositorState;

    /// Protocol-to-module mapping used by coverage checks.
    #[derive(Debug, Clone, Copy)]
    pub struct SmithayRuntimeBinding {
        pub interface: &'static str,
        pub module_path: &'static str,
    }

    /// Canonical Smithay runtime targets.
    pub const SMITHAY_RUNTIME_BINDINGS: &[SmithayRuntimeBinding] = &[
        SmithayRuntimeBinding { interface: "wl_compositor", module_path: "smithay::wayland::compositor" },
        SmithayRuntimeBinding { interface: "wl_subcompositor", module_path: "smithay::wayland::compositor" },
        SmithayRuntimeBinding { interface: "wl_shm", module_path: "smithay::wayland::shm" },
        SmithayRuntimeBinding { interface: "wl_seat", module_path: "smithay::wayland::seat" },
        SmithayRuntimeBinding { interface: "wl_output", module_path: "smithay::wayland::output" },
        SmithayRuntimeBinding { interface: "zxdg_output_manager_v1", module_path: "smithay::wayland::output" },
        SmithayRuntimeBinding { interface: "wl_data_device_manager", module_path: "smithay::wayland::selection::data_device" },
        SmithayRuntimeBinding { interface: "wl_fixes", module_path: "smithay::wayland::fixes" },
        SmithayRuntimeBinding { interface: "xdg_wm_base", module_path: "smithay::wayland::shell::xdg" },
        SmithayRuntimeBinding { interface: "xdg_wm_dialog_v1", module_path: "smithay::wayland::shell::xdg::dialog" },
        SmithayRuntimeBinding { interface: "zwlr_layer_shell_v1", module_path: "smithay::wayland::shell::wlr_layer" },
        SmithayRuntimeBinding { interface: "zwlr_screencopy_manager_v1", module_path: "smithay::wayland::image_copy_capture (wlr equivalent)" },
        SmithayRuntimeBinding { interface: "zwlr_export_dmabuf_manager_v1", module_path: "smithay::wayland::dmabuf export path" },
        SmithayRuntimeBinding { interface: "zwlr_virtual_pointer_manager_v1", module_path: "smithay::wayland::virtual_pointer" },
        SmithayRuntimeBinding { interface: "zxdg_toplevel_decoration_v1", module_path: "smithay::wayland::shell::xdg::decoration" },
        SmithayRuntimeBinding { interface: "xdg_activation_v1", module_path: "smithay::wayland::xdg_activation" },
        SmithayRuntimeBinding { interface: "zxdg_exporter_v2", module_path: "smithay::wayland::xdg_foreign" },
        SmithayRuntimeBinding { interface: "zxdg_importer_v2", module_path: "smithay::wayland::xdg_foreign" },
        SmithayRuntimeBinding { interface: "xdg_system_bell_v1", module_path: "smithay::wayland::xdg_system_bell" },
        SmithayRuntimeBinding { interface: "xdg_toplevel_icon_v1", module_path: "smithay::wayland::xdg_toplevel_icon" },
        SmithayRuntimeBinding { interface: "xdg_toplevel_tag_manager_v1", module_path: "smithay::wayland::xdg_toplevel_tag" },
        SmithayRuntimeBinding { interface: "zwp_linux_dmabuf_v1", module_path: "smithay::wayland::dmabuf" },
        SmithayRuntimeBinding { interface: "wp_presentation", module_path: "smithay::wayland::presentation" },
        SmithayRuntimeBinding { interface: "ext_foreign_toplevel_list_v1", module_path: "smithay::wayland::foreign_toplevel_list" },
        SmithayRuntimeBinding { interface: "wp_cursor_shape_manager_v1", module_path: "smithay::wayland::cursor_shape" },
        SmithayRuntimeBinding { interface: "zwp_pointer_constraints_v1", module_path: "smithay::wayland::pointer_constraints" },
        SmithayRuntimeBinding { interface: "zwp_pointer_gestures_v1", module_path: "smithay::wayland::pointer_gestures" },
        SmithayRuntimeBinding { interface: "zwp_relative_pointer_manager_v1", module_path: "smithay::wayland::relative_pointer" },
        SmithayRuntimeBinding { interface: "zwp_tablet_manager_v2", module_path: "smithay::wayland::tablet_manager" },
        SmithayRuntimeBinding { interface: "zwp_text_input_manager_v3", module_path: "smithay::wayland::text_input" },
        SmithayRuntimeBinding { interface: "zwp_input_method_manager_v2", module_path: "smithay::wayland::input_method" },
        SmithayRuntimeBinding { interface: "zwp_virtual_keyboard_manager_v1", module_path: "smithay::wayland::virtual_keyboard" },
        SmithayRuntimeBinding { interface: "zwlr_data_control_manager_v1", module_path: "smithay::wayland::selection::wlr_data_control" },
        SmithayRuntimeBinding { interface: "ext_data_control_manager_v1", module_path: "smithay::wayland::selection::ext_data_control" },
        SmithayRuntimeBinding { interface: "zwp_primary_selection_device_manager_v1", module_path: "smithay::wayland::selection::primary_selection" },
        SmithayRuntimeBinding { interface: "wp_fractional_scale_manager_v1", module_path: "smithay::wayland::fractional_scale" },
        SmithayRuntimeBinding { interface: "wp_viewporter", module_path: "smithay::wayland::viewporter" },
        SmithayRuntimeBinding { interface: "wp_single_pixel_buffer_manager_v1", module_path: "smithay::wayland::single_pixel_buffer" },
        SmithayRuntimeBinding { interface: "wp_alpha_modifier_v1", module_path: "smithay::wayland::alpha_modifier" },
        SmithayRuntimeBinding { interface: "wp_content_type_manager_v1", module_path: "smithay::wayland::content_type" },
        SmithayRuntimeBinding { interface: "wp_commit_timing_manager_v1", module_path: "smithay::wayland::commit_timing" },
        SmithayRuntimeBinding { interface: "wp_fifo_manager_v1", module_path: "smithay::wayland::fifo" },
        SmithayRuntimeBinding { interface: "ext_background_effect_manager_v1", module_path: "smithay::wayland::background_effect" },
        SmithayRuntimeBinding { interface: "zwp_idle_inhibit_manager_v1", module_path: "smithay::wayland::idle_inhibit" },
        SmithayRuntimeBinding { interface: "zwp_keyboard_shortcuts_inhibit_manager_v1", module_path: "smithay::wayland::keyboard_shortcuts_inhibit" },
        SmithayRuntimeBinding { interface: "ext_idle_notifier_v1", module_path: "smithay::wayland::idle_notify" },
        SmithayRuntimeBinding { interface: "wp_security_context_manager_v1", module_path: "smithay::wayland::security_context" },
        SmithayRuntimeBinding { interface: "ext_session_lock_manager_v1", module_path: "smithay::wayland::session_lock" },
        SmithayRuntimeBinding { interface: "xwayland_shell_v1", module_path: "smithay::wayland::xwayland_shell" },
        SmithayRuntimeBinding { interface: "zwp_xwayland_keyboard_grab_manager_v1", module_path: "smithay::wayland::xwayland_keyboard_grab" },
        SmithayRuntimeBinding { interface: "wp_drm_lease_device_v1", module_path: "smithay::wayland::drm_lease" },
        SmithayRuntimeBinding { interface: "wp_linux_drm_syncobj_manager_v1", module_path: "smithay::wayland::drm_syncobj" },
    ];

    /// Register Smithay-owned core + shell runtime globals.
    pub fn register_core_shell(state: &mut CompositorState, dh: &DisplayHandle) {
        if state.smithay_runtime.compositor.is_none() {
            state.smithay_runtime.compositor =
                Some(smithay::wayland::compositor::CompositorState::new_v6::<CompositorState>(dh));
        }
        if state.smithay_runtime.xdg_shell.is_none() {
            state.smithay_runtime.xdg_shell =
                Some(smithay::wayland::shell::xdg::XdgShellState::new::<CompositorState>(dh));
        }
        if state.smithay_runtime.shm.is_none() {
            state.smithay_runtime.shm =
                Some(smithay::wayland::shm::ShmState::new::<CompositorState>(dh, []));
        }
        if state.smithay_runtime.output_manager.is_none() {
            state.smithay_runtime.output_manager = Some(
                smithay::wayland::output::OutputManagerState::new_with_xdg_output::<CompositorState>(dh),
            );
        }
        if state.smithay_runtime.smithay_outputs.is_empty() {
            for output_state in &state.outputs {
                let output = smithay::output::Output::new(
                    output_state.name.clone(),
                    smithay::output::PhysicalProperties {
                        size: (
                            output_state.physical_width as i32,
                            output_state.physical_height as i32,
                        )
                            .into(),
                        subpixel: smithay::output::Subpixel::Unknown,
                        make: output_state.name.clone(),
                        model: output_state.name.clone(),
                    },
                );
                let _ = output.create_global::<CompositorState>(dh);
                state.smithay_runtime.smithay_outputs.push(output);
            }
        }
        if state.smithay_runtime.seat_state.is_none() {
            let mut seat_state = smithay::input::SeatState::<CompositorState>::new();
            let mut seat = seat_state.new_wl_seat(dh, "seat0");
            let _ = seat.add_pointer();
            #[cfg(not(any(
                target_os = "ios",
                target_os = "tvos",
                target_os = "visionos",
                target_os = "watchos"
            )))]
            let _ = seat.add_keyboard(
                smithay::input::keyboard::XkbConfig::default(),
                state.keyboard_repeat_delay,
                state.keyboard_repeat_rate,
            );
            state.smithay_runtime.seat_state = Some(seat_state);
            state.smithay_runtime.seat = Some(seat);
        }
        if state.smithay_runtime.data_device.is_none() {
            state.smithay_runtime.data_device = Some(
                smithay::wayland::selection::data_device::DataDeviceState::new::<CompositorState>(dh),
            );
        }
        state.smithay_runtime.core_shell_initialized = true;
    }

    /// Mark extension/wlr registration boundary as runtime initialized.
    pub fn register_extensions_wlr(state: &mut CompositorState) {
        state.smithay_runtime.extension_wlr_initialized = true;
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn core_shell_runtime_set_has_required_interfaces() {
            let required = [
                "wl_compositor",
                "wl_subcompositor",
                "wl_shm",
                "wl_seat",
                "wl_output",
                "zxdg_output_manager_v1",
                "wl_data_device_manager",
                "wl_fixes",
                "xdg_wm_base",
                "xdg_wm_dialog_v1",
                "zxdg_toplevel_decoration_v1",
            ];
            for iface in required {
                assert!(
                    SMITHAY_RUNTIME_BINDINGS
                        .iter()
                        .any(|entry| entry.interface == iface),
                    "missing core/shell runtime binding for {iface}"
                );
            }
        }

        #[test]
        fn extension_runtime_set_has_required_interfaces() {
            let required = [
                "zwp_linux_dmabuf_v1",
                "wp_presentation",
                "ext_data_control_manager_v1",
                "zwlr_data_control_manager_v1",
                "wp_fractional_scale_manager_v1",
                "wp_viewporter",
                "wp_content_type_manager_v1",
                "zwp_idle_inhibit_manager_v1",
                "wp_security_context_manager_v1",
                "ext_session_lock_manager_v1",
            ];
            for iface in required {
                assert!(
                    SMITHAY_RUNTIME_BINDINGS
                        .iter()
                        .any(|entry| entry.interface == iface),
                    "missing extension runtime binding for {iface}"
                );
            }
        }
    }
}

// Re-exports for common types if needed
pub use wayland::display::WawonaDisplay as WaylandDisplay;
pub use crate::core::state::CompositorState as CompositorData;
pub use crate::core::state::OutputState as OutputData;
// SeatData is in state.rs too
pub use crate::core::state::SeatState as SeatData;

pub mod presentation_time {
    pub use crate::core::wayland::ext::presentation_time::*;
}

/// Wayland protocol exposure policy and canonical manifest.
pub mod policy {
    /// Runtime protocol exposure profile.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum ProtocolProfile {
        /// Store-compliant local profile for Apple/Play distributions.
        StoreSafe,
        /// Store-compliant profile intended for remote-heavy workflows.
        StoreSafeRemote,
        /// Non-store desktop distribution profile.
        DesktopHost,
        /// Internal development profile (superset).
        FullDev,
    }

    impl ProtocolProfile {
        /// Parse profile name from string.
        pub fn from_str(raw: &str) -> Option<Self> {
            match raw {
                "store-safe" => Some(Self::StoreSafe),
                "store-safe-remote" => Some(Self::StoreSafeRemote),
                "desktop-host" => Some(Self::DesktopHost),
                "full-dev" => Some(Self::FullDev),
                _ => None,
            }
        }

        /// Stable profile identifier.
        pub fn as_str(self) -> &'static str {
            match self {
                Self::StoreSafe => "store-safe",
                Self::StoreSafeRemote => "store-safe-remote",
                Self::DesktopHost => "desktop-host",
                Self::FullDev => "full-dev",
            }
        }
    }

    impl Default for ProtocolProfile {
        fn default() -> Self {
            if cfg!(feature = "profile-store-safe-remote") {
                Self::StoreSafeRemote
            } else if cfg!(feature = "profile-store-safe") {
                Self::StoreSafe
            } else if cfg!(feature = "profile-full-dev") {
                Self::FullDev
            } else {
                // Keep desktop host as baseline for developer builds.
                Self::DesktopHost
            }
        }
    }

    /// Policy category for a protocol.
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum ExposureClass {
        StoreSafeCore,
        StoreSafeConditional,
        DesktopOnly,
        InternalOnly,
    }

    /// Canonical manifest entry.
    #[derive(Debug, Clone, Copy)]
    pub struct ProtocolManifestEntry {
        pub interface: &'static str,
        pub smithay_module: &'static str,
        pub exposure: ExposureClass,
        pub notes: &'static str,
    }

    /// Canonical protocol manifest used by compliance tooling and tests.
    pub const PROTOCOL_MANIFEST: &[ProtocolManifestEntry] = &[
        ProtocolManifestEntry {
            interface: "wl_compositor",
            smithay_module: "wayland::compositor",
            exposure: ExposureClass::StoreSafeCore,
            notes: "Core compositor object",
        },
        ProtocolManifestEntry {
            interface: "wl_shm",
            smithay_module: "wayland::shm",
            exposure: ExposureClass::StoreSafeCore,
            notes: "Core shared-memory buffers",
        },
        ProtocolManifestEntry {
            interface: "wl_output",
            smithay_module: "wayland::output",
            exposure: ExposureClass::StoreSafeCore,
            notes: "Core output advertising",
        },
        ProtocolManifestEntry {
            interface: "wl_seat",
            smithay_module: "wayland::seat",
            exposure: ExposureClass::StoreSafeCore,
            notes: "Core input seat",
        },
        ProtocolManifestEntry {
            interface: "xdg_wm_base",
            smithay_module: "wayland::shell::xdg",
            exposure: ExposureClass::StoreSafeCore,
            notes: "Baseline desktop shell role support",
        },
        ProtocolManifestEntry {
            interface: "zwlr_layer_shell_v1",
            smithay_module: "wayland::shell::wlr_layer",
            exposure: ExposureClass::StoreSafeConditional,
            notes: "Enable with explicit UX policy in store profiles",
        },
        ProtocolManifestEntry {
            interface: "zwlr_screencopy_manager_v1",
            smithay_module: "wayland::image_copy_capture / wlr equivalent",
            exposure: ExposureClass::DesktopOnly,
            notes: "Screen capture restricted from store-safe profiles",
        },
        ProtocolManifestEntry {
            interface: "zwlr_export_dmabuf_manager_v1",
            smithay_module: "wayland::dmabuf / export path",
            exposure: ExposureClass::DesktopOnly,
            notes: "Buffer export restricted from store-safe profiles",
        },
        ProtocolManifestEntry {
            interface: "zwlr_virtual_pointer_manager_v1",
            smithay_module: "wayland::virtual_pointer",
            exposure: ExposureClass::DesktopOnly,
            notes: "Synthetic input restricted from store-safe profiles",
        },
        ProtocolManifestEntry {
            interface: "zwp_virtual_keyboard_manager_v1",
            smithay_module: "wayland::virtual_keyboard",
            exposure: ExposureClass::DesktopOnly,
            notes: "Synthetic keyboard restricted from store-safe profiles",
        },
        ProtocolManifestEntry {
            interface: "zwlr_data_control_manager_v1",
            smithay_module: "wayland::selection::wlr_data_control",
            exposure: ExposureClass::DesktopOnly,
            notes: "Clipboard-manager class protocol",
        },
        ProtocolManifestEntry {
            interface: "ext_data_control_manager_v1",
            smithay_module: "wayland::selection::ext_data_control",
            exposure: ExposureClass::StoreSafeConditional,
            notes: "Allowed only with strict consent/data policy",
        },
        ProtocolManifestEntry {
            interface: "xwayland_shell_v1",
            smithay_module: "wayland::xwayland_shell",
            exposure: ExposureClass::DesktopOnly,
            notes: "Desktop/X11 interoperability only",
        },
        ProtocolManifestEntry {
            interface: "wp_drm_lease_device_v1",
            smithay_module: "wayland::drm_lease",
            exposure: ExposureClass::DesktopOnly,
            notes: "Linux DRM only",
        },
        ProtocolManifestEntry {
            interface: "wp_linux_drm_syncobj_manager_v1",
            smithay_module: "wayland::drm_syncobj",
            exposure: ExposureClass::DesktopOnly,
            notes: "Linux explicit sync object only",
        },
    ];

    /// Whether wlroots screencopy/export/virtual-input class protocols are allowed.
    pub fn allow_privileged_wlr(profile: ProtocolProfile) -> bool {
        matches!(profile, ProtocolProfile::DesktopHost | ProtocolProfile::FullDev)
    }

    /// Whether desktop-specific extension protocols are allowed.
    pub fn allow_desktop_extensions(profile: ProtocolProfile) -> bool {
        matches!(profile, ProtocolProfile::DesktopHost | ProtocolProfile::FullDev)
    }

    /// Whether KDE/Plasma non-smithay extension suite should be exposed.
    pub fn allow_plasma_extensions(profile: ProtocolProfile) -> bool {
        matches!(profile, ProtocolProfile::DesktopHost | ProtocolProfile::FullDev)
    }

    /// Resolve profile from env override if present.
    pub fn resolve_profile(default_profile: ProtocolProfile) -> ProtocolProfile {
        let raw = std::env::var("WAWONA_PROTOCOL_PROFILE").ok();
        raw.as_deref()
            .and_then(ProtocolProfile::from_str)
            .unwrap_or(default_profile)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn test_privileged_wlr_policy() {
            assert!(!allow_privileged_wlr(ProtocolProfile::StoreSafe));
            assert!(!allow_privileged_wlr(ProtocolProfile::StoreSafeRemote));
            assert!(allow_privileged_wlr(ProtocolProfile::DesktopHost));
            assert!(allow_privileged_wlr(ProtocolProfile::FullDev));
        }

        #[test]
        fn test_manifest_has_core_interfaces() {
            let has_wl = PROTOCOL_MANIFEST.iter().any(|e| e.interface == "wl_compositor");
            let has_xdg = PROTOCOL_MANIFEST.iter().any(|e| e.interface == "xdg_wm_base");
            assert!(has_wl, "manifest must include wl_compositor");
            assert!(has_xdg, "manifest must include xdg_wm_base");
        }
    }
}
