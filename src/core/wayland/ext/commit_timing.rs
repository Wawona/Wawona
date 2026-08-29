//! Commit Timing protocol implementation.
//!
//! This protocol allows clients to specify a target presentation time
//! for their next commit. The compositor can use this to schedule
//! frame presentation more precisely (e.g., for video playback).

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::commit_timing::v1::server::{
    wp_commit_timing_manager_v1::{self, WpCommitTimingManagerV1},
    wp_commit_timer_v1::{self, WpCommitTimerV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Stores target presentation timestamps per surface
#[derive(Debug, Clone, Default)]
pub struct CommitTimingState {
    /// surface_id → target presentation time in nanoseconds
    pub target_times: HashMap<u32, u64>,
}

impl CommitTimingState {
    /// Get the target presentation time for a surface (if set)
    pub fn get_target_ns(&self, surface_id: u32) -> Option<u64> {
        self.target_times.get(&surface_id).copied()
    }

    /// Clear the target time (after it's been consumed by the frame scheduler)
    pub fn consume(&mut self, surface_id: u32) -> Option<u64> {
        self.target_times.remove(&surface_id)
    }
}

// ============================================================================
// wp_commit_timing_manager_v1
// ============================================================================

impl GlobalDispatch<WpCommitTimingManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpCommitTimingManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_commit_timing_manager_v1");
    }
}

impl Dispatch<WpCommitTimingManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpCommitTimingManagerV1,
        request: wp_commit_timing_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_commit_timing_manager_v1::Request::GetTimer { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _timer = data_init.init(id, surface_id);
                tracing::debug!("Created commit timer for surface {}", surface_id);
            }
            wp_commit_timing_manager_v1::Request::Destroy => {
                tracing::debug!("wp_commit_timing_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_commit_timer_v1. User data is surface_id: u32
// ============================================================================

impl Dispatch<WpCommitTimerV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpCommitTimerV1,
        request: wp_commit_timer_v1::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_commit_timer_v1::Request::SetTimestamp { tv_sec_hi, tv_sec_lo, tv_nsec } => {
                let secs = ((tv_sec_hi as u64) << 32) | (tv_sec_lo as u64);
                let total_ns = secs * 1_000_000_000 + tv_nsec as u64;
                state.ext.commit_timing.target_times.insert(*surface_id, total_ns);
                tracing::debug!("Surface {} target presentation: {}.{:09}s", surface_id, secs, tv_nsec);
            }
            wp_commit_timer_v1::Request::Destroy => {
                state.ext.commit_timing.target_times.remove(surface_id);
                tracing::debug!("Commit timer destroyed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

/// Register wp_commit_timing_manager_v1 global
pub fn register_commit_timing(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpCommitTimingManagerV1, ()>(1, ())
}
