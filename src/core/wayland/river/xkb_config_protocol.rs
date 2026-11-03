//! Generated bindings for river-xkb-config-v1.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;
#[allow(unused_imports)]
use crate::core::wayland::river::input_protocol::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    use crate::core::wayland::river::input_protocol::__interfaces::*;
    wayland_scanner::generate_interfaces!("protocols/river/river-xkb-config-v1.xml");
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!("protocols/river/river-xkb-config-v1.xml");
