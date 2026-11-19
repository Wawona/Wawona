//! Session phase and Machines / Settings route roots.
//!
//! Bend in `verification/bend/` checks the model of these functions.
//! Exact's data source, UniFFI, and the compositor call this crate.
//! Bend's C backend is not a product target.

#[cfg(test)]
mod coverage;
pub mod focus;
pub mod machine_phase;
pub mod nav_place;
pub mod ui;

mod seam;

pub use machine_phase::{start_machine, stop_machine, MachinePhase};
pub use nav_place::{
    nav_back, nav_open_machine, nav_open_section, nav_select_machines, nav_select_settings,
    NavPlace,
};
pub use focus::{
    clear_closed_focus, eligible_after_close, focus_after_close, select_window,
};
pub use seam::{apply_nav, apply_phase};
