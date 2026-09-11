use crate::core::wayland::protocol::server::wp::presentation_time::server::{
    wp_presentation, wp_presentation_feedback,
};
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;

/// Presentation time global
pub struct PresentationTimeGlobal;

/// Presentation feedback callback
#[derive(Debug)]
pub struct PresentationFeedback {
    pub surface_id: u32,
    pub callback: wp_presentation_feedback::WpPresentationFeedback,
    pub committed: bool,
}

#[derive(Debug)]
pub struct PresentationState {
    pub feedbacks: Vec<PresentationFeedback>,
    pub next_seq: u64,
}

impl PresentationState {
    pub fn mark_committed(&mut self, surface_id: u32) {
        for feedback in &mut self.feedbacks {
            if feedback.surface_id == surface_id {
                feedback.committed = true;
            }
        }
    }

    pub fn send_presented_events(&mut self, timestamp_ns: u64, refresh_ns: u64, seq: u64) {
        let tv_sec = timestamp_ns / 1_000_000_000;
        let tv_nsec = (timestamp_ns % 1_000_000_000) as u32;
        let tv_sec_hi = (tv_sec >> 32) as u32;
        let tv_sec_lo = (tv_sec & 0xFFFF_FFFF) as u32;

        let mut i = 0;
        while i < self.feedbacks.len() {
            if self.feedbacks[i].committed {
                let feedback = self.feedbacks.remove(i);
                feedback.callback.presented(
                    tv_sec_hi,
                    tv_sec_lo,
                    tv_nsec,
                    refresh_ns as u32,
                    (seq >> 32) as u32,
                    (seq & 0xFFFFFFFF) as u32,
                    wp_presentation_feedback::Kind::Vsync,
                );
            } else {
                i += 1;
            }
        }
    }
}

impl Default for PresentationState {
    fn default() -> Self {
        Self {
            feedbacks: Vec::new(),
            next_seq: 1,
        }
    }
}

impl GlobalDispatch<wp_presentation::WpPresentation, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wp_presentation::WpPresentation>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let presentation = data_init.init(resource, ());
        // CLOCK_MONOTONIC = 1 on Linux/Darwin.  The protocol requires
        // clock_id to be sent before any presented event so clients
        // (notably waypipe) know which clock domain timestamps use.
        presentation.clock_id(1);
    }
}

impl Dispatch<wp_presentation::WpPresentation, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wp_presentation::WpPresentation,
        request: wp_presentation::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wp_presentation::Request::Feedback { surface, callback } => {
                let surface_id = surface
                    .data::<u32>()
                    .copied()
                    .unwrap_or_else(|| surface.id().protocol_id());

                let feedback_resource: wp_presentation_feedback::WpPresentationFeedback =
                    data_init.init(callback, ());

                state.ext.presentation.feedbacks.push(PresentationFeedback {
                    surface_id,
                    callback: feedback_resource,
                    committed: false, // Will be marked true on surface commit
                });
            }
            wp_presentation::Request::Destroy => {
                let client_id = _client.id();
                state.ext.presentation.feedbacks.retain(|f| {
                    f.callback
                        .client()
                        .map(|c| c.id() != client_id)
                        .unwrap_or(false)
                });
            }
            _ => {}
        }
    }
}

impl Dispatch<wp_presentation_feedback::WpPresentationFeedback, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wp_presentation_feedback::WpPresentationFeedback,
        _request: wp_presentation_feedback::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
    }
}

/// Register wp_presentation global
pub fn register_presentation_time(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, wp_presentation::WpPresentation, ()>(1, ())
}
