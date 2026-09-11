//! Smithay `TouchHandle` delivery and Multi-Touch seat policy.

use crate::core::wayland::policy::ProtocolProfile;
use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{
        wl_callback, wl_compositor, wl_pointer, wl_registry, wl_seat, wl_surface, wl_touch,
    },
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols::xdg::shell::client::{xdg_surface, xdg_toplevel, xdg_wm_base};

#[derive(Default)]
struct Probe {
    seat: Option<wl_seat::WlSeat>,
    compositor: Option<wl_compositor::WlCompositor>,
    xdg_wm_base: Option<xdg_wm_base::XdgWmBase>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    surface: Option<wl_surface::WlSurface>,
    touch: Option<wl_touch::WlTouch>,
    pointer: Option<wl_pointer::WlPointer>,
    has_touch_cap: bool,
    primary_selection: bool,
    downs: Vec<i32>,
    motions: Vec<i32>,
    ups: Vec<i32>,
    frames: u32,
    cancels: u32,
    pointer_axis: u32,
    pointer_buttons: u32,
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
                "wl_seat" => {
                    state.seat = Some(registry.bind(name, version.min(7), qh, ()));
                }
                "wl_compositor" => {
                    state.compositor = Some(registry.bind(name, version.min(4), qh, ()));
                }
                "xdg_wm_base" => {
                    state.xdg_wm_base = Some(registry.bind(name, version.min(1), qh, ()));
                }
                "zwp_primary_selection_device_manager_v1" => {
                    state.primary_selection = true;
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for Probe {
    fn event(
        state: &mut Self,
        seat: &wl_seat::WlSeat,
        event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities { capabilities } = event {
            if let Ok(capabilities) = capabilities.into_result() {
                if capabilities.contains(wl_seat::Capability::Touch) {
                    state.has_touch_cap = true;
                    if state.touch.is_none() {
                        state.touch = Some(seat.get_touch(qh, ()));
                    }
                }
                if capabilities.contains(wl_seat::Capability::Pointer) && state.pointer.is_none()
                {
                    state.pointer = Some(seat.get_pointer(qh, ()));
                }
            }
        }
    }
}

impl Dispatch<wl_touch::WlTouch, ()> for Probe {
    fn event(
        state: &mut Self,
        _proxy: &wl_touch::WlTouch,
        event: wl_touch::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_touch::Event::Down { id, .. } => state.downs.push(id),
            wl_touch::Event::Motion { id, .. } => state.motions.push(id),
            wl_touch::Event::Up { id, .. } => state.ups.push(id),
            wl_touch::Event::Frame => state.frames += 1,
            wl_touch::Event::Cancel => state.cancels += 1,
            _ => {}
        }
    }
}

impl Dispatch<wl_pointer::WlPointer, ()> for Probe {
    fn event(
        state: &mut Self,
        _proxy: &wl_pointer::WlPointer,
        event: wl_pointer::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_pointer::Event::Axis { .. } | wl_pointer::Event::AxisDiscrete { .. } => {
                state.pointer_axis += 1;
            }
            wl_pointer::Event::Button { .. } => {
                state.pointer_buttons += 1;
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

fn map_surface(env: &mut TestEnv, queue: &mut wayland_client::EventQueue<Probe>, probe: &mut Probe) {
    let qh = queue.handle();
    let compositor = probe.compositor.clone().expect("wl_compositor");
    let xdg = probe.xdg_wm_base.clone().expect("xdg_wm_base");
    let surface = compositor.create_surface(&qh, ());
    let xdg_surface = xdg.get_xdg_surface(&surface, &qh, ());
    let toplevel = xdg_surface.get_toplevel(&qh, ());
    surface.commit();
    probe.surface = Some(surface);
    probe.xdg_surface = Some(xdg_surface);
    probe.xdg_toplevel = Some(toplevel);
    env.wait_roundtrip(queue, probe);
}

fn first_surface_id(env: &TestEnv) -> u32 {
    *env.state
        .surfaces
        .keys()
        .next()
        .expect("mapped surface")
}

#[test]
fn seat_advertises_touch() {
    let mut env = TestEnv::new();
    let (_queue, probe) = bind_probe(&mut env);
    assert!(probe.has_touch_cap, "wl_seat must advertise Touch");
    assert!(probe.touch.is_some(), "client must bind wl_touch");
}

#[test]
fn smithay_touch_down_motion_up_frame() {
    let mut env = TestEnv::new();
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_surface(&mut env, &mut queue, &mut probe);
    let sid = first_surface_id(&env);

    env.state
        .inject_touch_down_on_surface(7, sid, 12.0, 18.0, 10);
    env.state
        .inject_touch_motion_local(7, 20.0, 30.0, 20);
    env.state.inject_touch_up(7, 30);
    env.state.inject_touch_frame();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert_eq!(probe.downs, vec![7]);
    assert_eq!(probe.motions, vec![7]);
    assert_eq!(probe.ups, vec![7]);
    assert!(probe.frames >= 1);
    assert_eq!(probe.pointer_axis, 0, "one-finger inject must not emit axis");
    assert_eq!(
        probe.pointer_buttons, 0,
        "apps must not get BTN_LEFT from Multi-Touch"
    );
}

#[test]
fn pointer_emulation_pref_mirrors_button() {
    let mut env = TestEnv::new();
    env.state.set_touch_pointer_emulation(true);
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_surface(&mut env, &mut queue, &mut probe);
    let sid = first_surface_id(&env);

    env.state
        .inject_touch_down_on_surface(3, sid, 8.0, 8.0, 10);
    env.state.inject_touch_up(3, 20);
    env.state.inject_touch_frame();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert_eq!(probe.downs, vec![3]);
    assert!(
        probe.pointer_buttons >= 1,
        "pref-gated emulation must send pointer button"
    );
    assert_eq!(probe.pointer_axis, 0);
}

#[test]
fn single_touch_cap_drops_second_id() {
    let mut env = TestEnv::new();
    env.state.seat.touch.max_concurrent = 1;
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_surface(&mut env, &mut queue, &mut probe);
    let sid = first_surface_id(&env);

    env.state
        .inject_touch_down_on_surface(1, sid, 1.0, 1.0, 10);
    env.state
        .inject_touch_down_on_surface(2, sid, 2.0, 2.0, 11);
    env.state.inject_touch_frame();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert_eq!(probe.downs, vec![1]);
    assert!(!probe.downs.contains(&2));
}

#[test]
fn touch_cancel_clears() {
    let mut env = TestEnv::new();
    let (mut queue, mut probe) = bind_probe(&mut env);
    map_surface(&mut env, &mut queue, &mut probe);
    let sid = first_surface_id(&env);

    env.state
        .inject_touch_down_on_surface(4, sid, 1.0, 1.0, 10);
    env.state.inject_touch_cancel();
    env.wait_roundtrip(&mut queue, &mut probe);

    assert!(probe.cancels >= 1 || !env.state.seat.touch.has_active_touches());
    assert!(!env.state.seat.touch.has_active_touches());
}

#[test]
fn store_safe_hides_primary_selection() {
    let mut state = crate::core::state::CompositorState::new(None);
    state.protocol_profile = ProtocolProfile::StoreSafe;
    let mut display = wayland_server::Display::<crate::core::state::CompositorState>::new().unwrap();
    let mut handle = display.handle();
    crate::core::wayland::smithay_runtime::register_core_shell(&mut state, &handle);
    crate::core::wayland::ext::register(&mut state, &handle);
    crate::core::wayland::host_im::attach(&mut display, &mut state);

    let (server_sock, client_sock) = std::os::unix::net::UnixStream::pair().unwrap();
    let client_data = crate::core::state::ClientState { id: Some(4) };
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
        !probe.primary_selection,
        "store-safe must not advertise primary selection"
    );
}

#[test]
fn desktop_advertises_primary_selection() {
    let mut state = crate::core::state::CompositorState::new(None);
    state.protocol_profile = ProtocolProfile::DesktopHost;
    let mut display = wayland_server::Display::<crate::core::state::CompositorState>::new().unwrap();
    let mut handle = display.handle();
    crate::core::wayland::smithay_runtime::register_core_shell(&mut state, &handle);
    crate::core::wayland::ext::register(&mut state, &handle);
    crate::core::wayland::host_im::attach(&mut display, &mut state);

    let (server_sock, client_sock) = std::os::unix::net::UnixStream::pair().unwrap();
    let client_data = crate::core::state::ClientState { id: Some(3) };
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
        probe.primary_selection,
        "desktop-host must advertise primary selection"
    );
}
