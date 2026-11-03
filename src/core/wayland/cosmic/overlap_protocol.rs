//! Generated bindings for cosmic-overlap-notify-unstable-v1.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use wayland_protocols::ext::foreign_toplevel_list::v1::server::*;
#[allow(unused_imports)]
use wayland_protocols_wlr::layer_shell::v1::server::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use wayland_protocols::ext::foreign_toplevel_list::v1::server::__interfaces::*;
    use wayland_protocols_wlr::layer_shell::v1::server::__interfaces::*;
    wayland_scanner::generate_interfaces!(
        "protocols/cosmic/cosmic-overlap-notify-unstable-v1.xml"
    );
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!("protocols/cosmic/cosmic-overlap-notify-unstable-v1.xml");
