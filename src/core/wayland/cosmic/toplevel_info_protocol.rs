//! Generated bindings for cosmic-toplevel-info-unstable-v1.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use wayland_protocols::ext::foreign_toplevel_list::v1::server::*;
#[allow(unused_imports)]
use wayland_protocols::ext::workspace::v1::server::*;
#[allow(unused_imports)]
use crate::core::wayland::cosmic::workspace_v1_protocol::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use wayland_protocols::ext::foreign_toplevel_list::v1::server::__interfaces::*;
    use wayland_protocols::ext::workspace::v1::server::__interfaces::*;
    use crate::core::wayland::cosmic::workspace_v1_protocol::__interfaces::*;
    wayland_scanner::generate_interfaces!(
        "protocols/cosmic/cosmic-toplevel-info-unstable-v1.xml"
    );
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!("protocols/cosmic/cosmic-toplevel-info-unstable-v1.xml");
