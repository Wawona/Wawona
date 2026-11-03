//! Generated bindings for xx-session-management-v1.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use wayland_protocols::xdg::shell::server::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use wayland_protocols::xdg::shell::server::__interfaces::*;
    wayland_scanner::generate_interfaces!("protocols/ext/xx-session-management-v1.xml");
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!("protocols/ext/xx-session-management-v1.xml");
