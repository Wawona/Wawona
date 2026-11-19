//! One-level Machines catalog route table.
//!
//! Matches the nesting in `exact/apps/wawona/app.contract` (`routes nav`):
//! one catalog tab. Children are machine, session, add, createTag, tabs,
//! settings, and section. Settings is a cover over the catalog, not a peer
//! tab root. Back from Settings returns to Machines. This is the helper the
//! data seam will call. It is not a second copy of Exact's navigator.
//!
//! The Bend model is `verification/bend/`. Its C backend is not a product target.

/// Where the contract route sits.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavPlace {
    /// Catalog root.
    Machines,
    /// `/m/:id`.
    Machine,
    /// `/session/:id`.
    Session,
    /// `/add`.
    Add,
    /// `/create-tag`.
    CreateTag,
    /// `/tabs`.
    Tabs,
    /// `/settings` cover.
    Settings,
    /// `/settings/:id`.
    Section,
}

/// Pop one level. Catalog root stays put. Settings cover returns to Machines.
pub fn nav_back(place: NavPlace) -> NavPlace {
    match place {
        NavPlace::Machines => NavPlace::Machines,
        NavPlace::Machine
        | NavPlace::Session
        | NavPlace::Add
        | NavPlace::CreateTag
        | NavPlace::Tabs
        | NavPlace::Settings => NavPlace::Machines,
        NavPlace::Section => NavPlace::Settings,
    }
}

/// Return to the catalog root.
pub fn nav_select_machines(_place: NavPlace) -> NavPlace {
    NavPlace::Machines
}

/// Open the Settings cover.
pub fn nav_select_settings(_place: NavPlace) -> NavPlace {
    NavPlace::Settings
}

/// Open a machine inspector.
pub fn nav_open_machine(_place: NavPlace) -> NavPlace {
    NavPlace::Machine
}

/// Open a settings section.
pub fn nav_open_section(_place: NavPlace) -> NavPlace {
    NavPlace::Section
}

#[cfg(test)]
mod tests {
    use super::*;

    fn all() -> [NavPlace; 8] {
        [
            NavPlace::Machines,
            NavPlace::Machine,
            NavPlace::Session,
            NavPlace::Add,
            NavPlace::CreateTag,
            NavPlace::Tabs,
            NavPlace::Settings,
            NavPlace::Section,
        ]
    }

    #[test]
    fn back_stabilizes_after_two() {
        for place in all() {
            let twice = nav_back(nav_back(place));
            assert_eq!(nav_back(twice), twice);
        }
    }

    #[test]
    fn back_returns_to_catalog_or_settings_cover() {
        assert_eq!(nav_back(NavPlace::Machines), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Machine), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Session), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Add), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::CreateTag), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Tabs), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Settings), NavPlace::Machines);
        assert_eq!(nav_back(NavPlace::Section), NavPlace::Settings);
    }

    #[test]
    fn open_then_back_is_the_catalog_or_settings() {
        for place in all() {
            assert_eq!(nav_back(nav_open_machine(place)), NavPlace::Machines);
            assert_eq!(nav_back(nav_open_section(place)), NavPlace::Settings);
            assert_eq!(nav_back(nav_select_settings(place)), NavPlace::Machines);
        }
    }

    #[test]
    fn select_machines_stays_at_root() {
        for place in all() {
            let machines = nav_select_machines(place);
            assert_eq!(machines, NavPlace::Machines);
            assert_eq!(nav_back(machines), machines);
        }
    }
}
