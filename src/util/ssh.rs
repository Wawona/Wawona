#![cfg(feature = "waypipe-ssh")]

use std::net::TcpStream;
use ssh2::Session;
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use tracing::{info, debug};

pub struct SshConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
    pub key_path: Option<String>,
}

pub struct SshTunnel {
    session: Session,
    _tcp: TcpStream,
}

impl SshTunnel {
    pub fn connect(config: SshConfig) -> anyhow::Result<Self> {
        info!("SSH: Connecting to {}:{}", config.host, config.port);
        let tcp = TcpStream::connect(format!("{}:{}", config.host, config.port))?;
        let mut session = Session::new()?;
        session.set_tcp_stream(tcp.try_clone()?);
        session.handshake()?;

        if let Some(password) = config.password {
            debug!("SSH: Authenticating with password for user {}", config.username);
            session.userauth_password(&config.username, &password)?;
        } else if let Some(key_path) = config.key_path {
            debug!("SSH: Authenticating with key {} for user {}", key_path, config.username);
            session.userauth_pubkey_file(&config.username, None, std::path::Path::new(&key_path), None)?;
        } else {
            anyhow::bail!("No authentication method provided");
        }

        if !session.authenticated() {
            anyhow::bail!("SSH authentication failed");
        }

        info!("SSH: Authenticated successfully");

        Ok(Self {
            session,
            _tcp: tcp,
        })
    }

    /// Spawns a remote command and returns a channel that can be used for bidirectional I/O.
    /// This is typically used to launch 'waypipe server' on the remote host.
    pub fn open_channel_for_command(&self, command: &str) -> anyhow::Result<ssh2::Channel> {
        let mut channel = self.session.channel_session()?;
        channel.exec(command)?;
        Ok(channel)
    }
}

/// Pump data bidirectionally between two streams using poll() for efficiency.
/// Both streams must support AsRawFd (Unix sockets, TCP streams, etc.)
pub fn pump_poll<S1, S2>(mut stream1: S1, mut stream2: S2) -> std::io::Result<()>
where
    S1: Read + Write + AsRawFd,
    S2: Read + Write + AsRawFd,
{
    let fd1 = stream1.as_raw_fd();
    let fd2 = stream2.as_raw_fd();

    let mut buf1 = [0u8; 16384];
    let mut buf2 = [0u8; 16384];

    loop {
        let mut fds = [
            libc::pollfd {
                fd: fd1,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: fd2,
                events: libc::POLLIN,
                revents: 0,
            },
        ];

        let ret = unsafe { libc::poll(fds.as_mut_ptr(), 2, 500) };

        if ret < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }

        if ret == 0 {
            continue;
        }

        if fds[0].revents & libc::POLLIN != 0 {
            match stream1.read(&mut buf1) {
                Ok(0) => break,
                Ok(n) => {
                    stream2.write_all(&buf1[..n])?;
                    stream2.flush()?;
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(e) => return Err(e),
            }
        }

        if fds[1].revents & libc::POLLIN != 0 {
            match stream2.read(&mut buf2) {
                Ok(0) => break,
                Ok(n) => {
                    stream1.write_all(&buf2[..n])?;
                    stream1.flush()?;
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                Err(e) => return Err(e),
            }
        }

        if fds[0].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
            || fds[1].revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
        {
            break;
        }
    }
    Ok(())
}

/// Pump data bidirectionally between two streams using a simple read loop.
/// Works with any Read+Write streams (including ssh2::Channel which lacks AsRawFd).
/// Uses non-blocking polling via short timeouts.
pub fn pump<S1, S2>(mut stream1: S1, mut stream2: S2) -> std::io::Result<()>
where
    S1: Read + Write,
    S2: Read + Write,
{
    let mut buf = [0u8; 16384];

    loop {
        match stream1.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                stream2.write_all(&buf[..n])?;
                stream2.flush()?;
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }

        match stream2.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                stream1.write_all(&buf[..n])?;
                stream1.flush()?;
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }
    Ok(())
}
