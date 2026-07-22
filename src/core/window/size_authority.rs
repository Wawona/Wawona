//! Host ↔ client size-authority state machine.
//!
//! Permanent anti-ping-pong model for Wawona (all platforms). Exactly one side
//! may change the agreed window size at a time.
//!
//! ## References
//!
//! - **xdg-shell**: `configure(0,0)` = client decides; non-zero = suggestion.
//!   Ack + commit may refuse the suggestion (fixed-size clients).
//! - **OWL** (`owl-compositor/owl`): every buffer commit → host
//!   `setFrameSize` / `setContentSize` to the buffer; map configure is 0×0.
//! - **Smithay**: configure serials + ack; compositor applies size from the
//!   surface after commit, not by fighting the client mid-serial.
//! - **WSLg / RAIL** (reference only): host chrome drives continuous geometry
//!   during drag; settle uses the committed client size — never dual writers.
//! - **waypipe**: remote lag means host must stay authoritative during drag
//!   and only reconcile on match/refuse — same SM.
//!
//! See `.cursor/rules/wawona-host-client-size-sync.mdc`.

/// Who may currently change the agreed host/client window size.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SizeAuthority {
    /// After map with xdg `configure(0,0)`; waiting for the first buffer.
    AwaitingFirstCommit,
    /// Client owns size. Host frame must follow commits (OWL).
    Client,
    /// Host owns size (live edge-drag / inject resize). Client lagging
    /// commits must not yank the host frame (#111).
    Host {
        requested_w: u32,
        requested_h: u32,
        /// Latest configure serial for this request (0 if not yet assigned).
        configure_serial: u32,
        generation: u64,
    },
}

impl Default for SizeAuthority {
    fn default() -> Self {
        Self::AwaitingFirstCommit
    }
}

impl SizeAuthority {
    pub fn is_host(&self) -> bool {
        matches!(self, Self::Host { .. })
    }

    pub fn is_client(&self) -> bool {
        matches!(self, Self::Client | Self::AwaitingFirstCommit)
    }

    pub fn host_requested(&self) -> Option<(u32, u32)> {
        match self {
            Self::Host {
                requested_w,
                requested_h,
                ..
            } => Some((*requested_w, *requested_h)),
            _ => None,
        }
    }
}

/// Outcome of feeding a client commit into the state machine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClientCommitDecision {
    pub authority: SizeAuthority,
    /// Update core `window.width/height` from the committed size.
    pub apply_client_size: bool,
    /// Platform host should resize to the committed size (OWL setFrame).
    pub emit_size_changed: bool,
    /// Present should stretch the last buffer into the host-requested size.
    pub stretch_present_to_host: bool,
    pub reason: &'static str,
}

/// Outcome of a host-driven resize request (AppKit/UIKit/Android edge drag).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostRequestDecision {
    pub authority: SizeAuthority,
    pub reason: &'static str,
}

fn sizes_match(a_w: u32, a_h: u32, b_w: i32, b_h: i32) -> bool {
    b_w > 0
        && b_h > 0
        && (a_w as i32 - b_w).abs() <= 1
        && (a_h as i32 - b_h).abs() <= 1
}

impl SizeAuthority {
    /// Host begins or continues a resize (inject / live drag tick).
    pub fn on_host_resize_request(
        self,
        width: u32,
        height: u32,
        generation: u64,
    ) -> HostRequestDecision {
        let width = width.max(1);
        let height = height.max(1);
        HostRequestDecision {
            authority: SizeAuthority::Host {
                requested_w: width,
                requested_h: height,
                configure_serial: match self {
                    SizeAuthority::Host {
                        configure_serial, ..
                    } => configure_serial,
                    _ => 0,
                },
                generation,
            },
            reason: "host_resize_request",
        }
    }

    /// Record the configure serial issued for the current host request.
    pub fn on_configure_sent(self, serial: u32) -> Self {
        match self {
            SizeAuthority::Host {
                requested_w,
                requested_h,
                generation,
                ..
            } => SizeAuthority::Host {
                requested_w,
                requested_h,
                configure_serial: serial,
                generation,
            },
            other => other,
        }
    }

    /// Client committed a buffer / window-geometry size.
    ///
    /// `xdg_pending_serial == 0` means the client has acked outstanding
    /// configures (no in-flight serial on the xdg_surface).
    /// `current_w/h` are the core window dimensions before this commit.
    /// `interactive_resize` is true while `xdg_toplevel.state.resizing` is set
    /// (host SSD live-drag or CSD resize grab) — lagging commits must not
    /// refuse/yank the host until the settle configure clears Resizing.
    pub fn on_client_commit(
        self,
        committed_w: i32,
        committed_h: i32,
        current_w: i32,
        current_h: i32,
        xdg_pending_serial: u32,
        has_committed_buffer: bool,
        interactive_resize: bool,
    ) -> ClientCommitDecision {
        if committed_w <= 0 || committed_h <= 0 {
            let stretch = self.is_host();
            return ClientCommitDecision {
                authority: self,
                apply_client_size: false,
                emit_size_changed: false,
                stretch_present_to_host: stretch,
                reason: "ignore_non_positive_commit",
            };
        }

        let size_differs = committed_w != current_w || committed_h != current_h;

        match self {
            SizeAuthority::AwaitingFirstCommit => ClientCommitDecision {
                authority: SizeAuthority::Client,
                apply_client_size: true,
                emit_size_changed: true,
                stretch_present_to_host: false,
                reason: "first_commit_client_decides",
            },
            SizeAuthority::Client => ClientCommitDecision {
                authority: SizeAuthority::Client,
                apply_client_size: true,
                // Notify host when size changed, or on the first buffer so a
                // platform placeholder (64×64) is replaced even if core was
                // already updated.
                emit_size_changed: size_differs || !has_committed_buffer,
                stretch_present_to_host: false,
                reason: "client_authoritative_commit",
            },
            SizeAuthority::Host {
                requested_w,
                requested_h,
                configure_serial,
                generation,
            } => {
                if sizes_match(requested_w, requested_h, committed_w, committed_h) {
                    return ClientCommitDecision {
                        authority: SizeAuthority::Client,
                        apply_client_size: true,
                        emit_size_changed: false,
                        stretch_present_to_host: false,
                        reason: "host_request_matched",
                    };
                }
                if xdg_pending_serial != 0 || interactive_resize {
                    // Still waiting for ack of a newer configure, or still in
                    // an interactive resize session — keep host authority; do
                    // not apply lagging buffer / refuse until settle.
                    return ClientCommitDecision {
                        authority: SizeAuthority::Host {
                            requested_w,
                            requested_h,
                            configure_serial,
                            generation,
                        },
                        apply_client_size: false,
                        emit_size_changed: false,
                        stretch_present_to_host: true,
                        reason: if interactive_resize {
                            "host_driving_interactive_resize"
                        } else {
                            "host_driving_pending_configure"
                        },
                    };
                }
                // Client acked the settle configure and still commits a
                // different size = refused the suggestion (weston-flower/smoke).
                // Host must adopt.
                ClientCommitDecision {
                    authority: SizeAuthority::Client,
                    apply_client_size: true,
                    emit_size_changed: true,
                    stretch_present_to_host: false,
                    reason: "client_refused_host_configure",
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_commit_makes_client_authoritative() {
        let d = SizeAuthority::AwaitingFirstCommit.on_client_commit(
            200, 200, 0, 0, 0, false, false,
        );
        assert_eq!(d.authority, SizeAuthority::Client);
        assert!(d.apply_client_size);
        assert!(d.emit_size_changed);
        assert!(!d.stretch_present_to_host);
        assert_eq!(d.reason, "first_commit_client_decides");
    }

    #[test]
    fn first_commit_applies_even_with_pending_initial_configure_serial() {
        // Mirrors surfaces.rs: initial xdg configure is 0×0 with a non-zero
        // serial; weston often commits before that serial is cleared.
        let d = SizeAuthority::AwaitingFirstCommit.on_client_commit(
            1024, 768, 0, 0, /*pending*/ 1, false, false,
        );
        assert_eq!(d.authority, SizeAuthority::Client);
        assert!(d.apply_client_size);
        assert!(d.emit_size_changed);
        assert_eq!(d.reason, "first_commit_client_decides");
    }

    #[test]
    fn host_drag_ignores_lagging_commit_while_pending() {
        let host = SizeAuthority::Client
            .on_host_resize_request(900, 700, 1)
            .authority
            .on_configure_sent(42);
        let d = host.on_client_commit(800, 600, 900, 700, /*pending*/ 42, true, false);
        assert!(d.authority.is_host());
        assert!(!d.apply_client_size);
        assert!(!d.emit_size_changed);
        assert!(d.stretch_present_to_host);
        assert_eq!(d.reason, "host_driving_pending_configure");
    }

    #[test]
    fn host_drag_ignores_mismatch_while_interactive_resize() {
        // Mid-drag: client may ack+commit an older size with no pending serial
        // before the next configure arrives. Must not refuse/yank.
        let host = SizeAuthority::Host {
            requested_w: 900,
            requested_h: 700,
            configure_serial: 7,
            generation: 3,
        };
        let d = host.on_client_commit(800, 600, 900, 700, 0, true, true);
        assert!(d.authority.is_host());
        assert!(!d.apply_client_size);
        assert!(d.stretch_present_to_host);
        assert_eq!(d.reason, "host_driving_interactive_resize");
    }

    #[test]
    fn host_drag_match_returns_client_authority() {
        let host = SizeAuthority::Host {
            requested_w: 900,
            requested_h: 700,
            configure_serial: 7,
            generation: 3,
        };
        let d = host.on_client_commit(900, 700, 900, 700, 0, true, false);
        assert_eq!(d.authority, SizeAuthority::Client);
        assert!(d.apply_client_size);
        assert!(!d.stretch_present_to_host);
        assert_eq!(d.reason, "host_request_matched");
    }

    #[test]
    fn fixed_size_client_refuse_ends_host_authority() {
        // flower/smoke: host asked 1024×768, client keeps 200×200 after ack.
        let host = SizeAuthority::Host {
            requested_w: 1024,
            requested_h: 768,
            configure_serial: 9,
            generation: 1,
        };
        let d = host.on_client_commit(200, 200, 1024, 768, 0, true, false);
        assert_eq!(d.authority, SizeAuthority::Client);
        assert!(d.apply_client_size);
        assert!(d.emit_size_changed);
        assert!(!d.stretch_present_to_host);
        assert_eq!(d.reason, "client_refused_host_configure");
    }

    #[test]
    fn ping_pong_impossible_during_host_drive() {
        // Sequence that previously flashed: host 900 → client 800 → host 900…
        let mut auth = SizeAuthority::Client;
        let mut host_w = 640u32;
        let mut host_h = 480u32;
        for gen in 1..=20 {
            host_w = 640 + gen * 10;
            host_h = 480 + gen * 8;
            auth = auth
                .on_host_resize_request(host_w, host_h, gen as u64)
                .authority
                .on_configure_sent(gen as u32);
            // Lagging commit at previous size with pending serial.
            let lag_w = (host_w as i32) - 10;
            let lag_h = (host_h as i32) - 8;
            let d = auth.clone().on_client_commit(
                lag_w,
                lag_h,
                host_w as i32,
                host_h as i32,
                gen as u32,
                true,
                true,
            );
            assert!(
                !d.apply_client_size,
                "gen {gen}: lagging commit must not apply"
            );
            assert!(d.stretch_present_to_host);
            auth = d.authority;
            // Agreed core size stays at host request (inject path); SM must
            // not hand client a write.
            assert_eq!(auth.host_requested(), Some((host_w, host_h)));
        }
        // Final matching commit settles.
        let d = auth.on_client_commit(
            host_w as i32,
            host_h as i32,
            host_w as i32,
            host_h as i32,
            0,
            true,
            false,
        );
        assert_eq!(d.authority, SizeAuthority::Client);
        assert!(d.apply_client_size);
    }

    #[test]
    fn client_mode_always_follows_buffer() {
        let d = SizeAuthority::Client.on_client_commit(200, 200, 64, 64, 0, true, false);
        assert!(d.apply_client_size);
        assert!(d.emit_size_changed);
        assert_eq!(d.authority, SizeAuthority::Client);
        let d2 = d
            .authority
            .on_client_commit(250, 250, 200, 200, 0, true, false);
        assert!(d2.apply_client_size);
        assert!(d2.emit_size_changed);
        assert!(!d2.stretch_present_to_host);
    }

    #[test]
    fn supersede_host_request_keeps_latest_size() {
        let a = SizeAuthority::Client
            .on_host_resize_request(800, 600, 1)
            .authority
            .on_host_resize_request(900, 700, 2)
            .authority;
        assert_eq!(a.host_requested(), Some((900, 700)));
    }
}
