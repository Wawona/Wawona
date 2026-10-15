//! Android Native Shell session. Spawn bundled `libzsh_bin.so` on a PTY.
//! Keys go to the master. The host feeds master output into `wwn_term`.

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::sync::Mutex;

struct Live {
    fd: i32,
    pid: i32,
}

static LIVE: Mutex<Option<Live>> = Mutex::new(None);

fn lock() -> std::sync::MutexGuard<'static, Option<Live>> {
    LIVE.lock().unwrap_or_else(|err| err.into_inner())
}

fn set_nonblock(fd: i32) {
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags >= 0 {
            libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
    }
}

fn set_slave_termios(slave: i32) {
    unsafe {
        let mut term: libc::termios = std::mem::zeroed();
        if libc::tcgetattr(slave, &mut term) != 0 {
            return;
        }
        term.c_iflag |= libc::ICRNL;
        term.c_oflag |= libc::OPOST | libc::ONLCR;
        term.c_lflag |= libc::ECHO | libc::ECHOE | libc::ICANON | libc::ISIG;
        term.c_cc[libc::VERASE] = 0x7f;
        term.c_cc[libc::VINTR] = 3;
        term.c_cc[libc::VEOF] = 4;
        libc::tcsetattr(slave, libc::TCSANOW, &term);
    }
}

fn set_winsize(fd: i32, cols: i32, rows: i32) {
    if cols < 1 || rows < 1 {
        return;
    }
    let mut size = libc::winsize {
        ws_row: rows as u16,
        ws_col: cols as u16,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe {
        libc::ioctl(fd, libc::TIOCSWINSZ, &mut size);
    }
}

/// Open `/dev/ptmx`, spawn `shell_path -i` on the slave. Returns the master
/// fd, or -1 when zsh or the PTY is missing.
#[no_mangle]
pub extern "C" fn wwn_android_shell_start(shell_path: *const c_char) -> c_int {
    if shell_path.is_null() {
        return -1;
    }
    let path = unsafe { CStr::from_ptr(shell_path) };
    if path.to_bytes().is_empty() {
        return -1;
    }
    wwn_android_shell_stop();

    unsafe {
        let master = libc::open(c"/dev/ptmx".as_ptr(), libc::O_RDWR | libc::O_CLOEXEC);
        if master < 0 {
            return -1;
        }
        if libc::grantpt(master) != 0 || libc::unlockpt(master) != 0 {
            libc::close(master);
            return -1;
        }
        let mut name = [0u8; 64];
        if libc::ptsname_r(
            master,
            name.as_mut_ptr() as *mut c_char,
            name.len(),
        ) != 0
        {
            libc::close(master);
            return -1;
        }
        let slave = libc::open(name.as_ptr() as *const c_char, libc::O_RDWR | libc::O_CLOEXEC);
        if slave < 0 {
            libc::close(master);
            return -1;
        }
        set_slave_termios(slave);
        set_winsize(master, 80, 24);
        let dash_i = c"-i";
        let argv = [
            path.as_ptr(),
            dash_i.as_ptr(),
            std::ptr::null(),
        ];
        // Child only calls async-signal-safe functions, then exec. That is the
        // allowed window after fork in this multithreaded process. posix_spawn
        // cannot ioctl TIOCSCTTY, so zsh would have no controlling terminal.
        let pid = libc::fork();
        if pid < 0 {
            libc::close(slave);
            libc::close(master);
            return -1;
        }
        if pid == 0 {
            libc::setsid();
            libc::ioctl(slave, libc::TIOCSCTTY, 0);
            libc::dup2(slave, 0);
            libc::dup2(slave, 1);
            libc::dup2(slave, 2);
            if slave > 2 {
                libc::close(slave);
            }
            libc::close(master);
            libc::execv(path.as_ptr(), argv.as_ptr());
            libc::_exit(127);
        }
        libc::close(slave);
        set_nonblock(master);
        *lock() = Some(Live { fd: master, pid });
        master
    }
}

#[no_mangle]
pub extern "C" fn wwn_android_shell_write(fd: c_int, bytes: *const u8, len: usize) -> c_int {
    if fd < 0 || bytes.is_null() || len == 0 {
        return -1;
    }
    if lock().as_ref().map(|live| live.fd) != Some(fd) {
        return -1;
    }
    let n = unsafe { libc::write(fd, bytes as *const libc::c_void, len) };
    if n > 0 {
        return n as c_int;
    }
    let err = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
    if err == libc::EAGAIN || err == libc::EWOULDBLOCK || err == libc::EINTR {
        0
    } else {
        -1
    }
}

/// Positive byte count, 0 when the master has nothing ready, -2 on EOF, -1 on error.
#[no_mangle]
pub extern "C" fn wwn_android_shell_read(fd: c_int, buf: *mut u8, cap: usize) -> c_int {
    if fd < 0 || buf.is_null() || cap == 0 {
        return -1;
    }
    let guard = lock();
    if guard.as_ref().map(|live| live.fd) != Some(fd) {
        return -1;
    }
    let n = unsafe { libc::read(fd, buf as *mut libc::c_void, cap) };
    if n > 0 {
        return n as c_int;
    }
    if n == 0 {
        return -2;
    }
    let err = std::io::Error::last_os_error()
        .raw_os_error()
        .unwrap_or(0);
    if err == libc::EAGAIN || err == libc::EWOULDBLOCK || err == libc::EINTR {
        0
    } else if err == libc::EIO {
        // Slave closed. Linux PTY masters return EIO, not a zero-length read.
        -2
    } else {
        -1
    }
}

#[no_mangle]
pub extern "C" fn wwn_android_shell_resize(fd: c_int, cols: c_int, rows: c_int) {
    let guard = lock();
    if guard.as_ref().map(|live| live.fd) == Some(fd) {
        set_winsize(fd, cols, rows);
    }
}

#[no_mangle]
pub extern "C" fn wwn_android_shell_stop() {
    let live = lock().take();
    if let Some(live) = live {
        unsafe {
            libc::kill(live.pid, libc::SIGHUP);
            libc::close(live.fd);
            let mut status = 0;
            libc::waitpid(live.pid, &mut status, libc::WNOHANG);
        }
    }
}
