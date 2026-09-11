//! Security Context protocol implementation.
//!
//! Allows sandboxed clients to establish connections with identity metadata.
//! The compositor stores sandbox_engine, app_id, instance_id for each
//! security context, which can be used for access control decisions.

use std::collections::HashMap;
use wayland_protocols::wp::security_context::v1::server::{
    wp_security_context_manager_v1::{self, WpSecurityContextManagerV1},
    wp_security_context_v1::{self, WpSecurityContextV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// Per-security-context metadata
#[derive(Debug, Clone, Default)]
pub struct SecurityContextData {
    pub sandbox_engine: String,
    pub app_id: String,
    pub instance_id: String,
    pub committed: bool,
}

/// Compositor-wide security context state
#[derive(Debug, Default)]
pub struct SecurityContextState {
    /// Active security contexts (context_id → data)
    pub contexts: HashMap<u32, SecurityContextData>,
}

impl GlobalDispatch<WpSecurityContextManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpSecurityContextManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_security_context_manager_v1");
    }
}

impl Dispatch<WpSecurityContextManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpSecurityContextManagerV1,
        request: wp_security_context_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_security_context_manager_v1::Request::CreateListener {
                id,
                listen_fd: _,
                close_fd: _,
            } => {
                let ctx = data_init.init(id, ());
                let ctx_id = ctx.id().protocol_id();
                state
                    .ext
                    .security_context
                    .contexts
                    .insert(ctx_id, SecurityContextData::default());
                tracing::debug!("Created security context {}", ctx_id);
            }
            wp_security_context_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpSecurityContextV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpSecurityContextV1,
        request: wp_security_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ctx_id = resource.id().protocol_id();
        match request {
            wp_security_context_v1::Request::SetSandboxEngine { name } => {
                if let Some(ctx) = state.ext.security_context.contexts.get_mut(&ctx_id) {
                    ctx.sandbox_engine = name;
                    tracing::debug!(
                        "Security context {} sandbox engine: {}",
                        ctx_id,
                        ctx.sandbox_engine
                    );
                }
            }
            wp_security_context_v1::Request::SetAppId { app_id } => {
                if let Some(ctx) = state.ext.security_context.contexts.get_mut(&ctx_id) {
                    ctx.app_id = app_id;
                    tracing::debug!("Security context {} app_id: {}", ctx_id, ctx.app_id);
                }
            }
            wp_security_context_v1::Request::SetInstanceId { instance_id } => {
                if let Some(ctx) = state.ext.security_context.contexts.get_mut(&ctx_id) {
                    ctx.instance_id = instance_id;
                    tracing::debug!(
                        "Security context {} instance_id: {}",
                        ctx_id,
                        ctx.instance_id
                    );
                }
            }
            wp_security_context_v1::Request::Commit => {
                if let Some(ctx) = state.ext.security_context.contexts.get_mut(&ctx_id) {
                    ctx.committed = true;
                    tracing::info!(
                        "Security context {} committed: engine={}, app={}, instance={}",
                        ctx_id,
                        ctx.sandbox_engine,
                        ctx.app_id,
                        ctx.instance_id
                    );
                }
            }
            wp_security_context_v1::Request::Destroy => {
                state.ext.security_context.contexts.remove(&ctx_id);
                tracing::debug!("Security context {} destroyed", ctx_id);
            }
            _ => {}
        }
    }
}

pub fn register_security_context(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpSecurityContextManagerV1, ()>(1, ())
}
