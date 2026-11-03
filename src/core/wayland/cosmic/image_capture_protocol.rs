//! Generated bindings for cosmic-image-capture-source-unstable-v1.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use wayland_protocols::ext::image_capture_source::v1::server::*;
#[allow(unused_imports)]
use wayland_protocols::ext::workspace::v1::server::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use wayland_protocols::ext::image_capture_source::v1::server::__interfaces::*;
    use wayland_protocols::ext::workspace::v1::server::__interfaces::*;
    wayland_scanner::generate_interfaces!(
        "protocols/cosmic/cosmic-image-capture-source-unstable-v1.xml"
    );
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!(
    "protocols/cosmic/cosmic-image-capture-source-unstable-v1.xml"
);
