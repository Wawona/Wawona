//! Tablet protocol implementation.
//!
//! This protocol provides support for graphics tablets with pressure-sensitive
//! styluses and other advanced input features.

use wayland_protocols::wp::tablet::zv2::server::{
    zwp_tablet_manager_v2::{self, ZwpTabletManagerV2},
    zwp_tablet_pad_group_v2::{self, ZwpTabletPadGroupV2},
    zwp_tablet_pad_ring_v2::{self, ZwpTabletPadRingV2},
    zwp_tablet_pad_strip_v2::{self, ZwpTabletPadStripV2},
    zwp_tablet_pad_v2::{self, ZwpTabletPadV2},
    zwp_tablet_seat_v2::{self, ZwpTabletSeatV2},
    zwp_tablet_tool_v2::{self, ZwpTabletToolV2},
    zwp_tablet_v2::{self, ZwpTabletV2},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone, Default)]
pub struct TabletSeatData {
    pub seat_id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct TabletData {
    pub id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct TabletToolData {
    pub id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct TabletPadData {
    pub id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct TabletPadRingData;

#[derive(Debug, Clone, Default)]
pub struct TabletPadStripData;

#[derive(Debug, Clone, Default)]
pub struct TabletPadGroupData;

// ============================================================================
// zwp_tablet_manager_v2
// ============================================================================

impl GlobalDispatch<ZwpTabletManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTabletManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_tablet_manager_v2");
    }
}

impl Dispatch<ZwpTabletManagerV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletManagerV2,
        request: zwp_tablet_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_manager_v2::Request::GetTabletSeat { tablet_seat, seat } => {
                let seat_id = seat.id().protocol_id();
                // let data = TabletSeatData { seat_id };
                let _tablet_seat = data_init.init(tablet_seat, ());
                tracing::debug!("Created tablet seat for seat {}", seat_id);
            }
            zwp_tablet_manager_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_manager_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_seat_v2
// ============================================================================

impl Dispatch<ZwpTabletSeatV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletSeatV2,
        request: zwp_tablet_seat_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_seat_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_seat_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_v2
// ============================================================================

impl Dispatch<ZwpTabletV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletV2,
        request: zwp_tablet_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_tool_v2
// ============================================================================

impl Dispatch<ZwpTabletToolV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletToolV2,
        request: zwp_tablet_tool_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_tool_v2::Request::SetCursor {
                serial,
                surface,
                hotspot_x,
                hotspot_y,
            } => {
                tracing::debug!(
                    "Tablet tool set cursor: serial={}, hotspot=({}, {})",
                    serial,
                    hotspot_x,
                    hotspot_y
                );
                let _ = surface;
            }
            zwp_tablet_tool_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_tool_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_pad_v2
// ============================================================================

impl Dispatch<ZwpTabletPadV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletPadV2,
        request: zwp_tablet_pad_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_pad_v2::Request::SetFeedback {
                button,
                description,
                serial,
            } => {
                tracing::debug!(
                    "Tablet pad feedback: button={}, desc={}, serial={}",
                    button,
                    description,
                    serial
                );
            }
            zwp_tablet_pad_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_pad_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_pad_ring_v2
// ============================================================================

impl Dispatch<ZwpTabletPadRingV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletPadRingV2,
        request: zwp_tablet_pad_ring_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_pad_ring_v2::Request::SetFeedback {
                description,
                serial,
            } => {
                tracing::debug!(
                    "Tablet pad ring feedback: desc={}, serial={}",
                    description,
                    serial
                );
            }
            zwp_tablet_pad_ring_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_pad_ring_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_pad_strip_v2
// ============================================================================

impl Dispatch<ZwpTabletPadStripV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletPadStripV2,
        request: zwp_tablet_pad_strip_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_pad_strip_v2::Request::SetFeedback {
                description,
                serial,
            } => {
                tracing::debug!(
                    "Tablet pad strip feedback: desc={}, serial={}",
                    description,
                    serial
                );
            }
            zwp_tablet_pad_strip_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_pad_strip_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_tablet_pad_group_v2
// ============================================================================

impl Dispatch<ZwpTabletPadGroupV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpTabletPadGroupV2,
        request: zwp_tablet_pad_group_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_tablet_pad_group_v2::Request::Destroy => {
                tracing::debug!("zwp_tablet_pad_group_v2 destroyed");
            }
            _ => {}
        }
    }
}

/// Register zwp_tablet_manager_v2 global
pub fn register_tablet(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpTabletManagerV2, ()>(1, ())
}
