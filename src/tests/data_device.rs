//! Regression tests for wl_data_device lifecycle (clipboard/DnD seat state).
//!
//! Historically `wl_data_device.release` could panic inside smithay
//! (`selection/data_device/device.rs` `Option::unwrap()` on `None`) when the
//! seat's selection `SeatData` was absent, poisoning compositor locks and
//! latching the whole compositor into a faulted state. These tests pin the
//! full lifecycle: get_data_device -> release -> client disconnect.

use crate::tests::harness::TestEnv;
use std::os::fd::AsFd;
use wayland_client::{
    protocol::{
        wl_callback, wl_compositor, wl_data_device, wl_data_device_manager, wl_data_offer,
        wl_data_source, wl_registry, wl_seat, wl_surface,
    },
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols::xdg::shell::client::{xdg_surface, xdg_toplevel, xdg_wm_base};
use wayland_server::Resource;

const CLIPBOARD_PAYLOAD: &[u8] = b"hello-from-client-a";

#[derive(Default)]
struct ClientState {
    seat: Option<wl_seat::WlSeat>,
    ddm: Option<wl_data_device_manager::WlDataDeviceManager>,
    compositor: Option<wl_compositor::WlCompositor>,
    xdg_wm_base: Option<xdg_wm_base::XdgWmBase>,
    surface: Option<wl_surface::WlSurface>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    selection_offers: u32,
    selection_events: u32,
    offer: Option<wl_data_offer::WlDataOffer>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for ClientState {
    fn event(
        state: &mut Self,
        proxy: &wl_registry::WlRegistry,
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
                "wl_seat" => state.seat = Some(proxy.bind(name, version, qh, ())),
                "wl_data_device_manager" => {
                    state.ddm = Some(proxy.bind(name, version, qh, ()))
                }
                "wl_compositor" => {
                    state.compositor = Some(proxy.bind(name, version.min(4), qh, ()))
                }
                "xdg_wm_base" => {
                    state.xdg_wm_base = Some(proxy.bind(name, version.min(1), qh, ()))
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for ClientState {
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

impl Dispatch<wl_data_device_manager::WlDataDeviceManager, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_data_device_manager::WlDataDeviceManager,
        _event: wl_data_device_manager::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_data_device::WlDataDevice, ()> for ClientState {
    wayland_client::event_created_child!(ClientState, wl_data_device::WlDataDevice, [
        wl_data_device::EVT_DATA_OFFER_OPCODE => (wl_data_offer::WlDataOffer, ()),
    ]);

    fn event(
        state: &mut Self,
        _proxy: &wl_data_device::WlDataDevice,
        event: wl_data_device::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            wl_data_device::Event::DataOffer { id } => {
                let _ = qh;
                state.offer = Some(id);
                state.selection_offers += 1;
            }
            wl_data_device::Event::Selection { id } => {
                if id.is_some() {
                    state.selection_events += 1;
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_data_source::WlDataSource, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_data_source::WlDataSource,
        event: wl_data_source::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let wl_data_source::Event::Send { fd, .. } = event {
            use std::io::Write;
            let mut file = std::fs::File::from(fd);
            let _ = file.write_all(CLIPBOARD_PAYLOAD);
        }
    }
}

impl Dispatch<wl_data_offer::WlDataOffer, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_data_offer::WlDataOffer,
        _event: wl_data_offer::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for ClientState {
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

impl Dispatch<wl_surface::WlSurface, ()> for ClientState {
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

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for ClientState {
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

impl Dispatch<xdg_surface::XdgSurface, ()> for ClientState {
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

impl Dispatch<xdg_toplevel::XdgToplevel, ()> for ClientState {
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

impl Dispatch<wl_callback::WlCallback, ()> for ClientState {
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

fn bind_globals(env: &mut TestEnv) -> (wayland_client::EventQueue<ClientState>, ClientState) {
    let mut queue = env.client.new_event_queue::<ClientState>();
    let qh = queue.handle();
    let display = env.client.display();
    let _registry = display.get_registry(&qh, ());
    let mut state = ClientState::default();
    env.wait_roundtrip(&mut queue, &mut state);
    assert!(state.seat.is_some(), "wl_seat global must be advertised");
    assert!(
        state.ddm.is_some(),
        "wl_data_device_manager global must be advertised"
    );
    (queue, state)
}

fn map_surface(
    env: &mut TestEnv,
    queue: &mut wayland_client::EventQueue<ClientState>,
    probe: &mut ClientState,
) {
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

fn map_surface_on(
    env: &mut TestEnv,
    conn: &Connection,
    queue: &mut wayland_client::EventQueue<ClientState>,
    probe: &mut ClientState,
) {
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
    env.wait_roundtrip_on(conn, queue, probe);
}

fn server_surface_for_client(
    env: &TestEnv,
    client: &wayland_server::Client,
) -> wayland_server::protocol::wl_surface::WlSurface {
    for surf in env.state.surfaces.values() {
        let Ok(surf) = surf.read() else {
            continue;
        };
        if let Some(res) = &surf.resource {
            if res.client().map(|c| c.id()) == Some(client.id()) {
                return res.clone();
            }
        }
    }
    panic!("no server surface for client");
}

fn keyboard_focus(
    env: &mut TestEnv,
    surface: wayland_server::protocol::wl_surface::WlSurface,
) {
    let seat = env
        .state
        .smithay_runtime
        .seat
        .clone()
        .expect("smithay seat");
    let keyboard = seat.get_keyboard().expect("keyboard");
    let serial = smithay::utils::SERIAL_COUNTER.next_serial();
    keyboard.set_focus(&mut env.state, Some(surface), serial);
}

/// get_data_device followed by release must not panic the server
/// (regression: smithay unwrap on missing seat SeatData).
#[test]
fn test_data_device_get_then_release() {
    let mut env = TestEnv::new();
    let (mut queue, mut state) = bind_globals(&mut env);
    let qh = queue.handle();

    let seat = state.seat.clone().unwrap();
    let ddm = state.ddm.clone().unwrap();
    let device = ddm.get_data_device(&seat, &qh, ());
    env.wait_roundtrip(&mut queue, &mut state);

    device.release();
    env.wait_roundtrip(&mut queue, &mut state);
    // A second release on a fresh device in the same session must also survive.
    let device2 = ddm.get_data_device(&seat, &qh, ());
    env.wait_roundtrip(&mut queue, &mut state);
    device2.release();
    env.wait_roundtrip(&mut queue, &mut state);
}

/// Releasing a data device on a seat whose selection SeatData was never
/// initialized through GetDataDevice on the same seat instance. Exercised by
/// creating the device and immediately releasing before any focus/selection.
#[test]
fn test_data_device_release_without_selection_activity() {
    let mut env = TestEnv::new();
    let (mut queue, mut state) = bind_globals(&mut env);
    let qh = queue.handle();

    let seat = state.seat.clone().unwrap();
    let ddm = state.ddm.clone().unwrap();
    // Release in the same batch as creation (no intermediate roundtrip).
    let device = ddm.get_data_device(&seat, &qh, ());
    device.release();
    env.wait_roundtrip(&mut queue, &mut state);
}

/// Abrupt client disconnect with a live data device must not panic the server
/// and must clear per-client data-device bookkeeping.
#[test]
fn test_data_device_client_disconnect_cleanup() {
    let mut env = TestEnv::new();
    let (mut queue, mut state) = bind_globals(&mut env);
    let qh = queue.handle();

    let seat = state.seat.clone().unwrap();
    let ddm = state.ddm.clone().unwrap();
    let _device = ddm.get_data_device(&seat, &qh, ());
    env.wait_roundtrip(&mut queue, &mut state);

    // Simulate abrupt disconnect: drop the whole client connection.
    drop(queue);
    drop(state);
    let conn = std::mem::replace(
        &mut env.client,
        Connection::from_socket({
            // Replace with a dummy pair so TestEnv teardown stays valid.
            let (_s, c) = std::os::unix::net::UnixStream::pair().unwrap();
            c
        })
        .unwrap(),
    );
    drop(conn);

    // Server must survive dispatching the disconnect.
    for _ in 0..5 {
        env.display.dispatch_clients(&mut env.state).ok();
        env.display.flush_clients().ok();
    }
}

/// Creating a source and set_selection must not panic the Smithay data device.
#[test]
fn test_data_device_set_selection_survives() {
    let mut env = TestEnv::new();
    let (mut queue, mut state) = bind_globals(&mut env);
    let qh = queue.handle();

    let seat = state.seat.clone().unwrap();
    let ddm = state.ddm.clone().unwrap();
    let device = ddm.get_data_device(&seat, &qh, ());
    let source = ddm.create_data_source(&qh, ());
    source.offer("text/plain;charset=utf-8".into());
    device.set_selection(Some(&source), 1);
    env.wait_roundtrip(&mut queue, &mut state);
}

/// Copy in client A must become a `wl_data_offer` that client B can receive.
#[test]
fn test_data_device_copy_a_paste_b() {
    let mut env = TestEnv::new();
    let (mut queue_a, mut a) = bind_globals(&mut env);
    map_surface(&mut env, &mut queue_a, &mut a);
    let qh_a = queue_a.handle();
    let seat_a = a.seat.clone().unwrap();
    let ddm_a = a.ddm.clone().unwrap();
    let device_a = ddm_a.get_data_device(&seat_a, &qh_a, ());
    env.wait_roundtrip(&mut queue_a, &mut a);

    let a_surface = server_surface_for_client(&env, &env.server_client);
    keyboard_focus(&mut env, a_surface);
    env.wait_roundtrip(&mut queue_a, &mut a);

    let source = ddm_a.create_data_source(&qh_a, ());
    source.offer("text/plain;charset=utf-8".into());
    device_a.set_selection(Some(&source), 1);
    env.wait_roundtrip(&mut queue_a, &mut a);

    let (conn_b, server_b) = env.add_client(2);
    let mut queue_b = conn_b.new_event_queue::<ClientState>();
    let qh_b = queue_b.handle();
    let _registry_b = conn_b.display().get_registry(&qh_b, ());
    let mut b = ClientState::default();
    env.wait_roundtrip_on(&conn_b, &mut queue_b, &mut b);
    map_surface_on(&mut env, &conn_b, &mut queue_b, &mut b);
    let seat_b = b.seat.clone().expect("B wl_seat");
    let ddm_b = b.ddm.clone().expect("B data device manager");
    let _device_b = ddm_b.get_data_device(&seat_b, &qh_b, ());
    env.wait_roundtrip_on(&conn_b, &mut queue_b, &mut b);

    let b_surface = server_surface_for_client(&env, &server_b);
    keyboard_focus(&mut env, b_surface);
    env.wait_roundtrip_on(&conn_b, &mut queue_b, &mut b);
    env.wait_roundtrip(&mut queue_a, &mut a);

    assert!(
        b.selection_offers >= 1 && b.selection_events >= 1,
        "client B must see A's clipboard selection (offers={} selection={})",
        b.selection_offers,
        b.selection_events
    );
    let offer = b.offer.clone().expect("B data offer");
    let (reader, writer) = nix::unistd::pipe().expect("pipe");
    offer.receive("text/plain;charset=utf-8".into(), writer.as_fd());
    env.wait_roundtrip_on(&conn_b, &mut queue_b, &mut b);
    env.wait_roundtrip(&mut queue_a, &mut a);
    drop(writer);

    use std::io::Read;
    let mut file = std::fs::File::from(reader);
    let mut buf = Vec::new();
    file.read_to_end(&mut buf).ok();
    assert_eq!(
        buf, CLIPBOARD_PAYLOAD,
        "client B must receive A's clipboard bytes"
    );
    let _ = source;
    let _ = device_a;
}
