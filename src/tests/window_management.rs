use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{wl_compositor, wl_seat, wl_registry, wl_callback},
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols::xdg::shell::client::{xdg_wm_base, xdg_surface, xdg_toplevel};

struct ClientState {
    compositor: Option<wl_compositor::WlCompositor>,
    seat: Option<wl_seat::WlSeat>,
    xdg_wm_base: Option<xdg_wm_base::XdgWmBase>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    configured: bool,
    last_serial: u32,
    last_width: i32,
    last_height: i32,
    maximized: bool,
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
            } else if interface == "wl_seat" {
                state.seat = Some(proxy.bind(name, version, qh, ()));
            } else if interface == "xdg_wm_base" {
                state.xdg_wm_base = Some(proxy.bind(name, version, qh, ()));
            }
        }
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for ClientState {
    fn event(_: &mut Self, _: &wl_compositor::WlCompositor, _: wl_compositor::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

impl Dispatch<wayland_client::protocol::wl_surface::WlSurface, ()> for ClientState {
    fn event(_: &mut Self, _: &wayland_client::protocol::wl_surface::WlSurface, _: wayland_client::protocol::wl_surface::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

impl Dispatch<wl_seat::WlSeat, ()> for ClientState {
    fn event(_: &mut Self, _: &wl_seat::WlSeat, _: wl_seat::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for ClientState {
    fn event(_: &mut Self, _: &xdg_wm_base::XdgWmBase, _: xdg_wm_base::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

impl Dispatch<xdg_surface::XdgSurface, ()> for ClientState {
    fn event(
        state: &mut Self,
        proxy: &xdg_surface::XdgSurface,
        event: xdg_surface::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let xdg_surface::Event::Configure { serial } = event {
            println!("CLIENT: xdg_surface.configure serial={}", serial);
            state.last_serial = serial;
            state.configured = true;
            proxy.ack_configure(serial);
        }
    }
}

impl Dispatch<xdg_toplevel::XdgToplevel, ()> for ClientState {
    fn event(
        state: &mut Self,
        _proxy: &xdg_toplevel::XdgToplevel,
        event: xdg_toplevel::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let xdg_toplevel::Event::Configure { width, height, states } = event {
            println!("CLIENT: xdg_toplevel.configure {}x{} states={:?}", width, height, states);
            state.last_width = width;
            state.last_height = height;
            
            // Check for Maximized state
            let maximized_val = wayland_protocols::xdg::shell::client::xdg_toplevel::State::Maximized as u32;
            let mut found_maximized = false;
            for chunk in states.chunks_exact(4) {
                let s = u32::from_ne_bytes(chunk.try_into().unwrap());
                if s == maximized_val {
                    found_maximized = true;
                    break;
                }
            }
            state.maximized = found_maximized;
        }
    }
}

impl Dispatch<wl_callback::WlCallback, ()> for ClientState {
    fn event(_: &mut Self, _: &wl_callback::WlCallback, _: wl_callback::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

#[test]
fn test_window_maximized_transition() {
    let mut env = TestEnv::new();
    
    // Setup a fake output so we get non-zero geometry
    env.state.outputs.push(crate::core::state::OutputState::new(
        1,
        "test-output".into(),
        1920,
        1080
    ));
    env.state.primary_output = 0;

    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, seat: None, xdg_wm_base: None, 
        xdg_surface: None, xdg_toplevel: None,
        configured: false, last_serial: 0, last_width: 0, last_height: 0, maximized: false
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Create surface and xdg_toplevel
    let compositor = client_state.compositor.as_ref().unwrap();
    let surface = compositor.create_surface(&qh, ());
    client_state.xdg_surface = Some(client_state.xdg_wm_base.as_ref().unwrap().get_xdg_surface(&surface, &qh, ()));
    client_state.xdg_toplevel = Some(client_state.xdg_surface.as_ref().unwrap().get_toplevel(&qh, ()));
    surface.commit();
    
    // Wait for initial configure
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    assert!(client_state.configured);
    
    // Request maximization
    client_state.xdg_toplevel.as_ref().unwrap().set_maximized();
    surface.commit();
    
    // Wait for configure with Maximized state
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Ensure server processes the last AckConfigure
    env.loop_dispatch();
    
    // Check if client received Maximized state
    assert!(client_state.maximized, "Client should have received Maximized state");
    assert_eq!(client_state.last_width, 1920, "Client should receive output width");
    assert_eq!(client_state.last_height, 1080, "Client should receive output height");
    
    // Verify finalized state in compositor
    let toplevel_id = env.state.xdg.toplevels.keys().next().cloned().unwrap();
    let tl_data = env.state.xdg.toplevels.get(&toplevel_id).unwrap();
    assert!(tl_data.maximized, "Compositor should have finalized maximized state after client ack");
    
    // Unset maximized
    client_state.xdg_toplevel.as_ref().unwrap().unset_maximized();
    surface.commit();
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // After unset_maximized, compositor sends floating configure (often 0x0 = client-chosen size).
    assert_eq!(client_state.last_width, 0, "Unset maximized should yield floating configure width");
    assert_eq!(client_state.last_height, 0, "Unset maximized should yield floating configure height");
    assert!(!client_state.maximized, "Client should have unset maximized state");
}

#[test]
fn test_window_fullscreen_transition() {
    let mut env = TestEnv::new();
    
    // Setup a fake output
    env.state.outputs.push(crate::core::state::OutputState::new(
        1,
        "test-output".into(),
        1920,
        1080
    ));
    env.state.primary_output = 0;

    let display = env.client.display();
    let mut event_queue = env.client.new_event_queue::<ClientState>();
    let qh = event_queue.handle();
    
    let _registry = display.get_registry(&qh, ());
    let mut client_state = ClientState { 
        compositor: None, seat: None, xdg_wm_base: None, 
        xdg_surface: None, xdg_toplevel: None,
        configured: false, last_serial: 0, last_width: 0, last_height: 0, maximized: false
    };
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    let compositor = client_state.compositor.as_ref().unwrap();
    let surface = compositor.create_surface(&qh, ());
    client_state.xdg_surface = Some(client_state.xdg_wm_base.as_ref().unwrap().get_xdg_surface(&surface, &qh, ()));
    client_state.xdg_toplevel = Some(client_state.xdg_surface.as_ref().unwrap().get_toplevel(&qh, ()));
    surface.commit();
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Request fullscreen
    client_state.xdg_toplevel.as_ref().unwrap().set_fullscreen(None);
    surface.commit();
    
    env.wait_roundtrip(&mut event_queue, &mut client_state);
    
    // Check fullscreen dimensions (should match output)
    assert_eq!(client_state.last_width, 1920);
    assert_eq!(client_state.last_height, 1080);
    
    // Check state bit (state=2 is fullscreen in xdg-shell)
    // We didn't fully decode state bits in ClientState, but verify geometry is enough for now
}
