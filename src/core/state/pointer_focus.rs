//! `wl_pointer` focus and delivery for the compositor-global pointer.
//!
//! Hosts without a window system (the WLCS harness) drive one global
//! pointer. The compositor picks the surface under it and owns
//! enter/leave/motion. Re-picking also runs from surface commits, so a
//! surface that moves or restacks under a still pointer updates focus
//! before the client's next `wl_display.sync` completes.

use super::*;
use smithay::input::pointer::PointerHandle;
use wayland_server::protocol::wl_pointer;
use wayland_server::protocol::wl_surface::WlSurface;

/// One `wl_pointer` axis within a frame.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PointerAxisEvent {
    pub axis: wl_pointer::Axis,
    pub value: Option<f64>,
    pub discrete: Option<i32>,
    pub source: Option<wl_pointer::AxisSource>,
    pub stop: bool,
}

impl CompositorState {
    fn smithay_pointer(&self) -> Option<PointerHandle<Self>> {
        self.smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_pointer())
    }

    fn surface_resource(&self, surface_id: u32) -> Option<WlSurface> {
        self.surfaces
            .get(&surface_id)
            .and_then(|surface| surface.read().ok().and_then(|s| s.resource.clone()))
    }

    /// `wl_pointer.enter` to every pointer `client` bound. Returns the count.
    pub fn send_pointer_enter(
        &self,
        client: &wayland_server::Client,
        serial: u32,
        surface: &WlSurface,
        lx: f64,
        ly: f64,
    ) -> usize {
        let Some(pointer) = self.smithay_pointer() else {
            return 0;
        };
        let mut sent = 0;
        for ptr in pointer.client_pointers(client) {
            ptr.enter(serial, surface, lx, ly);
            sent += 1;
        }
        sent
    }

    /// `wl_pointer.leave` to every pointer `client` bound. Returns the count.
    pub fn send_pointer_leave(
        &self,
        client: &wayland_server::Client,
        serial: u32,
        surface: &WlSurface,
    ) -> usize {
        let Some(pointer) = self.smithay_pointer() else {
            return 0;
        };
        let mut sent = 0;
        for ptr in pointer.client_pointers(client) {
            ptr.leave(serial, surface);
            sent += 1;
        }
        sent
    }

    /// `wl_pointer.motion` to every pointer `client` bound. Returns the count.
    pub fn send_pointer_motion(
        &self,
        client: &wayland_server::Client,
        time: u32,
        lx: f64,
        ly: f64,
    ) -> usize {
        let Some(pointer) = self.smithay_pointer() else {
            return 0;
        };
        let mut sent = 0;
        for ptr in pointer.client_pointers(client) {
            ptr.motion(time, lx, ly);
            sent += 1;
        }
        sent
    }

    /// `wl_pointer.frame` to every v5+ pointer `client` bound. Smithay's own
    /// seat path gates the version; `client_pointers()` does not.
    pub fn send_pointer_frame(&self, client: &wayland_server::Client) -> usize {
        let Some(pointer) = self.smithay_pointer() else {
            return 0;
        };
        let mut sent = 0;
        for ptr in pointer.client_pointers(client) {
            if ptr.version() >= 5 {
                ptr.frame();
                sent += 1;
            }
        }
        sent
    }

    /// `wl_pointer.button` to every pointer `client` bound. Returns the count.
    pub fn send_pointer_button(
        &self,
        client: &wayland_server::Client,
        serial: u32,
        time: u32,
        button: u32,
        state: wayland_server::protocol::wl_pointer::ButtonState,
    ) -> usize {
        let Some(pointer) = self.smithay_pointer() else {
            return 0;
        };
        let mut sent = 0;
        for ptr in pointer.client_pointers(client) {
            ptr.button(serial, time, button, state);
            sent += 1;
        }
        sent
    }

    /// One axis event (with its optional source, discrete steps and stop) to
    /// every pointer `client` bound, gated by each `wl_pointer` version.
    pub fn send_pointer_axis(
        &self,
        client: &wayland_server::Client,
        time: u32,
        axis: &PointerAxisEvent,
    ) {
        let Some(pointer) = self.smithay_pointer() else {
            return;
        };
        for ptr in pointer.client_pointers(client) {
            let version = ptr.version();
            if version >= 5 {
                if let Some(source) = axis.source {
                    ptr.axis_source(source);
                }
            }
            if let Some(steps) = axis.discrete {
                if version >= 8 {
                    ptr.axis_value120(axis.axis, steps.saturating_mul(120));
                } else if version >= 5 {
                    ptr.axis_discrete(axis.axis, steps);
                }
            }
            if let Some(value) = axis.value {
                ptr.axis(time, axis.axis, value);
            }
            if axis.stop && version >= 5 {
                ptr.axis_stop(time, axis.axis);
            }
        }
    }

    /// Button at the global pointer for a headless host: a press focuses and
    /// raises the window under the pointer, and the implicit grab keeps the
    /// pressed surface focused until release.
    pub(crate) fn deliver_global_button(
        &mut self,
        button: u32,
        state: wayland_server::protocol::wl_pointer::ButtonState,
        time: u32,
    ) {
        use wayland_server::protocol::wl_pointer::ButtonState;
        if state == ButtonState::Pressed {
            let window = self
                .seat
                .pointer
                .global_target
                .and_then(|(surface, _, _)| u32::try_from(surface).ok())
                .and_then(|sid| self.root_window_of_surface(sid));
            if let Some(wid) = window {
                self.set_focused_window(Some(wid));
                self.window_tree.bring_to_front(wid);
            }
            self.seat.pointer.button_count += 1;
        } else {
            self.seat.pointer.button_count = self.seat.pointer.button_count.saturating_sub(1);
        }
        let serial = self.next_serial();
        self.seat.pointer.last_button_serial = serial;
        if let Some(client) = self.focused_pointer_client() {
            self.send_pointer_button(&client, serial, time, button, state);
        }
    }

    /// Deliver `wl_pointer.motion` + `frame` to the focused client.
    ///
    /// Prefers explicit `client_pointers()` delivery so clients that bind
    /// `wl_pointer` after an early enter still receive enter+motion.
    pub fn deliver_pointer_motion(&mut self, timestamp_ms: u32, lx: f64, ly: f64) {
        let focused_client = self.focused_pointer_client();
        if let Some(client) = focused_client.as_ref() {
            let mut sent = self.send_pointer_motion(client, timestamp_ms, lx, ly);
            if sent == 0 {
                let resource = self
                    .seat
                    .pointer
                    .focus
                    .and_then(|sid| self.surface_resource(sid));
                if let Some(res) = resource {
                    let enter_serial = self.next_serial();
                    sent = self.send_pointer_enter(client, enter_serial, &res, lx, ly);
                    if sent > 0 {
                        self.seat.pointer.last_enter_serial = enter_serial;
                        sent = self.send_pointer_motion(client, timestamp_ms, lx, ly);
                    }
                }
            }
            if sent > 0 {
                self.send_pointer_frame(client);
                return;
            }
        }
        if self.seat.pointer.resources.is_empty() {
            return;
        }
        self.seat
            .broadcast_pointer_motion(timestamp_ms, lx, ly, focused_client.as_ref());
        self.seat.broadcast_pointer_frame(focused_client.as_ref());
    }

    /// Move pointer focus to `target_sid` (any surface, including
    /// subsurfaces) at surface-local `(lx, ly)`: leave the old surface,
    /// enter the new one.
    pub fn focus_pointer_surface(&mut self, target_sid: u32, lx: f64, ly: f64, serial: u32) {
        if self.seat.pointer.focus == Some(target_sid) {
            return;
        }
        let old_sid = self.seat.pointer.focus;

        self.seat.pointer.focus = Some(target_sid);
        self.seat.pointer.focus_x = lx;
        self.seat.pointer.focus_y = ly;
        self.seat.pointer.last_enter_serial = serial;

        if let Some(res) = old_sid.and_then(|sid| self.surface_resource(sid)) {
            if let Some(client) = res.client() {
                if self.send_pointer_leave(&client, serial, &res) == 0 {
                    self.seat.broadcast_pointer_leave(serial, &res);
                }
            }
        }

        if let Some(res) = self.surface_resource(target_sid) {
            if let Some(client) = res.client() {
                if self.send_pointer_enter(&client, serial, &res, lx, ly) > 0 {
                    self.send_pointer_frame(&client);
                } else {
                    self.seat.broadcast_pointer_enter(serial, &res, lx, ly);
                }
            }
        }
        self.sync_pointer_constraints();
        self.deliver_pointer_motion(0, lx, ly);
    }

    /// Surface and surface-local position under a global point. While a
    /// button is held, the implicit grab keeps the pressed surface as the
    /// target. An interactive move/resize owns the pointer: no target.
    pub fn global_pointer_target(&mut self, x: f64, y: f64) -> Option<(u64, f64, f64)> {
        if self.seat.pointer.interactive_grab.is_some() {
            return None;
        }
        let grabbed = (self.seat.pointer.button_count > 0)
            .then_some(self.seat.pointer.global_target)
            .flatten()
            .map(|(surface, _, _)| u32::try_from(surface))
            .transpose()
            .ok()?;
        let (surface, lx, ly) = self.pointer_target_at_global(x, y, grabbed)?;
        Some((u64::from(surface), lx, ly))
    }

    /// Re-pick the surface under the global pointer and deliver
    /// enter/leave/motion for the result.
    pub fn deliver_global_pointer(&mut self, x: f64, y: f64, timestamp_ms: u32, serial: u32) {
        let target = self.global_pointer_target(x, y);
        let previous = std::mem::replace(&mut self.seat.pointer.global_target, target);
        match target {
            Some((surface, lx, ly)) => {
                let Ok(sid) = u32::try_from(surface) else {
                    return;
                };
                self.seat.cleanup_resources();
                self.seat.pointer.x = lx;
                self.seat.pointer.y = ly;
                self.focus_pointer_surface(sid, lx, ly, serial);
                self.seat.pointer.focus_x = lx;
                self.seat.pointer.focus_y = ly;
                self.deliver_pointer_motion(timestamp_ms, lx, ly);
            }
            None => {
                if previous.is_some() {
                    self.leave_global_pointer_focus(serial);
                }
            }
        }
    }

    /// The global pointer left every surface. An implicit grab keeps focus
    /// while a button is held.
    pub fn leave_global_pointer_focus(&mut self, serial: u32) {
        let Some(sid) = self.seat.pointer.focus else {
            return;
        };
        if self.seat.pointer.button_count > 0 {
            return;
        }
        self.leave_pointer_surface(sid, serial);
    }

    /// Re-deliver the global pointer when the surface or surface-local
    /// position under it changed without pointer motion (window moved,
    /// resized, mapped, unmapped, or a subsurface moved or restacked).
    /// `serial` is only drawn when something is delivered.
    pub fn repick_global_pointer(&mut self, timestamp_ms: u32, serial: &mut dyn FnMut() -> u32) {
        let Some((x, y)) = self.seat.pointer.global_position else {
            return;
        };
        if self.global_pointer_target(x, y) == self.seat.pointer.global_target {
            return;
        }
        let serial = serial();
        self.deliver_global_pointer(x, y, timestamp_ms, serial);
    }

    /// Commit-time re-pick for headless hosts.
    pub(crate) fn repick_global_pointer_after_commit(&mut self) {
        if !self.headless_host {
            return;
        }
        let Some((x, y)) = self.seat.pointer.global_position else {
            return;
        };
        if self.global_pointer_target(x, y) == self.seat.pointer.global_target {
            return;
        }
        let serial = self.next_serial();
        self.deliver_global_pointer(
            x,
            y,
            crate::core::compositor::Compositor::timestamp_ms(),
            serial,
        );
    }
}
