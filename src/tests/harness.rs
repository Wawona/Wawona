use std::sync::Arc;
use std::os::unix::net::UnixStream;
use wayland_server::Display;
use wayland_client::Connection;
use crate::core::state::{CompositorState, ClientState};

pub struct TestEnv {
    pub display: Display<CompositorState>,
    pub client: Connection,
    pub state: CompositorState,
}

impl TestEnv {
    pub fn new() -> Self {
        let display = Display::<CompositorState>::new().unwrap();
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
        crate::core::wayland::ext::register(&mut state, &handle);
        
        // Create client on server side
        let client_data = ClientState { id: Some(1) };
        let client_obj = handle.insert_client(server_sock, Arc::new(client_data.clone())).unwrap();
        let client_id = client_obj.id();
        state.clients.insert(client_id, client_data);
        
        Self {
            display,
            client,
            state,
        }
    }
    
    pub fn loop_dispatch(&mut self) {
        self.display.dispatch_clients(&mut self.state).expect("Server dispatch failed");
        self.display.flush_clients().expect("Server flush failed");
    }
    
    /// Process events on both sides until a roundtrip is complete
    pub fn wait_roundtrip<S: wayland_client::Dispatch<wayland_client::protocol::wl_callback::WlCallback, ()> + 'static>(&mut self, queue: &mut wayland_client::EventQueue<S>, state: &mut S) {
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
}
