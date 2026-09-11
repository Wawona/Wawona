//! Product-domain errors (UniFFI). Not compositor `WWNCore*` errors.

use thiserror::Error;

#[derive(Debug, Error, Clone, uniffi::Error)]
pub enum DomainError {
    #[error("invalid profile JSON: {message}")]
    InvalidJson { message: String },

    #[error("validation failed: {message}")]
    Validation { message: String },

    #[error("refused: {message}")]
    Refused { message: String },
}

impl DomainError {
    pub fn invalid_json(msg: impl Into<String>) -> Self {
        Self::InvalidJson {
            message: msg.into(),
        }
    }

    pub fn validation(msg: impl Into<String>) -> Self {
        Self::Validation {
            message: msg.into(),
        }
    }

    pub fn refused(msg: impl Into<String>) -> Self {
        Self::Refused {
            message: msg.into(),
        }
    }
}
