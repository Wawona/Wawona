//! Generated bindings for cosmic-screencopy-unstable-v2.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use crate::core::wayland::cosmic::image_source_protocol::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use crate::core::wayland::cosmic::image_source_protocol::__interfaces::*;
    wayland_scanner::generate_interfaces!(
        "protocols/cosmic/cosmic-screencopy-unstable-v2.xml"
    );
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!(
    "protocols/cosmic/cosmic-screencopy-unstable-v2.xml"
);
