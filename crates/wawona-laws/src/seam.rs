//! String seam shared by Exact `machinePhase` / `navPlace` and UniFFI.

use super::{
    nav_back, nav_open_machine, nav_open_section, nav_select_machines, nav_select_settings,
    start_machine, stop_machine, MachinePhase, NavPlace,
};

/// `start` or `stop` on `idle`, `running`, or `stopped`.
pub fn apply_phase(op: &str, phase: &str) -> Option<&'static str> {
    let phase = parse_phase(phase)?;
    let next = match op {
        "start" => start_machine(phase),
        "stop" => stop_machine(phase),
        _ => return None,
    };
    Some(phase_name(next))
}

/// Route-root step. Exact's own navigator still owns the live stack.
pub fn apply_nav(op: &str, place: &str) -> Option<&'static str> {
    let place = parse_place(place)?;
    let next = match op {
        "back" => nav_back(place),
        "open-machine" => nav_open_machine(place),
        "open-section" => nav_open_section(place),
        "select-machines" => nav_select_machines(place),
        "select-settings" => nav_select_settings(place),
        _ => return None,
    };
    Some(place_name(next))
}

fn parse_phase(name: &str) -> Option<MachinePhase> {
    match name {
        "idle" => Some(MachinePhase::Idle),
        "running" => Some(MachinePhase::Running),
        "stopped" => Some(MachinePhase::Stopped),
        _ => None,
    }
}

fn phase_name(phase: MachinePhase) -> &'static str {
    match phase {
        MachinePhase::Idle => "idle",
        MachinePhase::Running => "running",
        MachinePhase::Stopped => "stopped",
    }
}

fn parse_place(name: &str) -> Option<NavPlace> {
    match name {
        "machines" => Some(NavPlace::Machines),
        "machine" => Some(NavPlace::Machine),
        "session" => Some(NavPlace::Session),
        "add" => Some(NavPlace::Add),
        "create-tag" => Some(NavPlace::CreateTag),
        "tabs" => Some(NavPlace::Tabs),
        "settings" => Some(NavPlace::Settings),
        "section" => Some(NavPlace::Section),
        _ => None,
    }
}

fn place_name(place: NavPlace) -> &'static str {
    match place {
        NavPlace::Machines => "machines",
        NavPlace::Machine => "machine",
        NavPlace::Session => "session",
        NavPlace::Add => "add",
        NavPlace::CreateTag => "create-tag",
        NavPlace::Tabs => "tabs",
        NavPlace::Settings => "settings",
        NavPlace::Section => "section",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phase_names_round_trip() {
        for phase in ["idle", "running", "stopped"] {
            assert_eq!(apply_phase("start", phase), Some("running"));
            let stopped = apply_phase("stop", phase).unwrap();
            assert_eq!(apply_phase("stop", stopped), Some(stopped));
        }
        assert_eq!(apply_phase("stop", "idle"), Some("idle"));
        assert_eq!(apply_phase("stop", "running"), Some("stopped"));
        assert_eq!(apply_phase("nope", "idle"), None);
        assert_eq!(apply_phase("start", "nope"), None);
    }

    #[test]
    fn nav_names_round_trip() {
        assert_eq!(apply_nav("back", "machine"), Some("machines"));
        assert_eq!(apply_nav("back", "session"), Some("machines"));
        assert_eq!(apply_nav("back", "settings"), Some("machines"));
        assert_eq!(apply_nav("back", "section"), Some("settings"));
        assert_eq!(apply_nav("open-machine", "settings"), Some("machine"));
        assert_eq!(apply_nav("open-section", "machines"), Some("section"));
        assert_eq!(apply_nav("select-machines", "section"), Some("machines"));
        assert_eq!(apply_nav("select-settings", "machine"), Some("settings"));
        assert_eq!(apply_nav("back", "nope"), None);
    }
}
