//! Request-time xdg-shell validation that Smithay 0.7 does not perform.
//!
//! `xdg_wm_base.get_xdg_surface` must reject a `wl_surface` that already has
//! a role (`role`) or a buffer attached or committed (`invalid_surface_state`),
//! and `wl_surface.attach` must reject a buffer on an `xdg_surface` that has
//! not been sent its initial configure (`xdg_surface.unconfigured_buffer`).
//! Smithay checks none of these at request time, so `xdg_wm_base` and
//! `wl_surface` dispatch run through the wrappers below before forwarding to
//! Smithay's own handlers.

use smithay::reexports::wayland_protocols::xdg::decoration::zv1::server::{
    zxdg_decoration_manager_v1::{self, ZxdgDecorationManagerV1},
    zxdg_toplevel_decoration_v1::{self, ZxdgToplevelDecorationV1},
};
use smithay::reexports::wayland_protocols::xdg::shell::server::{
    xdg_popup::{self, XdgPopup},
    xdg_positioner::{self, XdgPositioner},
    xdg_surface::{self, XdgSurface},
    xdg_toplevel::{self, XdgToplevel},
    xdg_wm_base::{self, XdgWmBase},
};
use smithay::reexports::wayland_server::{
    backend::ClientId,
    protocol::wl_surface::{self, WlSurface},
    Client, DataInit, Dispatch, DisplayHandle, Resource,
};
use smithay::wayland::compositor::{self, BufferAssignment, SurfaceAttributes, SurfaceUserData};
use smithay::wayland::shell::xdg::decoration::XdgDecorationState;
use smithay::wayland::shell::xdg::{
    PositionerState, XdgPopupSurfaceData, XdgPositionerUserData, XdgShellState,
    XdgShellSurfaceUserData, XdgSurfaceUserData, XdgToplevelSurfaceData, XdgWmBaseUserData,
    XDG_POPUP_ROLE, XDG_TOPLEVEL_ROLE,
};

use crate::core::state::CompositorState;
use crate::core::surface::BufferType;

type SmithayCompositor = smithay::wayland::compositor::CompositorState;

/// Protocol id of a client-created object, read from the `Debug` rendering of
/// its `New<I>` (`xdg_surface@12[3]`). `wayland-server` exposes no accessor
/// before `DataInit::init`, which Smithay performs internally.
pub(crate) fn new_object_protocol_id(debug: &str, interface: &str) -> Option<u32> {
    let needle = format!("{interface}@");
    let start = debug.find(&needle)? + needle.len();
    let rest = &debug[start..];
    let end = rest
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(rest.len());
    rest[..end].parse().ok().filter(|&id| id != 0)
}

impl CompositorState {
    fn xdg_surface_creation_error(
        &self,
        surface: &WlSurface,
    ) -> Option<(xdg_wm_base::Error, &'static str)> {
        let foreign_role = compositor::get_role(surface)
            .is_some_and(|role| role != XDG_TOPLEVEL_ROLE && role != XDG_POPUP_ROLE);
        let live_xdg_surface = self
            .xdg_surface_objects
            .get(&surface.id())
            .is_some_and(|xdg| xdg.is_alive());
        if foreign_role || live_xdg_surface {
            return Some((xdg_wm_base::Error::Role, "wl_surface already has a role"));
        }
        let pending_buffer = compositor::with_states(surface, |states| {
            matches!(
                states
                    .cached_state
                    .get::<SurfaceAttributes>()
                    .pending()
                    .buffer,
                Some(BufferAssignment::NewBuffer(_))
            )
        });
        let committed_buffer = surface
            .client()
            .and_then(|client| {
                self.protocol_to_internal_surface
                    .get(&(client.id(), surface.id().protocol_id()))
                    .copied()
            })
            .and_then(|id| self.get_surface(id))
            .is_some_and(|s| {
                s.read()
                    .map(|s| !matches!(s.current.buffer, BufferType::None))
                    .unwrap_or(false)
            });
        (pending_buffer || committed_buffer).then_some((
            xdg_wm_base::Error::InvalidSurfaceState,
            "wl_surface has a buffer attached or committed",
        ))
    }

    fn unconfigured_xdg_surface(&self, surface: &WlSurface) -> Option<XdgSurface> {
        let xdg = self.xdg_surface_objects.get(&surface.id())?;
        if !xdg.is_alive() {
            return None;
        }
        let configured = compositor::with_states(surface, |states| {
            if let Some(data) = states.data_map.get::<XdgToplevelSurfaceData>() {
                return data.lock().is_ok_and(|d| d.initial_configure_sent);
            }
            if let Some(data) = states.data_map.get::<XdgPopupSurfaceData>() {
                return data.lock().is_ok_and(|d| d.initial_configure_sent);
            }
            false
        });
        (!configured).then(|| xdg.clone())
    }
}

impl Dispatch<XdgWmBase, XdgWmBaseUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &XdgWmBase,
        request: xdg_wm_base::Request,
        data: &XdgWmBaseUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let mut created = None;
        let mut error = None;
        if let xdg_wm_base::Request::GetXdgSurface { id, surface } = &request {
            error = state.xdg_surface_creation_error(surface);
            created = Some((
                surface.id(),
                new_object_protocol_id(&format!("{id:?}"), "xdg_surface"),
            ));
        }

        <XdgShellState as Dispatch<XdgWmBase, XdgWmBaseUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );

        if let Some((code, message)) = error {
            resource.post_error(code, message);
            return;
        }
        if let Some((surface_id, Some(protocol_id))) = created {
            if let Ok(xdg) = client.object_from_protocol_id::<XdgSurface>(dhandle, protocol_id) {
                state.xdg_surface_objects.insert(surface_id, xdg);
            }
        }
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &XdgWmBase,
        data: &XdgWmBaseUserData,
    ) {
        <XdgShellState as Dispatch<XdgWmBase, XdgWmBaseUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<WlSurface, SurfaceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &WlSurface,
        request: wl_surface::Request,
        data: &SurfaceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let wl_surface::Request::Attach {
            buffer: Some(_), ..
        } = &request
        {
            if let Some(xdg) = state.unconfigured_xdg_surface(resource) {
                xdg.post_error(
                    xdg_surface::Error::UnconfiguredBuffer,
                    "buffer attached before the initial xdg_surface.configure",
                );
                return;
            }
        }
        // Smithay may apply this surface's state during the commit below, so
        // the children's positions must be captured first.
        if matches!(request, wl_surface::Request::Commit) {
            if let Some(surface_id) = state.internal_surface_id(resource) {
                state.capture_subsurface_positions(surface_id);
            }
        }
        <SmithayCompositor as Dispatch<WlSurface, SurfaceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
    }

    fn destroyed(state: &mut Self, client: ClientId, resource: &WlSurface, data: &SurfaceUserData) {
        state.xdg_surface_objects.remove(&resource.id());
        <SmithayCompositor as Dispatch<WlSurface, SurfaceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

/// Zero-width / zero-height axes of a positioner's anchor rect. xdg-shell only
/// rejects negative anchor sizes; Smithay 0.7 also rejects zero, so a zero
/// axis is forwarded as 1 and restored here before geometry is computed.
pub(crate) type ZeroAnchorAxes = (bool, bool);

pub(crate) fn restore_zero_anchor(
    mut positioner: PositionerState,
    axes: Option<ZeroAnchorAxes>,
) -> PositionerState {
    if let Some((zero_w, zero_h)) = axes {
        if zero_w {
            positioner.anchor_rect.size.w = 0;
        }
        if zero_h {
            positioner.anchor_rect.size.h = 0;
        }
    }
    positioner
}

impl Dispatch<XdgPositioner, XdgPositionerUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &XdgPositioner,
        request: xdg_positioner::Request,
        data: &XdgPositionerUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let request = match request {
            xdg_positioner::Request::SetAnchorRect {
                x,
                y,
                width,
                height,
            } if width >= 0 && height >= 0 => {
                if width == 0 || height == 0 {
                    state
                        .zero_anchor_positioners
                        .insert(resource.id(), (width == 0, height == 0));
                } else {
                    state.zero_anchor_positioners.remove(&resource.id());
                }
                xdg_positioner::Request::SetAnchorRect {
                    x,
                    y,
                    width: width.max(1),
                    height: height.max(1),
                }
            }
            other => other,
        };
        <XdgShellState as Dispatch<XdgPositioner, XdgPositionerUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &XdgPositioner,
        data: &XdgPositionerUserData,
    ) {
        state.zero_anchor_positioners.remove(&resource.id());
        <XdgShellState as Dispatch<XdgPositioner, XdgPositionerUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<XdgSurface, XdgSurfaceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &XdgSurface,
        request: xdg_surface::Request,
        data: &XdgSurfaceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let xdg_surface::Request::GetPopup { positioner, .. } = &request {
            state.pending_zero_anchor =
                state.zero_anchor_positioners.get(&positioner.id()).copied();
        }
        <XdgShellState as Dispatch<XdgSurface, XdgSurfaceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
        state.pending_zero_anchor = None;
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &XdgSurface,
        data: &XdgSurfaceUserData,
    ) {
        <XdgShellState as Dispatch<XdgSurface, XdgSurfaceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<XdgPopup, XdgShellSurfaceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &XdgPopup,
        request: xdg_popup::Request,
        data: &XdgShellSurfaceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let xdg_popup::Request::Reposition { positioner, .. } = &request {
            state.pending_zero_anchor =
                state.zero_anchor_positioners.get(&positioner.id()).copied();
        }
        <XdgShellState as Dispatch<XdgPopup, XdgShellSurfaceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
        state.pending_zero_anchor = None;
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &XdgPopup,
        data: &XdgShellSurfaceUserData,
    ) {
        <XdgShellState as Dispatch<XdgPopup, XdgShellSurfaceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<ZxdgDecorationManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZxdgDecorationManagerV1,
        request: zxdg_decoration_manager_v1::Request,
        data: &(),
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let created = match &request {
            zxdg_decoration_manager_v1::Request::GetToplevelDecoration { id, toplevel } => Some((
                toplevel.id(),
                new_object_protocol_id(&format!("{id:?}"), "zxdg_toplevel_decoration_v1"),
            )),
            _ => None,
        };
        <XdgDecorationState as Dispatch<ZxdgDecorationManagerV1, (), Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
        if let Some((toplevel_id, Some(protocol_id))) = created {
            if let Ok(decoration) =
                client.object_from_protocol_id::<ZxdgToplevelDecorationV1>(dhandle, protocol_id)
            {
                state
                    .toplevel_decorations
                    .insert(toplevel_id, (resource.clone(), decoration));
            }
        }
    }
}

impl Dispatch<XdgToplevel, XdgShellSurfaceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &XdgToplevel,
        request: xdg_toplevel::Request,
        data: &XdgShellSurfaceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        // zxdg_toplevel_decoration_v1: destroying the toplevel before its
        // decoration object is `orphaned`.
        let orphaned = matches!(request, xdg_toplevel::Request::Destroy)
            .then(|| state.toplevel_decorations.remove(&resource.id()))
            .flatten()
            .filter(|(_, decoration)| decoration.is_alive());
        <XdgShellState as Dispatch<XdgToplevel, XdgShellSurfaceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
        if let Some((manager, _)) = orphaned {
            manager.post_error(
                zxdg_toplevel_decoration_v1::Error::Orphaned as u32,
                "xdg_toplevel destroyed before its decoration object",
            );
        }
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &XdgToplevel,
        data: &XdgShellSurfaceUserData,
    ) {
        state.toplevel_decorations.remove(&resource.id());
        <XdgShellState as Dispatch<XdgToplevel, XdgShellSurfaceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::{new_object_protocol_id, restore_zero_anchor};
    use smithay::utils::Rectangle;
    use smithay::wayland::shell::xdg::PositionerState;

    fn positioner_with_anchor(w: i32, h: i32) -> PositionerState {
        PositionerState {
            anchor_rect: Rectangle::new((10, 20).into(), (w, h).into()),
            ..Default::default()
        }
    }

    #[test]
    fn zero_anchor_axes_restored() {
        let p = restore_zero_anchor(positioner_with_anchor(1, 1), Some((true, false)));
        assert_eq!((p.anchor_rect.size.w, p.anchor_rect.size.h), (0, 1));
        let p = restore_zero_anchor(positioner_with_anchor(1, 1), Some((true, true)));
        assert_eq!((p.anchor_rect.size.w, p.anchor_rect.size.h), (0, 0));
        assert_eq!((p.anchor_rect.loc.x, p.anchor_rect.loc.y), (10, 20));
    }

    #[test]
    fn non_zero_anchor_untouched() {
        let p = restore_zero_anchor(positioner_with_anchor(30, 40), None);
        assert_eq!((p.anchor_rect.size.w, p.anchor_rect.size.h), (30, 40));
    }

    #[test]
    fn reads_id_from_rs_backend_debug() {
        let debug = "New { id: XdgSurface { id: ObjectId(xdg_surface@12[3], 7), version: 6 } }";
        assert_eq!(new_object_protocol_id(debug, "xdg_surface"), Some(12));
    }

    #[test]
    fn rejects_missing_interface() {
        assert_eq!(
            new_object_protocol_id("New { id: wl_surface@4[1] }", "xdg_surface"),
            None
        );
    }

    #[test]
    fn rejects_null_and_non_numeric_ids() {
        assert_eq!(
            new_object_protocol_id("xdg_surface@0[1]", "xdg_surface"),
            None
        );
        assert_eq!(
            new_object_protocol_id("xdg_surface@[1]", "xdg_surface"),
            None
        );
        assert_eq!(new_object_protocol_id("xdg_surface@", "xdg_surface"), None);
    }

    #[test]
    fn rejects_overflowing_id() {
        assert_eq!(
            new_object_protocol_id("xdg_surface@99999999999[1]", "xdg_surface"),
            None
        );
    }
}
