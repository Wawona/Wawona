//! Regression tests for wl_data_device lifecycle (clipboard/DnD seat state).
//!
//! Historically `wl_data_device.release` could panic inside smithay
//! (`selection/data_device/device.rs` `Option::unwrap()` on `None`) when the
//! seat's selection `SeatData` was absent, poisoning compositor locks and
//! latching the whole compositor into a faulted state. These tests pin the
//! full lifecycle: get_data_device -> release -> client disconnect.

use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{wl_data_device, wl_data_device_manager, wl_registry, wl_seat, wl_callback},
    Connection, Dispatch, QueueHandle,
};

#[derive(Default)]
struct ClientState {
    seat: Option<wl_seat::WlSeat>,
    ddm: Option<wl_data_device_manager::WlDataDeviceManager>,
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
        if let wl_registry::Event::Global { name, interface, version } = event {
            if interface == "wl_seat" {
                state.seat = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "wl_data_device_manager" {
                state.ddm = Some(proxy.bind(name, version, qh, ()));
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
    fn event(
        _state: &mut Self,
        _proxy: &wl_data_device::WlDataDevice,
        _event: wl_data_device::Event,
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
    let conn = std::mem::replace(&mut env.client, Connection::from_socket({
        // Replace with a dummy pair so TestEnv teardown stays valid.
        let (_s, c) = std::os::unix::net::UnixStream::pair().unwrap();
        c
    }).unwrap());
    drop(conn);

    // Server must survive dispatching the disconnect.
    for _ in 0..5 {
        env.display.dispatch_clients(&mut env.state).ok();
        env.display.flush_clients().ok();
    }
}
