#![cfg(feature = "waypipe-ssh")]

use crate::util::ssh::{SshConfig, SshTunnel, pump};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::thread;
use std::os::unix::net::UnixStream;
use std::os::unix::io::AsRawFd;
use tracing::{info, error};

#[no_mangle]
pub extern "C" fn wawona_ssh_tunnel_create(
    host: *const c_char,
    port: u16,
    username: *const c_char,
    password: *const c_char,
) -> *mut SshTunnel {
    if host.is_null() || username.is_null() {
        return std::ptr::null_mut();
    }

    let host = unsafe { CStr::from_ptr(host) }.to_string_lossy().into_owned();
    let username = unsafe { CStr::from_ptr(username) }.to_string_lossy().into_owned();
    let password = if password.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(password) }.to_string_lossy().into_owned())
    };

    let config = SshConfig {
        host,
        port,
        username,
        password,
        key_path: None, // TODO: add key support to FFI
    };

    match SshTunnel::connect(config) {
        Ok(tunnel) => Box::into_raw(Box::new(tunnel)),
        Err(e) => {
            error!("FFI: Failed to create SSH tunnel: {}", e);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn wawona_ssh_tunnel_free(tunnel: *mut SshTunnel) {
    if !tunnel.is_null() {
        unsafe {
            let _ = Box::from_raw(tunnel);
        }
    }
}

/// Spawns a background thread that pumps data between a local Unix socket and an SSH channel.
/// Returns a file descriptor for the local side of the pump. 
/// The SSH channel will be used to execute 'command'.
#[no_mangle]
pub extern "C" fn wawona_ssh_tunnel_spawn_pump(
    tunnel: *mut SshTunnel,
    command: *const c_char,
) -> c_int {
    if tunnel.is_null() || command.is_null() {
        return -1;
    }

    let tunnel = unsafe { &*tunnel };
    let command = unsafe { CStr::from_ptr(command) }.to_string_lossy().into_owned();

    match tunnel.open_channel_for_command(&command) {
        Ok(channel) => {
            // Create a socket pair
            match UnixStream::pair() {
                Ok((local_stream, pump_stream)) => {
                    let _local_fd = local_stream.as_raw_fd();
                    
                    // We need to keep the local_stream alive in the caller or elsewhere?
                    // Actually, if we return the FD, the caller owns it.
                    // But UnixStream will close the FD when dropped.
                    // So we must leak it or use into_raw_fd.
                    use std::os::unix::io::IntoRawFd;
                    let local_fd_final = local_stream.into_raw_fd();

                    // Spawn the pump thread
                    thread::spawn(move || {
                        info!("SSH: Starting pump for command: {}", command);
                        if let Err(e) = pump(pump_stream, channel) {
                            error!("SSH: Pump error for {}: {}", command, e);
                        }
                        info!("SSH: Pump finished for command: {}", command);
                    });

                    local_fd_final
                }
                Err(e) => {
                    error!("FFI: Failed to create UnixStream pair: {}", e);
                    -1
                }
            }
        }
        Err(e) => {
            error!("FFI: Failed to open SSH channel: {}", e);
            -1
        }
    }
}
