//! wlr-layer-shell-unstable-v1.
//!
//! Smithay's `wlr_layer` owns the protocol objects, the layer role, the
//! size/anchor validation (`invalid_size`) and configure/ack bookkeeping.
//! Wawona mirrors every layer surface in [`LayerSurface`] for arrangement
//! (anchors, margins, exclusive zones), stacking and keyboard
//! interactivity, and drives configures from that arrangement.

use smithay::reexports::wayland_server::protocol::{wl_output::WlOutput, wl_surface::WlSurface};
use smithay::wayland::compositor::with_states;
use smithay::wayland::shell::wlr_layer::{
    ExclusiveZone, KeyboardInteractivity, Layer, LayerSurface as SmithayLayerSurface,
    LayerSurfaceCachedState, LayerSurfaceData, WlrLayerShellHandler, WlrLayerShellState,
};
use smithay::wayland::shell::xdg::PopupSurface;
use std::sync::{Arc, RwLock};
use wayland_server::backend::ClientId;
use wayland_server::{DisplayHandle, Resource};

use crate::core::state::{CompositorState, LayerSurface};
use crate::core::surface::role::SurfaceRole;
use crate::util::geometry::Rect;

/// `zwlr_layer_shell_v1.layer` values.
pub const LAYER_TOP: u32 = 2;

/// `zwlr_layer_surface_v1.keyboard_interactivity` values.
pub const INTERACTIVITY_NONE: u32 = 0;
pub const INTERACTIVITY_EXCLUSIVE: u32 = 1;

const ANCHOR_TOP: u32 = 1;
const ANCHOR_BOTTOM: u32 = 2;
const ANCHOR_LEFT: u32 = 4;
const ANCHOR_RIGHT: u32 = 8;

fn layer_index(layer: Layer) -> u32 {
    match layer {
        Layer::Background => 0,
        Layer::Bottom => 1,
        Layer::Top => 2,
        Layer::Overlay => 3,
    }
}

fn interactivity_value(interactivity: KeyboardInteractivity) -> u32 {
    match interactivity {
        KeyboardInteractivity::None => 0,
        KeyboardInteractivity::Exclusive => 1,
        KeyboardInteractivity::OnDemand => 2,
    }
}

fn exclusive_zone_value(zone: ExclusiveZone) -> i32 {
    match zone {
        ExclusiveZone::Exclusive(n) => i32::try_from(n).unwrap_or(i32::MAX),
        ExclusiveZone::Neutral => 0,
        ExclusiveZone::DontCare => -1,
    }
}

/// Edge an exclusive zone is reserved against: a single anchored edge, or
/// that edge plus both perpendicular edges. Corner and opposite-edge
/// anchors reserve nothing.
pub fn exclusive_edge(anchor: u32) -> Option<u32> {
    let top = anchor & ANCHOR_TOP != 0;
    let bottom = anchor & ANCHOR_BOTTOM != 0;
    let left = anchor & ANCHOR_LEFT != 0;
    let right = anchor & ANCHOR_RIGHT != 0;
    if top == bottom {
        match (left, right) {
            (true, false) => Some(ANCHOR_LEFT),
            (false, true) => Some(ANCHOR_RIGHT),
            _ => None,
        }
    } else if left == right {
        if top {
            Some(ANCHOR_TOP)
        } else {
            Some(ANCHOR_BOTTOM)
        }
    } else {
        None
    }
}

/// Configure size for a layer surface inside `area`: the requested size, or
/// the area between the margins on an axis the surface stretches along
/// (anchored to both edges with a requested size of 0).
pub fn layer_configure_size(
    requested: (u32, u32),
    anchor: u32,
    margin: (i32, i32, i32, i32),
    area: &Rect,
) -> (u32, u32) {
    let (top, right, bottom, left) = margin;
    let stretch = |req: u32, both: bool, extent: u32, a: i32, b: i32| -> u32 {
        if req != 0 || !both {
            return req;
        }
        let extent = i64::from(extent) - i64::from(a) - i64::from(b);
        u32::try_from(extent.max(0)).unwrap_or(0)
    };
    let width = stretch(
        requested.0,
        anchor & ANCHOR_LEFT != 0 && anchor & ANCHOR_RIGHT != 0,
        area.width,
        left,
        right,
    );
    let height = stretch(
        requested.1,
        anchor & ANCHOR_TOP != 0 && anchor & ANCHOR_BOTTOM != 0,
        area.height,
        top,
        bottom,
    );
    (width, height)
}

/// Top-left of a `size` layer surface inside `area`: against the anchored
/// edge plus its margin (left/top win when both are anchored), else
/// centered.
pub fn layer_position(
    size: (u32, u32),
    anchor: u32,
    margin: (i32, i32, i32, i32),
    area: &Rect,
) -> (i32, i32) {
    let (top, right, bottom, left) = margin;
    let axis =
        |near: bool, far: bool, origin: i32, extent: u32, len: u32, m_near: i32, m_far: i32| {
            let extent = i64::from(extent);
            let len = i64::from(len);
            let origin = i64::from(origin);
            let pos = if near {
                origin + i64::from(m_near)
            } else if far {
                origin + extent - len - i64::from(m_far)
            } else {
                origin + (extent - len) / 2
            };
            i32::try_from(pos).unwrap_or(0)
        };
    (
        axis(
            anchor & ANCHOR_LEFT != 0,
            anchor & ANCHOR_RIGHT != 0,
            area.x,
            area.width,
            size.0,
            left,
            right,
        ),
        axis(
            anchor & ANCHOR_TOP != 0,
            anchor & ANCHOR_BOTTOM != 0,
            area.y,
            area.height,
            size.1,
            top,
            bottom,
        ),
    )
}

/// Shrink `usable` by an exclusive zone (zone plus the margin on that edge).
pub fn reserve_exclusive_zone(
    usable: &mut Rect,
    anchor: u32,
    zone: i32,
    margin: (i32, i32, i32, i32),
) {
    if zone <= 0 {
        return;
    }
    let Some(edge) = exclusive_edge(anchor) else {
        return;
    };
    let (top, right, bottom, left) = margin;
    let shrink =
        |len: u32, by: i32| u32::try_from((i64::from(len) - i64::from(by)).max(0)).unwrap_or(0);
    match edge {
        ANCHOR_TOP => {
            let by = zone.saturating_add(top);
            usable.y = usable.y.saturating_add(by);
            usable.height = shrink(usable.height, by);
        }
        ANCHOR_BOTTOM => usable.height = shrink(usable.height, zone.saturating_add(bottom)),
        ANCHOR_LEFT => {
            let by = zone.saturating_add(left);
            usable.x = usable.x.saturating_add(by);
            usable.width = shrink(usable.width, by);
        }
        _ => usable.width = shrink(usable.width, zone.saturating_add(right)),
    }
}

impl WlrLayerShellHandler for CompositorState {
    fn shell_state(&mut self) -> &mut WlrLayerShellState {
        self.smithay_runtime
            .layer_shell
            .as_mut()
            .expect("smithay layer shell state must be initialized before dispatch")
    }

    fn new_layer_surface(
        &mut self,
        surface: SmithayLayerSurface,
        output: Option<WlOutput>,
        layer: Layer,
        namespace: String,
    ) {
        let wl_surface = surface.wl_surface().clone();
        let Some(client_id) = wl_surface.client().map(|c| c.id()) else {
            return;
        };
        let surface_id = self.ensure_internal_surface_mapping(client_id.clone(), &wl_surface);
        let output_id = output
            .as_ref()
            .and_then(|o| self.output_id_by_resource.get(&o.id()).copied())
            .or_else(|| self.outputs.get(self.primary_output).map(|o| o.id))
            .unwrap_or(0);
        if let Some(surf) = self.get_surface(surface_id) {
            if let Ok(mut surf) = surf.write() {
                if let Err(e) = surf.set_role(SurfaceRole::Layer) {
                    tracing::warn!("Failed to set Layer role on surface {}: {}", surface_id, e);
                }
            }
        }
        let mut mirror = LayerSurface::new(surface_id, output_id, layer_index(layer), namespace);
        mirror.handle = Some(surface);
        self.add_layer_surface(client_id.clone(), mirror);
        self.wlr
            .surface_to_layer
            .insert((client_id, surface_id), surface_id);
    }

    fn new_popup(&mut self, parent: SmithayLayerSurface, popup: PopupSurface) {
        let Some(parent_id) = self.internal_surface_id(parent.wl_surface()) else {
            return;
        };
        let Some(client_id) = popup.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = popup.xdg_popup().id().protocol_id();
        // The xdg popup was created without a parent; constrain it again now
        // that its parent is this layer surface.
        let mut target = self.popup_target_rect();
        if let Some(ls) = self.layer_surface_for(parent_id) {
            if let Ok(ls) = ls.read() {
                target.loc.x -= ls.x;
                target.loc.y -= ls.y;
            }
        }
        let positioner = popup.with_pending_state(|state| state.positioner);
        let geo = positioner.get_unconstrained_geometry(target);
        popup.with_pending_state(|state| state.geometry = geo);
        let xdg_surface_id = self
            .xdg
            .popups
            .get_mut(&(client_id.clone(), popup_id))
            .map(|data| {
                data.parent_surface_id = Some(parent_id);
                data.geometry = (geo.loc.x, geo.loc.y, geo.size.w, geo.size.h);
                data.xdg_surface_id
            });
        match popup.send_configure() {
            Ok(serial) => {
                let pending =
                    xdg_surface_id.and_then(|id| self.xdg.surfaces.get_mut(&(client_id, id)));
                if let Some(surface_data) = pending {
                    surface_data.pending_serial = u32::from(serial);
                    surface_data.pending_serials.push(u32::from(serial));
                }
            }
            Err(err) => tracing::debug!("layer popup configure not sent: {err:?}"),
        }
    }

    fn layer_destroyed(&mut self, surface: SmithayLayerSurface) {
        let Some(key) = self.layer_key_for_handle(&surface) else {
            return;
        };
        self.wlr.layer_surfaces.remove(&key);
        self.wlr.surface_to_layer.remove(&key);
        self.reposition_layer_surfaces();
        self.refresh_layer_keyboard_focus();
    }
}

smithay::delegate_layer_shell!(CompositorState);

impl CompositorState {
    fn layer_key_for_handle(&self, surface: &SmithayLayerSurface) -> Option<(ClientId, u32)> {
        self.wlr.layer_surfaces.iter().find_map(|(key, ls)| {
            let ls = ls.read().ok()?;
            ls.handle
                .as_ref()
                .is_some_and(|h| h.shell_surface() == surface.shell_surface())
                .then(|| key.clone())
        })
    }

    /// Layer mirror for an internal surface id.
    pub(crate) fn layer_surface_for(&self, surface_id: u32) -> Option<Arc<RwLock<LayerSurface>>> {
        self.wlr
            .layer_surfaces
            .iter()
            .find(|((_, sid), _)| *sid == surface_id)
            .map(|(_, ls)| ls.clone())
    }

    fn surface_has_buffer(&self, surface_id: u32) -> bool {
        self.get_surface(surface_id)
            .and_then(|s| s.read().ok().map(|s| s.current.buffer_id.is_some()))
            .unwrap_or(false)
    }

    /// Layer part of a `wl_surface.commit`, after the surface state was
    /// applied. Smithay has already validated the size against the anchors.
    pub(crate) fn commit_layer_surface(&mut self, wl_surface: &WlSurface, surface_id: u32) {
        let Some(mirror) = self.layer_surface_for(surface_id) else {
            return;
        };
        let Some(handle) = mirror.read().ok().and_then(|ls| ls.handle.clone()) else {
            return;
        };
        let (cached, attrs) = with_states(wl_surface, |states| {
            let cached = *states
                .cached_state
                .get::<LayerSurfaceCachedState>()
                .current();
            let attrs = states
                .data_map
                .get::<LayerSurfaceData>()
                .and_then(|data| data.lock().ok().map(|a| a.initial_configure_sent));
            (cached, attrs)
        });
        let Some(initial_configure_sent) = attrs else {
            return;
        };
        // A buffer on the initial commit is tolerated (as Mir and wlroots
        // do): the surface is configured now and maps with that buffer.
        let mapped = self.surface_has_buffer(surface_id);
        let mut newly_mapped = false;
        if let Ok(mut ls) = mirror.write() {
            newly_mapped = mapped && !ls.mapped;
            ls.requested = (
                u32::try_from(cached.size.w).unwrap_or(0),
                u32::try_from(cached.size.h).unwrap_or(0),
            );
            ls.anchor = cached.anchor.bits();
            ls.margin = (
                cached.margin.top,
                cached.margin.right,
                cached.margin.bottom,
                cached.margin.left,
            );
            ls.exclusive_zone = exclusive_zone_value(cached.exclusive_zone);
            ls.interactivity = interactivity_value(cached.keyboard_interactivity);
            ls.layer = layer_index(cached.layer);
            ls.initialized = true;
            ls.mapped = mapped;
        }
        if !initial_configure_sent {
            self.reposition_layer_surfaces();
            if let Ok(ls) = mirror.read() {
                let size = (ls.width, ls.height);
                handle.with_pending_state(|state| {
                    state.size = Some(
                        (
                            i32::try_from(size.0).unwrap_or(0),
                            i32::try_from(size.1).unwrap_or(0),
                        )
                            .into(),
                    );
                });
            }
            handle.send_configure();
        } else {
            self.reposition_layer_surfaces();
        }
        // An on-demand surface takes focus when it maps, like a new window.
        if newly_mapped && self.layer_takes_click_focus(surface_id) {
            self.set_keyboard_focus_surface(Some(surface_id));
        }
        self.refresh_layer_keyboard_focus();
    }

    /// Mapped layer surface that holds the keyboard exclusively: exclusive
    /// interactivity on the top or overlay layer, highest layer first.
    pub(crate) fn exclusive_layer_focus(&self) -> Option<u32> {
        self.wlr
            .layer_surfaces
            .values()
            .filter_map(|ls| {
                let ls = ls.read().ok()?;
                (ls.mapped && ls.interactivity == INTERACTIVITY_EXCLUSIVE && ls.layer >= LAYER_TOP)
                    .then_some((ls.layer, ls.surface_id))
            })
            .max()
            .map(|(_, sid)| sid)
    }

    /// Whether a click may give `surface_id` (a layer surface) keyboard focus.
    pub(crate) fn layer_takes_click_focus(&self, surface_id: u32) -> bool {
        self.layer_surface_for(surface_id)
            .and_then(|ls| {
                ls.read()
                    .ok()
                    .map(|ls| ls.mapped && ls.interactivity != INTERACTIVITY_NONE)
            })
            .unwrap_or(false)
    }

    /// Re-evaluate keyboard focus after a layer surface changed: an
    /// exclusive layer surface takes it; a layer surface that no longer
    /// accepts focus returns it to the focused window.
    pub(crate) fn refresh_layer_keyboard_focus(&mut self) {
        if let Some(sid) = self.exclusive_layer_focus() {
            self.set_keyboard_focus_surface(Some(sid));
            return;
        }
        let Some(current) = self.seat.keyboard.focus else {
            return;
        };
        let is_layer = self
            .wlr
            .surface_to_layer
            .keys()
            .any(|(_, sid)| *sid == current);
        let lost_layer = !is_layer
            && self.surfaces.get(&current).is_some_and(|s| {
                s.read()
                    .map(|s| s.role == SurfaceRole::Layer)
                    .unwrap_or(false)
            });
        if (is_layer && !self.layer_takes_click_focus(current)) || lost_layer {
            let target = self
                .focus
                .keyboard_focus
                .and_then(|wid| self.windows.get(&wid))
                .and_then(|w| w.read().ok().map(|w| w.surface_id));
            self.set_keyboard_focus_surface(target);
        }
    }
}

/// Register zwlr_layer_shell_v1 through Smithay.
pub fn register_layer_shell(state: &mut CompositorState, display: &DisplayHandle) {
    state.smithay_runtime.layer_shell = Some(WlrLayerShellState::new::<CompositorState>(display));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn area() -> Rect {
        Rect::new(0, 0, 1000, 800)
    }

    #[test]
    fn requested_size_wins_even_when_anchored_to_all_edges() {
        let size = layer_configure_size((321, 218), 15, (0, 0, 0, 0), &area());
        assert_eq!(size, (321, 218));
    }

    #[test]
    fn zero_size_stretches_between_margins_when_anchored_to_both_edges() {
        let size = layer_configure_size((0, 0), 15, (12, 9, 15, 6), &area());
        assert_eq!(size, (1000 - 6 - 9, 800 - 12 - 15));
    }

    #[test]
    fn unanchored_surface_is_centered() {
        assert_eq!(
            layer_position((200, 300), 0, (1, 2, 3, 4), &area()),
            (400, 250)
        );
    }

    #[test]
    fn right_bottom_anchor_uses_far_margins() {
        let pos = layer_position(
            (200, 300),
            ANCHOR_RIGHT | ANCHOR_BOTTOM,
            (12, 9, 15, 6),
            &area(),
        );
        assert_eq!(pos, (1000 - 200 - 9, 800 - 300 - 15));
    }

    #[test]
    fn corner_anchor_reserves_no_exclusive_zone() {
        let mut usable = area();
        reserve_exclusive_zone(&mut usable, ANCHOR_TOP | ANCHOR_LEFT, 25, (0, 0, 0, 0));
        assert_eq!(
            (usable.x, usable.y, usable.width, usable.height),
            (0, 0, 1000, 800)
        );
    }

    #[test]
    fn top_edge_reserves_zone_plus_margin() {
        let mut usable = area();
        reserve_exclusive_zone(
            &mut usable,
            ANCHOR_TOP | ANCHOR_LEFT | ANCHOR_RIGHT,
            25,
            (12, 0, 0, 0),
        );
        assert_eq!(
            (usable.x, usable.y, usable.width, usable.height),
            (0, 37, 1000, 763)
        );
    }

    #[test]
    fn negative_zone_reserves_nothing() {
        let mut usable = area();
        reserve_exclusive_zone(&mut usable, ANCHOR_LEFT, -1, (0, 0, 0, 0));
        assert_eq!(usable.width, 1000);
    }
}
