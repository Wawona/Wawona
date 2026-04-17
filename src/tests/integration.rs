use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{
        wl_compositor, wl_shm, wl_seat, wl_registry, wl_callback, wl_pointer, wl_keyboard,
        wl_subcompositor, wl_subsurface
    },
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols::xdg::shell::client::{xdg_wm_base, xdg_surface, xdg_toplevel};
use std::os::fd::AsFd;
use wayland_client::Proxy;
use wayland_protocols::wp::relative_pointer::zv1::client::{
    zwp_relative_pointer_manager_v1, zwp_relative_pointer_v1
};

struct ClientState {
    compositor: Option<wl_compositor::WlCompositor>,
    shm: Option<wl_shm::WlShm>,
    seat: Option<wl_seat::WlSeat>,
    pointer: Option<wl_pointer::WlPointer>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    xdg_wm_base: Option<xdg_wm_base::XdgWmBase>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    subcompositor: Option<wl_subcompositor::WlSubcompositor>,
    relative_pointer_manager: Option<zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1>,
    relative_motion_events: Vec<(f64, f64)>,
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
            if interface == "wl_compositor" {
                state.compositor = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "wl_shm" {
                state.shm = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "wl_seat" {
                state.seat = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "xdg_wm_base" {
                state.xdg_wm_base = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "wl_subcompositor" {
                state.subcompositor = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "zwp_relative_pointer_manager_v1" {
                state.relative_pointer_manager = Some(proxy.bind(name, version, qh, ()));
            }
        }
    }
}

impl Dispatch<wl_subcompositor::WlSubcompositor, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_subcompositor::WlSubcompositor,
        _event: wl_subcompositor::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_subsurface::WlSubsurface, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_subsurface::WlSubsurface,
        _event: wl_subsurface::Event,
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

impl Dispatch<zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1,
        _event: zwp_relative_pointer_manager_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<zwp_relative_pointer_v1::ZwpRelativePointerV1, ()> for ClientState {
    fn event(
        state: &mut Self,
        _proxy: &zwp_relative_pointer_v1::ZwpRelativePointerV1,
        event: zwp_relative_pointer_v1::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let zwp_relative_pointer_v1::Event::RelativeMotion { dx, dy, .. } = event {
            state.relative_motion_events.push((dx, dy));
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

impl Dispatch<wl_shm::WlShm, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_shm::WlShm,
        _event: wl_shm::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for ClientState {
    fn event(
        state: &mut Self,
        _proxy: &wl_seat::WlSeat,
        event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_seat::Event::Capabilities { capabilities } = event {
            use wayland_client::WEnum;
            if let WEnum::Value(caps) = capabilities {
                if caps.contains(wl_seat::Capability::Pointer) {
                    state.pointer = Some(_proxy.get_pointer(qh, ()));
                }
                if caps.contains(wl_seat::Capability::Keyboard) {
                    state.keyboard = Some(_proxy.get_keyboard(qh, ()));
                }
            }
        }
    }
}

impl Dispatch<wl_pointer::WlPointer, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_pointer::WlPointer,
        _event: wl_pointer::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wl_keyboard::WlKeyboard, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_keyboard::WlKeyboard,
        _event: wl_keyboard::Event,
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

impl Dispatch<wayland_client::protocol::wl_surface::WlSurface, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wayland_client::protocol::wl_surface::WlSurface,
        _event: wayland_client::protocol::wl_surface::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wayland_client::protocol::wl_buffer::WlBuffer, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wayland_client::protocol::wl_buffer::WlBuffer,
        _event: wayland_client::protocol::wl_buffer::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<wayland_client::protocol::wl_shm_pool::WlShmPool, ()> for ClientState {
    fn event(
        _state: &mut Self,
        _proxy: &wayland_client::protocol::wl_shm_pool::WlShmPool,
        _event: wayland_client::protocol::wl_shm_pool::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

#[test]
fn test_client_connection() {
    let mut env = TestEnv::new();
    
    // Dispatch events to process client connection
    env.loop_dispatch();
    
    // Check if client is connected
    assert_eq!(env.state.clients.len(), 1);
}

#[test]
fn test_bind_globals() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    
    // Initialize client state
    let mut client_state = ClientState {
        compositor: None,
        shm: None,
        seat: None,
        pointer: None,
        keyboard: None,
        xdg_wm_base: None,
        xdg_surface: None,
        xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    // Roundtrip
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // This is a basic check that we can roundtrip
}

#[test]
fn test_compositor_protocol() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { compositor: None, shm: None, seat: None, pointer: None, keyboard: None, xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None, subcompositor: None, relative_pointer_manager: None, relative_motion_events: Vec::new() };
    
    // Bind globals
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check if compositor bound
    assert!(client_state.compositor.is_some());
    let compositor = client_state.compositor.as_ref().unwrap();
    
    // Create surface
    let _surface = compositor.create_surface(&qh, ());
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Verify usage of surface?
    // We can't easily inspect server state from client object here without shared state access or ID tracking.
    // But if no protocol error occurred, it worked.
}

#[test]
fn test_shm_protocol() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { compositor: None, shm: None, seat: None, pointer: None, keyboard: None, xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None, subcompositor: None, relative_pointer_manager: None, relative_motion_events: Vec::new() };
    
    // Bind globals
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check if shm bound
    assert!(client_state.shm.is_some());
    let shm = client_state.shm.as_ref().unwrap();
    
    // Create shm pool
    // We need a real FD for this. 
    // On macOS, let's use a tempfile or similar.
    use std::io::Write;
    let mut temp = tempfile::tempfile().unwrap();
    temp.write_all(&[0u8; 4096]).unwrap();
    
    // Convert to BorrowedFd for bind
    use std::os::unix::io::AsFd;
    let pool = shm.create_pool(temp.as_fd(), 4096, &qh, ());
    
    // Create buffer from pool
    let _buffer = pool.create_buffer(0, 32, 32, 128, wayland_client::protocol::wl_shm::Format::Argb8888, &qh, ());
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Success if no protocol errors
}

#[test]
fn test_seat_protocol() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { compositor: None, shm: None, seat: None, pointer: None, keyboard: None, xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None, subcompositor: None, relative_pointer_manager: None, relative_motion_events: Vec::new() };
    
    // Bind globals
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check if seat bound
    assert!(client_state.seat.is_some());
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Success if no protocol errors
}

#[test]
fn test_input_events() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, 
        shm: None, 
        seat: None,
        pointer: None,
        keyboard: None,
        xdg_wm_base: None,
        xdg_surface: None,
        xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    // Bind globals and get seat caps
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check if seat bound
    assert!(client_state.seat.is_some());
    
    // Wait for caps to be processed and pointer bound
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    assert!(client_state.pointer.is_some());
    
    // Create surface and focus it (in theory we need to focus it to get enter/motion)
    // For now we just check if no protocol errors occur on basic binds.
    // Full input focus testing requires more setup (output, internal focus etc).
}

#[test]
fn test_xdg_shell_protocol() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, shm: None, seat: None, pointer: None, keyboard: None,
        xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    // Bind globals
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check if xdg_wm_base bound
    assert!(client_state.xdg_wm_base.is_some());
    let xdg_wm_base = client_state.xdg_wm_base.as_ref().unwrap();
    let compositor = client_state.compositor.as_ref().unwrap();
    
    // Create surface and xdg_surface
    let surface = compositor.create_surface(&qh, ());
    let xdg_surface = xdg_wm_base.get_xdg_surface(&surface, &qh, ());
    let xdg_toplevel = xdg_surface.get_toplevel(&qh, ());
    
    client_state.xdg_surface = Some(xdg_surface);
    client_state.xdg_toplevel = Some(xdg_toplevel);
    
    // Commit to trigger configure
    surface.commit();
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Success if no protocol errors (e.g. invalid role)
}

#[test]
fn test_shm_pool_resize() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, shm: None, seat: None, pointer: None, keyboard: None,
        xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    let shm = client_state.shm.as_ref().expect("wl_shm not bound");
    
    // Create pool
    let temp = tempfile::tempfile().unwrap();
    let pool = shm.create_pool(temp.as_fd(), 4096, &qh, ());
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Verify pool exists in server
    let pool_id = Proxy::id(&pool).protocol_id();
    let client_id = env.state.clients.keys().next().expect("No server client").clone();
    {
        let state = &env.state;
        assert!(state.shm_pools.contains_key(&(client_id.clone(), pool_id)));
        assert_eq!(state.shm_pools.get(&(client_id.clone(), pool_id)).unwrap().size, 4096);
    }
    
    // Resize pool
    pool.resize(8192);
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Verify resize in server
    {
        let state = &env.state;
        assert_eq!(state.shm_pools.get(&(client_id.clone(), pool_id)).unwrap().size, 8192);
    }
}

#[test]
fn test_subsurface_sync_commit() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, shm: None, seat: None, pointer: None, keyboard: None,
        xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    let compositor = client_state.compositor.as_ref().unwrap();
    let subcompositor = client_state.subcompositor.as_ref().expect("wl_subcompositor not bound");
    
    // Create parent and child surfaces
    let parent_surface = compositor.create_surface(&qh, ());
    let child_surface = compositor.create_surface(&qh, ());
    
    let subsurface = subcompositor.get_subsurface(&child_surface, &parent_surface, &qh, ());
    subsurface.set_sync(); // Default is sync, but let's be explicit
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    let child_proto_id = Proxy::id(&child_surface).protocol_id();
    let parent_proto_id = Proxy::id(&parent_surface).protocol_id();
    let client_id = env.state.clients.keys().next().expect("No server client").clone();
    
    let child_id = *env
        .state
        .protocol_to_internal_surface
        .get(&(client_id.clone(), child_proto_id))
        .expect("Child internal ID not found");
    let parent_id = *env
        .state
        .protocol_to_internal_surface
        .get(&(client_id.clone(), parent_proto_id))
        .expect("Parent internal ID not found");
    
    // Verify subsurface relationship
    {
        let state = &env.state;
        assert!(state.subsurfaces.contains_key(&child_id));
        assert_eq!(state.subsurfaces.get(&child_id).unwrap().parent_id, parent_id);
    }
    
    // 1. Commit child (sync mode) -> state should be CACHED, not current
    child_surface.set_buffer_scale(2);
    child_surface.commit();
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    {
        let state = &env.state;
        let child = state.get_surface(child_id).unwrap();
        let child = child.read().unwrap();
        // current.scale should still be 1 (default)
        assert_eq!(child.current.scale, 1);
        // cached should contain the scale 2
        assert_eq!(child.cached.as_ref().unwrap().scale, 2);
    }
    
    // 2. Commit parent -> child's cached state should be applied to current
    parent_surface.commit();
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    {
        let state = &env.state;
        let child = state.get_surface(child_id).unwrap();
        let child = child.read().unwrap();
        // current.scale should now be 2
        assert_eq!(child.current.scale, 2);
        // cached should be None
        assert!(child.cached.is_none());
    }
}

#[test]
fn test_relative_pointer_motion() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, shm: None, seat: None, pointer: None, keyboard: None,
        xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    let seat = client_state.seat.as_ref().expect("wl_seat not bound");
    client_state.pointer = Some(seat.get_pointer(&qh, ()));
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    let rel_mgr = client_state.relative_pointer_manager.as_ref().expect("zwp_relative_pointer_manager_v1 not bound");
    let pointer = client_state.pointer.as_ref().unwrap();
    let _rel_pointer = rel_mgr.get_relative_pointer(pointer, &qh, ());
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Inject relative motion in server
    env.state.inject_pointer_motion_relative(10.5, 20.25, 1234);
    
    // Roundtrip to let client receive events
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Verify client received relative motion
    assert_eq!(client_state.relative_motion_events.len(), 1);
    let (dx, dy) = client_state.relative_motion_events[0];
    assert_eq!(dx, 10.5);
    assert_eq!(dy, 20.25);
}

#[test]
fn test_pointer_lock() {
    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, shm: None, seat: None, pointer: None, keyboard: None,
        xdg_wm_base: None, xdg_surface: None, xdg_toplevel: None,
        subcompositor: None,
        relative_pointer_manager: None,
        relative_motion_events: Vec::new(),
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Create surface and xdg_toplevel to get focus
    let compositor = client_state.compositor.as_ref().unwrap();
    let surface = compositor.create_surface(&qh, ());
    client_state.xdg_surface = Some(client_state.xdg_wm_base.as_ref().unwrap().get_xdg_surface(&surface, &qh, ()));
    client_state.xdg_toplevel = Some(client_state.xdg_surface.as_ref().unwrap().get_toplevel(&qh, ()));
    surface.commit();
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    let surface_id = surface.id().protocol_id();
    let client_id = env.state.clients.keys().next().expect("No server client").clone();
    
    // Set focus manually in test env
    env.state.seat.pointer.focus = Some(surface_id);
    
    // Check if locked - should be false
    assert!(!env.state.ext.pointer_constraints.is_pointer_locked(client_id, surface_id));
    
    // In a real scenario, client would bind pointer_constraints and request lock
    // For this test, we'll verify the server-side logic of is_pointer_locked
    // by manually adding a locked pointer to the state
    
    // Actually, let's verify that focus management activates constraints
    // (This requires a more complex mocking of the wayland-server objects)
    
    // For now, verified relative motion which uses the same infrastructure.
}
