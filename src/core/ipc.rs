use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use std::thread;

use crate::core::state::CompositorState;

pub struct IpcServer {
    socket_path: Option<PathBuf>,
}

impl IpcServer {
    pub fn new(state: Arc<RwLock<CompositorState>>) -> Self {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        // Use a short name ("wwn.sock") to stay within SUN_LEN (104 bytes)
        // on iOS where the sandbox path is already ~85 characters.
        let socket_path = PathBuf::from(runtime_dir).join("wwn.sock");

        // Clean up old socket
        if socket_path.exists() {
            let _ = std::fs::remove_file(&socket_path);
        }

        // Check path length before binding — Unix domain sockets have a
        // hard limit (SUN_LEN = 104 on Apple platforms).
        let path_bytes = socket_path.as_os_str().as_encoded_bytes().len();
        if path_bytes >= 104 {
            tracing::warn!(
                "IPC socket path too long ({} bytes, max 103): {:?} — IPC disabled",
                path_bytes, socket_path
            );
            return IpcServer { socket_path: None };
        }

        let listener = match UnixListener::bind(&socket_path) {
            Ok(l) => l,
            Err(e) => {
                tracing::warn!("Failed to bind IPC socket {:?}: {} — IPC disabled", socket_path, e);
                return IpcServer { socket_path: None };
            }
        };

        tracing::info!("IPC server listening on {:?}", socket_path);

        thread::spawn(move || {
            for stream in listener.incoming() {
                match stream {
                    Ok(mut stream) => {
                        let state = state.clone();
                        thread::spawn(move || {
                            let mut reader = BufReader::new(stream.try_clone().unwrap());
                            let mut line = String::new();
                            loop {
                                line.clear();
                                if reader.read_line(&mut line).unwrap_or(0) == 0 {
                                    break;
                                }
                                
                                let cmd = line.trim();
                                let response = match cmd {
                                    "ping" => "pong\n".to_string(),
                                    "version" => format!("wawona {}\n", env!("CARGO_PKG_VERSION")),
                                    "windows" => {
                                        if let Ok(state) = state.read() {
                                            let mut out = String::new();
                                            out.push_str(&format!("Window count: {}\n", state.windows.len()));
                                            for (id, window) in &state.windows {
                                                if let Ok(w) = window.read() {
                                                    out.push_str(&format!("Window {}: \"{}\" ({}x{}) - Surface {}\n", 
                                                        id, w.title, w.geometry().width, w.geometry().height, w.surface_id));
                                                }
                                            }
                                            out
                                        } else {
                                            "error: lock failed\n".to_string()
                                        }
                                    },
                                    "tree" => {
                                        if let Ok(state) = state.read() {
                                            state.scene.dump()
                                        } else {
                                            "error: lock failed\n".to_string()
                                        }
                                    },
                                    _ => "error: unknown command\n".to_string(),
                                };
                                
                                if let Err(e) = stream.write_all(response.as_bytes()) {
                                    tracing::error!("IPC write error: {}", e);
                                    break;
                                }
                            }
                        });
                    }
                    Err(err) => {
                        tracing::error!("IPC connect error: {}", err);
                    }
                }
            }
        });

        IpcServer { socket_path: Some(socket_path) }
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        if let Some(ref path) = self.socket_path {
            if path.exists() {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}
