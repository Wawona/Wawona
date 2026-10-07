#[cfg(loom)]
use loom::sync::atomic::{AtomicU64, Ordering};
#[cfg(not(loom))]
use std::sync::atomic::{AtomicU64, Ordering};

/// Monotonic counter. The first bump returns 0.
pub struct GenerationCounter {
    value: AtomicU64,
}

impl GenerationCounter {
    pub fn new() -> Self {
        Self {
            value: AtomicU64::new(0),
        }
    }

    pub fn bump(&self) -> u64 {
        self.value.fetch_add(1, Ordering::AcqRel)
    }

    pub fn load(&self) -> u64 {
        self.value.load(Ordering::Acquire)
    }
}

impl Default for GenerationCounter {
    fn default() -> Self {
        Self::new()
    }
}
