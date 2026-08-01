//! Protocol-matrix integration test: binds a real client to the compositor
//! and asserts the advertised registry globals match the active
//! [`ProtocolProfile`] policy. This is the machine-verifier for advertisement
//! honesty — a protocol must never be advertised unless the compositor can
//! actually service it for that profile.

#![cfg(test)]

use std::collections::HashMap;

use wayland_client::{
    protocol::{wl_callback, wl_registry},
    Connection, Dispatch, QueueHandle,
};

use crate::core::wayland::policy;
use crate::tests::harness::TestEnv;

#[derive(Default)]
struct RegistryProbe {
    /// interface name → advertised version
    globals: HashMap<String, u32>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for RegistryProbe {
    fn event(
        state: &mut Self,
        _proxy: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global { interface, version, .. } = event {
            state.globals.insert(interface, version);
        }
    }
}

impl Dispatch<wl_callback::WlCallback, ()> for RegistryProbe {
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

fn collect_globals(env: &mut TestEnv) -> HashMap<String, u32> {
    let display = env.client.display();
    let mut queue = env.client.new_event_queue::<RegistryProbe>();
    let qh = queue.handle();
    let _registry = display.get_registry(&qh, ());
    let mut probe = RegistryProbe::default();
    env.wait_roundtrip(&mut queue, &mut probe);
    probe.globals
}

#[test]
fn test_protocol_matrix_core_globals_advertised() {
    let mut env = TestEnv::new();
    let globals = collect_globals(&mut env);

    // Core protocols every profile must expose.
    let required = [
        "wl_compositor",
        "wl_subcompositor",
        "wl_shm",
        "wl_seat",
        "wl_output",
        "wl_data_device_manager",
        "xdg_wm_base",
        "wp_viewporter",
        "wp_presentation",
        "zwp_relative_pointer_manager_v1",
        "zwp_pointer_constraints_v1",
        "wp_fractional_scale_manager_v1",
        "wp_cursor_shape_manager_v1",
        "zwp_linux_dmabuf_v1",
        "wp_single_pixel_buffer_manager_v1",
        // Registered in the bug-squash campaign (previously orphaned modules).
        "wp_commit_timing_manager_v1",
        "wp_color_manager_v1",
    ];
    let mut missing = Vec::new();
    for iface in required {
        if !globals.contains_key(iface) {
            missing.push(iface);
        }
    }
    assert!(
        missing.is_empty(),
        "core protocols missing from registry: {:?}\nadvertised: {:?}",
        missing,
        {
            let mut v: Vec<_> = globals.keys().collect();
            v.sort();
            v
        }
    );
}

#[test]
fn test_protocol_matrix_profile_honesty() {
    let mut env = TestEnv::new();
    let profile = env.state.protocol_profile;
    let globals = collect_globals(&mut env);

    // Layer-shell presentation is incomplete: it may only be advertised on
    // desktop/dev profiles, never on store-safe ones.
    let layer_shell = globals.contains_key("zwlr_layer_shell_v1");
    assert_eq!(
        layer_shell,
        policy::allow_desktop_extensions(profile),
        "zwlr_layer_shell_v1 advertisement must follow desktop-extension policy (profile {})",
        profile.as_str()
    );

    // Privileged wlr globals must track the privileged policy.
    for iface in [
        "zwlr_screencopy_manager_v1",
        "zwlr_virtual_pointer_manager_v1",
        "zwp_virtual_keyboard_manager_v1",
        "zwlr_export_dmabuf_manager_v1",
    ] {
        if let Some(&_v) = globals.get(iface) {
            assert!(
                policy::allow_privileged_wlr(profile),
                "{} advertised but profile {} disallows privileged wlr globals",
                iface,
                profile.as_str()
            );
        }
    }
}

/// Generates `docs/protocol-status.md` from the *live* advertised registry so
/// the roadmap can never drift from what the compositor actually exposes. Runs
/// as a normal test (asserting the registry is non-empty); when
/// `WWN_WRITE_PROTOCOL_STATUS=1` it also writes the manifest to disk. Regenerate
/// via `scripts/gen-protocol-status.sh`.
#[test]
fn test_generate_protocol_status_manifest() {
    let mut env = TestEnv::new();
    let profile = env.state.protocol_profile;
    let globals = collect_globals(&mut env);
    assert!(
        !globals.is_empty(),
        "registry advertised no globals; manifest would be empty"
    );

    let mut entries: Vec<(&String, &u32)> = globals.iter().collect();
    entries.sort_by(|a, b| a.0.cmp(b.0));

    let mut md = String::new();
    md.push_str("# Wayland protocol status\n\n");
    md.push_str(
        "<!-- AUTO-GENERATED by `cargo test test_generate_protocol_status_manifest`.\n\
         Do not edit by hand; run `scripts/gen-protocol-status.sh` to refresh. -->\n\n",
    );
    md.push_str(&format!("Active profile at generation: `{}`\n\n", profile.as_str()));
    md.push_str(&format!("Total advertised globals: **{}**\n\n", entries.len()));
    md.push_str("| Interface | Advertised version |\n");
    md.push_str("|-----------|--------------------|\n");
    for (iface, version) in &entries {
        md.push_str(&format!("| `{}` | {} |\n", iface, version));
    }
    md.push('\n');

    if std::env::var("WWN_WRITE_PROTOCOL_STATUS").is_ok() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/docs/protocol-status.md");
        std::fs::write(path, &md).expect("write docs/protocol-status.md");
        eprintln!("wrote {}", path);
    }
}

#[test]
fn test_protocol_matrix_dmabuf_feedback_resolves() {
    use wayland_client::protocol::wl_registry::WlRegistry;
    use wayland_protocols::wp::linux_dmabuf::zv1::client::{
        zwp_linux_dmabuf_feedback_v1, zwp_linux_dmabuf_v1,
    };

    /// High bit set = IOSurface id in low 63 bits (see linux_dmabuf.rs bind).
    const IOSURFACE_MODIFIER: u64 = 0x8000_0000_0000_0000;

    #[derive(Default)]
    struct FeedbackProbe {
        dmabuf: Option<(u32, u32)>, // (name, version)
        feedback_done: bool,
        /// Bare `format` or non-IOSurface `modifier` (e.g. LINEAR) — unrenderable.
        unrenderable_formats_advertised: bool,
    }

    impl Dispatch<WlRegistry, ()> for FeedbackProbe {
        fn event(
            state: &mut Self,
            _proxy: &WlRegistry,
            event: wl_registry::Event,
            _data: &(),
            _conn: &Connection,
            _qh: &QueueHandle<Self>,
        ) {
            if let wl_registry::Event::Global { name, interface, version } = event {
                if interface == "zwp_linux_dmabuf_v1" {
                    state.dmabuf = Some((name, version));
                }
            }
        }
    }

    impl Dispatch<zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()> for FeedbackProbe {
        fn event(
            state: &mut Self,
            _proxy: &zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1,
            event: zwp_linux_dmabuf_v1::Event,
            _data: &(),
            _conn: &Connection,
            _qh: &QueueHandle<Self>,
        ) {
            // IOSurface modifiers are intentional (#86). Reject bare Format and
            // any modifier that is not the IOSurface high-bit convention.
            match event {
                zwp_linux_dmabuf_v1::Event::Format { .. } => {
                    state.unrenderable_formats_advertised = true;
                }
                zwp_linux_dmabuf_v1::Event::Modifier {
                    modifier_hi,
                    modifier_lo,
                    ..
                } => {
                    let modifier = ((modifier_hi as u64) << 32) | (modifier_lo as u64);
                    if modifier != IOSURFACE_MODIFIER {
                        state.unrenderable_formats_advertised = true;
                    }
                }
                _ => {}
            }
        }
    }

    impl Dispatch<zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1, ()> for FeedbackProbe {
        fn event(
            state: &mut Self,
            _proxy: &zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1,
            event: zwp_linux_dmabuf_feedback_v1::Event,
            _data: &(),
            _conn: &Connection,
            _qh: &QueueHandle<Self>,
        ) {
            if matches!(event, zwp_linux_dmabuf_feedback_v1::Event::Done) {
                state.feedback_done = true;
            }
        }
    }

    impl Dispatch<wl_callback::WlCallback, ()> for FeedbackProbe {
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

    let mut env = TestEnv::new();
    let display = env.client.display();
    let mut queue = env.client.new_event_queue::<FeedbackProbe>();
    let qh = queue.handle();
    let registry = display.get_registry(&qh, ());
    let mut probe = FeedbackProbe::default();
    env.wait_roundtrip(&mut queue, &mut probe);

    let (name, version) = probe.dmabuf.expect("zwp_linux_dmabuf_v1 must be advertised");
    assert!(version >= 4, "dmabuf global must be v4+ for feedback");

    let dmabuf: zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1 =
        registry.bind(name, 4, &qh, ());
    let _feedback = dmabuf.get_default_feedback(&qh, ());
    env.wait_roundtrip(&mut queue, &mut probe);

    assert!(
        !probe.unrenderable_formats_advertised,
        "bare Format / non-IOSurface modifiers must not be advertised (unrenderable)"
    );
    assert!(
        probe.feedback_done,
        "dmabuf feedback must resolve with done (clients would stall otherwise)"
    );
}
