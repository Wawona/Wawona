//! Handle to the in-process Wawona compositor (Linux GTK UI).
//!
//! Machines Start needs to stage fill-host before the client connects, the
//! same as macOS `setFillsHostForClientLaunch:`.

use std::sync::{Arc, OnceLock};

use crate::ffi::api::WawonaCore;

static CORE: OnceLock<Arc<WawonaCore>> = OnceLock::new();

pub fn set(core: Arc<WawonaCore>) {
    let _ = CORE.set(core);
}

pub fn get() -> Option<&'static Arc<WawonaCore>> {
    CORE.get()
}
