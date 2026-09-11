use crate::core::state::{ClientState, CompositorState};
use std::os::unix::net::UnixStream;
use std::sync::Arc;
use wayland_client::Connection;
use wayland_server::{Client, Display};

pub struct TestEnv {
    pub display: Display<CompositorState>,
    pub client: Connection,
    pub server_client: Client,
    pub state: CompositorState,
}

impl TestEnv {
    pub fn new() -> Self {
        let mut display = Display::<CompositorState>::new().unwrap();
        let mut handle = display.handle();

        // Create socket pair
        let (server_sock, client_sock) = UnixStream::pair().unwrap();

        // Create client connection
        let client = Connection::from_socket(client_sock).unwrap();

        // Initialize state
        let mut state = CompositorState::new(None);

        // Register protocols (match production compositor registration order)
        crate::core::wayland::smithay_runtime::register_core_shell(&mut state, &handle);
        crate::core::wayland::smithay_runtime::register_extensions_wlr(&mut state);
        crate::core::wayland::wayland::register(&mut state, &handle);
        crate::core::wayland::xdg::register(&mut state, &handle);
        crate::core::wayland::wlr::register(&mut state, &handle);
        crate::core::wayland::plasma::register(&mut state, &handle);
        crate::core::wayland::ext::register(&mut state, &handle);
        crate::core::wayland::host_im::attach(&mut display, &mut state);

        // Create client on server side
        let client_data = ClientState { id: Some(1) };
        let client_obj = handle
            .insert_client(server_sock, Arc::new(client_data.clone()))
            .unwrap();
        let client_id = client_obj.id();
        state.clients.insert(client_id, client_data);

        Self {
            display,
            client,
            server_client: client_obj,
            state,
        }
    }

    /// Extra Wayland client on the same compositor (Copy in A / Paste in B).
    pub fn add_client(&mut self, id: u32) -> (Connection, Client) {
        let (server_sock, client_sock) = UnixStream::pair().unwrap();
        let mut handle = self.display.handle();
        let client_data = ClientState { id: Some(id) };
        let server_client = handle
            .insert_client(server_sock, Arc::new(client_data.clone()))
            .unwrap();
        self.state.clients.insert(server_client.id(), client_data);
        (
            Connection::from_socket(client_sock).unwrap(),
            server_client,
        )
    }

    pub fn loop_dispatch(&mut self) {
        crate::core::wayland::host_im::pump(&mut self.display, &mut self.state);
    }

    /// Process events on both sides until a roundtrip is complete
    pub fn wait_roundtrip<
        S: wayland_client::Dispatch<wayland_client::protocol::wl_callback::WlCallback, ()> + 'static,
    >(
        &mut self,
        queue: &mut wayland_client::EventQueue<S>,
        state: &mut S,
    ) {
        // Send sync request
        let display = self.client.display();
        let _callback = display.sync(&queue.handle(), ());

        // Ensure client sends the request
        self.client.flush().expect("Client flush failed");

        // Loop until callback is received
        // In a test env we can just do a few iterations
        for _ in 0..20 {
            // Server side
            self.loop_dispatch();

            // Client side: Read and dispatch
            if let Some(guard) = self.client.prepare_read() {
                guard.read().ok();
            }
            queue.dispatch_pending(state).ok();
            self.client.flush().ok();
        }
    }

    /// Roundtrip a specific client connection (second seat client, etc.).
    pub fn wait_roundtrip_on<
        S: wayland_client::Dispatch<wayland_client::protocol::wl_callback::WlCallback, ()> + 'static,
    >(
        &mut self,
        conn: &Connection,
        queue: &mut wayland_client::EventQueue<S>,
        state: &mut S,
    ) {
        let display = conn.display();
        let _callback = display.sync(&queue.handle(), ());
        conn.flush().expect("Client flush failed");
        for _ in 0..20 {
            self.loop_dispatch();
            if let Some(guard) = conn.prepare_read() {
                guard.read().ok();
            }
            queue.dispatch_pending(state).ok();
            conn.flush().ok();
        }
    }
}
