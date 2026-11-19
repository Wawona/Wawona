//! Pure Exact UI transitions. One contract, every `ALL_TARGETS` host.
//!
//! Bend models these functions. The contract actions named in `coverage` are
//! the calls. Host effects (open a URL, sync now) stay outside the laws.

pub fn store_bool(on: bool) -> bool {
    on
}

pub fn flip_bool(on: bool) -> bool {
    !on
}

/// Remote stays on only while the draft session is waypipe.
pub fn remote_on(waypipe: bool, on: bool) -> bool {
    waypipe && on
}

/// A blank trimmed name does not save.
pub fn save_when(named: bool) -> bool {
    named
}

/// A hidden section does not open.
pub fn open_when(shown: bool) -> bool {
    shown
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_and_flip_cover_settings_writes() {
        assert!(store_bool(true));
        assert!(!store_bool(false));
        assert!(flip_bool(flip_bool(true)));
        assert!(!flip_bool(true));
    }

    #[test]
    fn guards_match_the_contract() {
        assert!(!remote_on(false, true));
        assert!(remote_on(true, true));
        assert!(!remote_on(true, false));
        assert!(!save_when(false));
        assert!(save_when(true));
        assert!(!open_when(false));
        assert!(open_when(true));
    }
}