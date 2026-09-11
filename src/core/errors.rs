//! Core error types

use thiserror::Error;

/// Core compositor errors
#[derive(Error, Debug, Clone)]
pub enum CoreError {
    #[error("Wayland protocol error: {0}")]
    WaylandError(String),

    #[error("State error: {0}")]
    StateError(String),

    #[error("Platform error: {0}")]
    PlatformError(String),

    #[error("Invalid surface ID: {0}")]
    InvalidSurfaceId(u32),

    #[error("Invalid window ID: {0}")]
    InvalidWindowId(u64),

    #[error("Resource not found: {0}")]
    ResourceNotFound(String),
}

impl CoreError {
    pub fn wayland_error(msg: impl Into<String>) -> Self {
        Self::WaylandError(msg.into())
    }

    pub fn state_error(msg: impl Into<String>) -> Self {
        Self::StateError(msg.into())
    }

    pub fn platform_error(msg: impl Into<String>) -> Self {
        Self::PlatformError(msg.into())
    }
}

/// Result type for core operations
pub type Result<T> = std::result::Result<T, CoreError>;

// Legacy type alias for compatibility
#[deprecated(note = "Use CoreError instead")]
pub type WawonaError = CoreError;
