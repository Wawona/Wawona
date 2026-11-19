//! Machine phase is the session law the compositor owns.
//!
//! Exact Contract reaches this function later through the data seam. The Bend
//! model in `verification/bend/` states the same transitions. That model is
//! checked by `cargo xtask prove bend`. Its C backend is not a product target.

/// Where a machine sits between Start and Stop.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MachinePhase {
    /// No session.
    Idle,
    /// Compositor session is up.
    Running,
    /// Stop finished. A second Stop stays here.
    Stopped,
}

/// Stop is safe to retry. Idle stays idle. Running becomes stopped.
/// Stopped stays stopped.
pub fn stop_machine(phase: MachinePhase) -> MachinePhase {
    match phase {
        MachinePhase::Idle => MachinePhase::Idle,
        MachinePhase::Running => MachinePhase::Stopped,
        MachinePhase::Stopped => MachinePhase::Stopped,
    }
}

/// Start brings every phase to Running. A second Start stays there.
pub fn start_machine(phase: MachinePhase) -> MachinePhase {
    match phase {
        MachinePhase::Idle | MachinePhase::Running | MachinePhase::Stopped => MachinePhase::Running,
    }
}

#[cfg(test)]
mod tests {
    use super::{start_machine, stop_machine, MachinePhase};

    #[test]
    fn stop_is_idempotent() {
        for phase in [MachinePhase::Idle, MachinePhase::Running, MachinePhase::Stopped] {
            assert_eq!(stop_machine(stop_machine(phase)), stop_machine(phase));
        }
    }

    #[test]
    fn stop_leaves_idle() {
        assert_eq!(stop_machine(MachinePhase::Idle), MachinePhase::Idle);
    }

    #[test]
    fn stop_ends_running() {
        assert_eq!(stop_machine(MachinePhase::Running), MachinePhase::Stopped);
    }

    #[test]
    fn stop_keeps_stopped() {
        assert_eq!(stop_machine(MachinePhase::Stopped), MachinePhase::Stopped);
    }

    #[test]
    fn start_is_running_and_idempotent() {
        for phase in [MachinePhase::Idle, MachinePhase::Running, MachinePhase::Stopped] {
            assert_eq!(start_machine(phase), MachinePhase::Running);
            assert_eq!(start_machine(start_machine(phase)), start_machine(phase));
        }
    }

    #[test]
    fn start_then_stop_is_stopped() {
        for phase in [MachinePhase::Idle, MachinePhase::Running, MachinePhase::Stopped] {
            assert_eq!(stop_machine(start_machine(phase)), MachinePhase::Stopped);
            assert_eq!(start_machine(stop_machine(phase)), MachinePhase::Running);
        }
    }
}
