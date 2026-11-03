//! Commit Timing protocol implementation.
//!
//! Clients set a target presentation time for the next commit. The compositor
//! latches that target on commit and must not present that content before the
//! target (hold-until-target).

use std::collections::HashMap;
use wayland_protocols::wp::commit_timing::v1::server::{
    wp_commit_timer_v1::{self, WpCommitTimerV1},
    wp_commit_timing_manager_v1::{self, WpCommitTimingManagerV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

use crate::core::wayland::protocol_proofs::commit_timing_hold_required;

/// Stores target presentation timestamps per surface.
#[derive(Debug, Clone, Default)]
pub struct CommitTimingState {
    /// surface_id → target presentation time in nanoseconds (pending, pre-commit)
    pub target_times: HashMap<u32, u64>,
    /// surface_id → earliest present time after latch (hold-until-target)
    pub held_until: HashMap<u32, u64>,
}

impl CommitTimingState {
    /// Latch a pending target on commit. Returns the hold deadline if still future.
    pub fn latch_on_commit(&mut self, surface_id: u32, now_ns: u64) -> Option<u64> {
        let target = self.target_times.remove(&surface_id)?;
        if commit_timing_hold_required(target, now_ns) {
            self.held_until.insert(surface_id, target);
            Some(target)
        } else {
            self.held_until.remove(&surface_id);
            None
        }
    }

    /// True while this surface's latched content must not present yet.
    pub fn is_held(&self, surface_id: u32, now_ns: u64) -> bool {
        self.held_until
            .get(&surface_id)
            .is_some_and(|t| commit_timing_hold_required(*t, now_ns))
    }

    /// Drop holds whose deadline has passed. Returns released surface ids.
    pub fn release_ready(&mut self, now_ns: u64) -> Vec<u32> {
        let ready: Vec<u32> = self
            .held_until
            .iter()
            .filter(|(_, t)| !commit_timing_hold_required(**t, now_ns))
            .map(|(s, _)| *s)
            .collect();
        for s in &ready {
            self.held_until.remove(s);
        }
        ready
    }
}

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
            wp_commit_timer_v1::Request::SetTimestamp {
                tv_sec_hi,
                tv_sec_lo,
                tv_nsec,
            } => {
                let secs = ((tv_sec_hi as u64) << 32) | (tv_sec_lo as u64);
                let total_ns = secs * 1_000_000_000 + tv_nsec as u64;
                state
                    .ext
                    .commit_timing
                    .target_times
                    .insert(*surface_id, total_ns);
                tracing::debug!(
                    "Surface {} target presentation: {}.{:09}s",
                    surface_id,
                    secs,
                    tv_nsec
                );
            }
            wp_commit_timer_v1::Request::Destroy => {
                state.ext.commit_timing.target_times.remove(surface_id);
                state.ext.commit_timing.held_until.remove(surface_id);
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hold_required_when_target_in_future() {
        assert!(commit_timing_hold_required(200, 100));
        assert!(!commit_timing_hold_required(100, 100));
        assert!(!commit_timing_hold_required(50, 100));
    }

    #[test]
    fn latch_holds_future_target() {
        let mut st = CommitTimingState::default();
        st.target_times.insert(7, 500);
        assert_eq!(st.latch_on_commit(7, 100), Some(500));
        assert!(st.is_held(7, 100));
        assert!(st.release_ready(500).contains(&7));
        assert!(!st.is_held(7, 500));
    }
}

