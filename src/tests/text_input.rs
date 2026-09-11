//! Smithay TI-v3 / host IM / OSK policy tests.

use crate::core::input::osk::{osk_should_show, OskHost};
use crate::core::wayland::ext::text_input::text_entry_wanted;
use crate::core::wayland::policy::ProtocolProfile;
use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{wl_callback, wl_compositor, wl_registry, wl_seat, wl_surface},
    Connection, Dispatch, Proxy, QueueHandle,
};
use wayland_protocols::wp::text_input::zv3::client::{
    zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
    zwp_text_input_v3::{self, ZwpTextInputV3},
};
use wayland_protocols::xdg::shell::client::{xdg_surface, xdg_toplevel, xdg_wm_base};

#[derive(Default)]
struct Probe {
    ti_manager: Option<ZwpTextInputManagerV3>,
    im_manager: bool,
    vk_manager: bool,
    seat: Option<wl_seat::WlSeat>,
    compositor: Option<wl_compositor::WlCompositor>,
    xdg_wm_base: Option<xdg_wm_base::XdgWmBase>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    surface: Option<wl_surface::WlSurface>,
    text_input: Option<ZwpTextInputV3>,
    commit_strings: Vec<String>,
    done_serials: Vec<u32>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for Probe {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            match interface.as_str() {
                "zwp_text_input_manager_v3" => {
                    state.ti_manager = Some(registry.bind(name, version.min(1), qh, ()));
                }
                "zwp_input_method_manager_v2" => {
                    state.im_manager = true;
                }
                "zwp_virtual_keyboard_manager_v1" => {
                    state.vk_manager = true;
                }
                "wl_seat" => {
                    state.seat = Some(registry.bind(name, version.min(1), qh, ()));
                }
                "wl_compositor" => {
                    state.compositor = Some(registry.bind(name, version.min(4), qh, ()));
                }
                "xdg_wm_base" => {
                    state.xdg_wm_base = Some(registry.bind(name, version.min(1), qh, ()));
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &wl_seat::WlSeat,
        _event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpTextInputManagerV3, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &ZwpTextInputManagerV3,
        _event: zwp_text_input_manager_v3::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpTextInputV3, ()> for Probe {
    fn event(
        state: &mut Self,
        _proxy: &ZwpTextInputV3,
        event: zwp_text_input_v3::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            zwp_text_input_v3::Event::CommitString { text } => {
                if let Some(text) = text {
                    state.commit_strings.push(text);
                }
            }
            zwp_text_input_v3::Event::Done { serial } => {
                state.done_serials.push(serial);
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &wl_compositor::WlCompositor,
        _event: wl_compositor::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_surface::WlSurface, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &wl_surface::WlSurface,
        _event: wl_surface::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for Probe {
    fn event(
        _state: &mut Self,
        proxy: &xdg_wm_base::XdgWmBase,
        event: xdg_wm_base::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let xdg_wm_base::Event::Ping { serial } = event {
            proxy.pong(serial);
        }
    }
}

impl Dispatch<xdg_surface::XdgSurface, ()> for Probe {
    fn event(
        _state: &mut Self,
        proxy: &xdg_surface::XdgSurface,
        event: xdg_surface::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let xdg_surface::Event::Configure { serial } = event {
            proxy.ack_configure(serial);
        }
    }
}

impl Dispatch<xdg_toplevel::XdgToplevel, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &xdg_toplevel::XdgToplevel,
        _event: xdg_toplevel::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_callback::WlCallback, ()> for Probe {
    fn event(
        _state: &mut Self,
        _proxy: &wl_callback::WlCallback,
        _event: wl_callback::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

fn bind_probe(env: &mut TestEnv) -> (wayland_client::EventQueue<Probe>, Probe) {
    let mut queue = env.client.new_event_queue::<Probe>();
    let qh = queue.handle();
    let _registry = env.client.display().get_registry(&qh, ());
    let mut probe = Probe::default();
    env.wait_roundtrip(&mut queue, &mut probe);
    (queue, probe)
}

#[test]
fn host_im_stand_in_binds() {
    let env = TestEnv::new();
    assert!(
        env.state
            .host_im
            .as_ref()
            .map(|im| im.has_instance())
            .unwrap_or(false),
        "host IM stand-in must bind IM-v2"
    );
}

#[test]
fn store_safe_does_not_advertise_im_or_virtual_keyboard() {
    let mut state = crate::core::state::CompositorState::new(None);
    state.protocol_profile = ProtocolProfile::StoreSafe;
    let mut display = wayland_server::Display::<crate::core::state::CompositorState>::new().unwrap();
    let mut handle = display.handle();
    crate::core::wayland::smithay_runtime::register_core_shell(&mut state, &handle);
    crate::core::wayland::ext::register(&mut state, &handle);
    crate::core::wayland::wlr::register(&mut state, &handle);
    crate::core::wayland::host_im::attach(&mut display, &mut state);

    let (server_sock, client_sock) = std::os::unix::net::UnixStream::pair().unwrap();
    let client_data = crate::core::state::ClientState { id: Some(2) };
    let server_client = handle
        .insert_client(server_sock, std::sync::Arc::new(client_data))
        .unwrap();
    let client = wayland_client::Connection::from_socket(client_sock).unwrap();
    let mut env = TestEnv {
        display,
        client,
        server_client,
        state,
    };
    let (_queue, probe) = bind_probe(&mut env);
    assert!(
        probe.ti_manager.is_some(),
        "TI-v3 must stay public on store-safe"
    );
    assert!(
        !probe.im_manager,
        "IM-v2 must not be advertised to store apps"
    );
    assert!(
        !probe.vk_manager,
        "virtual-keyboard must not be advertised to store apps"
    );
}

#[test]
fn enable_without_commit_does_not_want_osk() {
    let mut env = TestEnv::new();
    let (mut queue, mut probe) = bind_probe(&mut env);
    let qh = queue.handle();
    let manager = probe.ti_manager.take().expect("TI-v3 manager");
    let seat = probe.seat.take().expect("seat");
    probe.text_input = Some(manager.get_text_input(&seat, &qh, ()));
    env.wait_roundtrip(&mut queue, &mut probe);

    let ti = probe.text_input.as_ref().expect("text input");
    ti.enable();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert!(
        !text_entry_wanted(&env.state),
        "uncommitted enable must not open OSK"
    );
    assert!(!osk_should_show(
        text_entry_wanted(&env.state),
        OskHost::TouchOsk,
        false,
        false
    ));
}

#[test]
fn macos_never_requests_osk_when_wanted() {
    assert!(!osk_should_show(true, OskHost::Never, false, false));
    assert!(!osk_should_show(true, OskHost::Never, false, true));
}

fn map_and_focus_surface(
    env: &mut TestEnv,
    queue: &mut wayland_client::EventQueue<Probe>,
    probe: &mut Probe,
) {
    let qh = queue.handle();
    let compositor = probe.compositor.as_ref().expect("wl_compositor");
    let xdg = probe.xdg_wm_base.as_ref().expect("xdg_wm_base");
    let surface = compositor.create_surface(&qh, ());
    probe.xdg_surface = Some(xdg.get_xdg_surface(&surface, &qh, ()));
    probe.xdg_toplevel = Some(probe.xdg_surface.as_ref().unwrap().get_toplevel(&qh, ()));
    surface.commit();
    probe.surface = Some(surface);
    env.wait_roundtrip(queue, probe);

    let surface = probe.surface.as_ref().expect("surface");
    let surface_proto_id = Proxy::id(surface).protocol_id();
    let client_id = env
        .state
        .clients
        .keys()
        .next()
        .expect("test client")
        .clone();
    let surface_id = *env
        .state
        .protocol_to_internal_surface
        .get(&(client_id, surface_proto_id))
        .expect("surface internal ID");
    let surface_res = env
        .state
        .get_surface(surface_id)
        .unwrap()
        .read()
        .unwrap()
        .resource
        .clone()
        .expect("surface resource");
    let keyboard = env
        .state
        .smithay_runtime
        .seat
        .as_ref()
        .expect("seat")
        .get_keyboard()
        .expect("keyboard");
    let serial = env.state.next_serial();
    keyboard.set_focus(&mut env.state, Some(surface_res), serial.into());
    env.wait_roundtrip(queue, probe);
}

#[test]
fn committed_enable_wants_osk_on_touch_host() {
    let mut env = TestEnv::new();
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_and_focus_surface(&mut env, &mut queue, &mut probe);

    let qh = queue.handle();
    let manager = probe.ti_manager.take().expect("TI-v3 manager");
    let seat = probe.seat.take().expect("seat");
    probe.text_input = Some(manager.get_text_input(&seat, &qh, ()));
    env.wait_roundtrip(&mut queue, &mut probe);

    let ti = probe.text_input.as_ref().expect("text input");
    ti.enable();
    ti.commit();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert!(
        text_entry_wanted(&env.state),
        "committed enable must want text entry"
    );
    assert!(osk_should_show(
        text_entry_wanted(&env.state),
        OskHost::TouchOsk,
        false,
        false
    ));
    assert!(!osk_should_show(
        text_entry_wanted(&env.state),
        OskHost::Never,
        false,
        false
    ));
}

#[test]
fn im_serial_mismatch_discards_commit_string() {
    let mut env = TestEnv::new();
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_and_focus_surface(&mut env, &mut queue, &mut probe);

    let qh = queue.handle();
    let manager = probe.ti_manager.take().expect("TI-v3 manager");
    let seat = probe.seat.take().expect("seat");
    probe.text_input = Some(manager.get_text_input(&seat, &qh, ()));
    env.wait_roundtrip(&mut queue, &mut probe);

    let ti = probe.text_input.as_ref().expect("text input");
    ti.enable();
    ti.commit();
    env.wait_roundtrip(&mut queue, &mut probe);

    env.state
        .host_im
        .as_ref()
        .expect("host IM")
        .queue_commit_string_wrong_serial("discard-me");
    env.wait_roundtrip(&mut queue, &mut probe);

    assert_eq!(
        probe.done_serials.last().copied(),
        Some(0),
        "Smithay signals IM serial mismatch with text_input.done(0)"
    );
}

#[test]
fn trusted_filter_rejects_store_client() {
    let mut env = TestEnv::new();
    env.state.protocol_profile = ProtocolProfile::StoreSafe;
    let (server_sock, _client_sock) = std::os::unix::net::UnixStream::pair().unwrap();
    let client = env
        .display
        .handle()
        .insert_client(
            server_sock,
            std::sync::Arc::new(crate::core::state::ClientState { id: Some(9) }),
        )
        .unwrap();
    assert!(!crate::core::wayland::host_im::is_trusted_input_method(
        &client,
        ProtocolProfile::StoreSafe
    ));
    assert!(!crate::core::wayland::host_im::is_trusted_virtual_keyboard(
        &client,
        ProtocolProfile::StoreSafe
    ));
}
