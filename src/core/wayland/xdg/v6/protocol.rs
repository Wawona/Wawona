//! Generated protocol bindings for zxdg_shell_v6.

#[allow(unused_imports)]
use wayland_server;
#[allow(unused_imports)]
use wayland_server::protocol::*;

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
pub mod __interfaces {
    use wayland_server::protocol::__interfaces::*;
    wayland_scanner::generate_interfaces!("protocols/xdg-shell-unstable-v6.xml");
}

#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]
use self::__interfaces::*;

wayland_scanner::generate_server_code!("protocols/xdg-shell-unstable-v6.xml");
