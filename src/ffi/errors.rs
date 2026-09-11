//! FFI error types
//!
//! This module defines the error types that are exposed via UniFFI.
//! These errors can be caught and handled by platform code (Kotlin, Swift, etc.)

use thiserror::Error;

/// Compositor errors exposed via FFI
#[derive(Debug, Error, Clone, uniffi::Error)]
pub enum CompositorError {
    #[error("Failed to initialize compositor: {message}")]
    InitializationFailed { message: String },

    #[error("Compositor already started")]
    AlreadyStarted,

    #[error("Compositor not started")]
    NotStarted,

    #[error("Invalid window ID: {id}")]
    InvalidWindowId { id: u64 },

    #[error("Invalid surface ID: {id}")]
    InvalidSurfaceId { id: u32 },

    #[error("Invalid buffer ID: {id}")]
    InvalidBufferId { id: u64 },

    #[error("Invalid output ID: {id}")]
    InvalidOutputId { id: u32 },

    #[error("Invalid client ID: {id}")]
    InvalidClientId { id: u32 },

    #[error("Socket error: {message}")]
    SocketError { message: String },

    #[error("Platform error: {message}")]
    PlatformError { message: String },

    #[error("Wayland error: {message}")]
    WaylandError { message: String },

    #[error("Protocol error: {message}")]
    ProtocolError { message: String },

    #[error("Resource not found: {resource}")]
    ResourceNotFound { resource: String },

    #[error("Buffer too small: expected {expected} bytes, got {actual}")]
    BufferTooSmall { expected: u64, actual: u64 },

    #[error("Unsupported format: {format}")]
    UnsupportedFormat { format: String },
}

impl CompositorError {
    // ===== Convenience constructors =====

    pub fn initialization_failed(msg: impl Into<String>) -> Self {
        Self::InitializationFailed {
            message: msg.into(),
        }
    }

    pub fn invalid_window_id(id: u64) -> Self {
        Self::InvalidWindowId { id }
    }

    pub fn invalid_surface_id(id: u32) -> Self {
        Self::InvalidSurfaceId { id }
    }

    pub fn invalid_buffer_id(id: u64) -> Self {
        Self::InvalidBufferId { id }
    }

    pub fn invalid_output_id(id: u32) -> Self {
        Self::InvalidOutputId { id }
    }

    pub fn invalid_client_id(id: u32) -> Self {
        Self::InvalidClientId { id }
    }

    pub fn socket_error(msg: impl Into<String>) -> Self {
        Self::SocketError {
            message: msg.into(),
        }
    }

    pub fn platform_error(msg: impl Into<String>) -> Self {
        Self::PlatformError {
            message: msg.into(),
        }
    }

    pub fn wayland_error(msg: impl Into<String>) -> Self {
        Self::WaylandError {
            message: msg.into(),
        }
    }

    pub fn protocol_error(msg: impl Into<String>) -> Self {
        Self::ProtocolError {
            message: msg.into(),
        }
    }

    pub fn resource_not_found(resource: impl Into<String>) -> Self {
        Self::ResourceNotFound {
            resource: resource.into(),
        }
    }

    pub fn buffer_too_small(expected: u64, actual: u64) -> Self {
        Self::BufferTooSmall { expected, actual }
    }

    pub fn unsupported_format(format: impl Into<String>) -> Self {
        Self::UnsupportedFormat {
            format: format.into(),
        }
    }
}

/// Result type for FFI operations
pub type Result<T> = std::result::Result<T, CompositorError>;

// ============================================================================
// Conversions from Core errors
// ============================================================================

/// Convert from core errors to FFI errors
impl From<crate::core::errors::CoreError> for CompositorError {
    fn from(err: crate::core::errors::CoreError) -> Self {
        use crate::core::errors::CoreError;

        match err {
            CoreError::WaylandError(msg) => CompositorError::wayland_error(msg),
            CoreError::StateError(msg) => CompositorError::platform_error(msg),
            CoreError::PlatformError(msg) => CompositorError::platform_error(msg),
            CoreError::InvalidSurfaceId(id) => CompositorError::invalid_surface_id(id),
            CoreError::InvalidWindowId(id) => CompositorError::invalid_window_id(id),
            CoreError::ResourceNotFound(msg) => CompositorError::resource_not_found(msg),
        }
    }
}

/// Convert from std::io::Error
impl From<std::io::Error> for CompositorError {
    fn from(err: std::io::Error) -> Self {
        CompositorError::platform_error(err.to_string())
    }
}

// ============================================================================
// Error Categories
// ============================================================================

impl CompositorError {
    /// Check if this is a fatal error that requires stopping the compositor
    pub fn is_fatal(&self) -> bool {
        matches!(
            self,
            CompositorError::InitializationFailed { .. } | CompositorError::SocketError { .. }
        )
    }

    /// Check if this is a recoverable error
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            CompositorError::InvalidWindowId { .. }
                | CompositorError::InvalidSurfaceId { .. }
                | CompositorError::InvalidBufferId { .. }
                | CompositorError::InvalidOutputId { .. }
                | CompositorError::InvalidClientId { .. }
                | CompositorError::ResourceNotFound { .. }
                | CompositorError::BufferTooSmall { .. }
                | CompositorError::UnsupportedFormat { .. }
        )
    }

    /// Check if this is a protocol error (client misbehaving)
    pub fn is_protocol_error(&self) -> bool {
        matches!(
            self,
            CompositorError::ProtocolError { .. } | CompositorError::WaylandError { .. }
        )
    }

    /// Get error code for debugging
    pub fn code(&self) -> u32 {
        match self {
            CompositorError::InitializationFailed { .. } => 1,
            CompositorError::AlreadyStarted => 2,
            CompositorError::NotStarted => 3,
            CompositorError::InvalidWindowId { .. } => 10,
            CompositorError::InvalidSurfaceId { .. } => 11,
            CompositorError::InvalidBufferId { .. } => 12,
            CompositorError::InvalidOutputId { .. } => 13,
            CompositorError::InvalidClientId { .. } => 14,
            CompositorError::SocketError { .. } => 20,
            CompositorError::PlatformError { .. } => 30,
            CompositorError::WaylandError { .. } => 40,
            CompositorError::ProtocolError { .. } => 41,
            CompositorError::ResourceNotFound { .. } => 50,
            CompositorError::BufferTooSmall { .. } => 60,
            CompositorError::UnsupportedFormat { .. } => 61,
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = CompositorError::initialization_failed("test");
        assert_eq!(err.to_string(), "Failed to initialize compositor: test");
    }

    #[test]
    fn test_error_is_fatal() {
        assert!(CompositorError::initialization_failed("test").is_fatal());
        assert!(CompositorError::socket_error("test").is_fatal());
        assert!(!CompositorError::invalid_window_id(1).is_fatal());
    }

    #[test]
    fn test_error_is_recoverable() {
        assert!(CompositorError::invalid_window_id(1).is_recoverable());
        assert!(CompositorError::resource_not_found("test").is_recoverable());
        assert!(!CompositorError::AlreadyStarted.is_recoverable());
    }
}
