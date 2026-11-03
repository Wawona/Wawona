//! Wawona Terminal must not sit on a dead prompt with no explanation.
//!
//! A PTY master returns 0 or `EIO` when the slave closes. That is a finished
//! session, not a frozen grid. The host draws [`ENDED_NOTICE`] and stops
//! sending keys. A live shell that is idle (`EAGAIN`) stays live.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PtyReadKind {
    Bytes,
    WouldBlock,
    Eof,
    Hangup,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScreenFate {
    Keep,
    Ended,
}

pub const ENDED_NOTICE: &str = "[session ended]";

/// Classify one `read` on a nonblocking PTY master.
/// `n > 0` is bytes. `n == 0` is EOF. `n < 0` uses `errno`.
pub fn classify_pty_read(n: isize, errno: i32) -> PtyReadKind {
    if n > 0 {
        return PtyReadKind::Bytes;
    }
    if n == 0 {
        return PtyReadKind::Eof;
    }
    // EAGAIN 11, EWOULDBLOCK 11 on Linux, EINTR 4. Darwin EAGAIN is 35.
    if errno == 11 || errno == 35 || errno == 4 {
        return PtyReadKind::WouldBlock;
    }
    PtyReadKind::Hangup
}

pub fn screen_fate(kind: PtyReadKind) -> ScreenFate {
    match kind {
        PtyReadKind::Bytes | PtyReadKind::WouldBlock => ScreenFate::Keep,
        PtyReadKind::Eof | PtyReadKind::Hangup => ScreenFate::Ended,
    }
}

/// `exited` is true when `waitpid(WNOHANG)` reaped the child.
pub fn child_fate(exited: bool) -> ScreenFate {
    if exited {
        ScreenFate::Ended
    } else {
        ScreenFate::Keep
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_and_bytes_stay_live() {
        assert_eq!(screen_fate(classify_pty_read(12, 0)), ScreenFate::Keep);
        assert_eq!(screen_fate(classify_pty_read(-1, 11)), ScreenFate::Keep);
        assert_eq!(screen_fate(classify_pty_read(-1, 35)), ScreenFate::Keep);
        assert_eq!(screen_fate(classify_pty_read(-1, 4)), ScreenFate::Keep);
        assert_eq!(child_fate(false), ScreenFate::Keep);
    }

    #[test]
    fn eof_and_eio_end_the_screen() {
        assert_eq!(screen_fate(classify_pty_read(0, 0)), ScreenFate::Ended);
        // Linux PTY EIO is 5.
        assert_eq!(screen_fate(classify_pty_read(-1, 5)), ScreenFate::Ended);
        assert_eq!(screen_fate(classify_pty_read(-1, 0)), ScreenFate::Ended);
        assert_eq!(child_fate(true), ScreenFate::Ended);
    }

    #[test]
    fn notice_is_visible_text() {
        assert!(ENDED_NOTICE.contains("session ended"));
        assert!(!ENDED_NOTICE.is_empty());
    }
}
