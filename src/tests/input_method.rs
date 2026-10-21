//! External `zwp_input_method_v2` clients (IBus, Fcitx, WLCS) against the
//! seat that already carries the in-process host IM stand-in.

use crate::tests::harness::TestEnv;
use wayland_client::{
    protocol::{wl_callback, wl_registry, wl_seat},
    Connection, Dispatch, QueueHandle,
};
use wayland_protocols_misc::zwp_input_method_v2::client::{
    zwp_input_method_manager_v2::{self, ZwpInputMethodManagerV2},
    zwp_input_method_v2::{self, ZwpInputMethodV2},
};

#[derive(Default)]
struct ImProbe {
    manager: Option<ZwpInputMethodManagerV2>,
    seat: Option<wl_seat::WlSeat>,
    activates: u32,
    deactivates: u32,
    dones: u32,
    unavailable: u32,
}

impl Dispatch<wl_registry::WlRegistry, ()> for ImProbe {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            match interface.as_str() {
                "zwp_input_method_manager_v2" => {
                    state.manager = Some(registry.bind(name, version.min(1), qh, ()));
                }
                "wl_seat" => {
                    state.seat = Some(registry.bind(name, version.min(1), qh, ()));
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for ImProbe {
    fn event(
        _state: &mut Self,
        _proxy: &wl_seat::WlSeat,
        _event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpInputMethodManagerV2, ()> for ImProbe {
    fn event(
        _state: &mut Self,
        _proxy: &ZwpInputMethodManagerV2,
        _event: zwp_input_method_manager_v2::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwpInputMethodV2, ()> for ImProbe {
    fn event(
        state: &mut Self,
        _proxy: &ZwpInputMethodV2,
        event: zwp_input_method_v2::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            zwp_input_method_v2::Event::Activate => state.activates += 1,
            zwp_input_method_v2::Event::Deactivate => state.deactivates += 1,
            zwp_input_method_v2::Event::Done => state.dones += 1,
            zwp_input_method_v2::Event::Unavailable => state.unavailable += 1,
            _ => {}
        }
    }
}

impl Dispatch<wl_callback::WlCallback, ()> for ImProbe {
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

struct ExternalIm {
    conn: Connection,
    queue: wayland_client::EventQueue<ImProbe>,
    probe: ImProbe,
    im: ZwpInputMethodV2,
}

fn bind_external_im(env: &mut TestEnv) -> ExternalIm {
    let (conn, _server) = env.add_client(7);
    let mut queue = conn.new_event_queue::<ImProbe>();
    let qh = queue.handle();
    let _registry = conn.display().get_registry(&qh, ());
    let mut probe = ImProbe::default();
    env.wait_roundtrip_on(&conn, &mut queue, &mut probe);
    let manager = probe.manager.clone().expect("IM-v2 manager advertised");
    let seat = probe.seat.clone().expect("wl_seat");
    let im = manager.get_input_method(&seat, &qh, ());
    env.wait_roundtrip_on(&conn, &mut queue, &mut probe);
    ExternalIm {
        conn,
        queue,
        probe,
        im,
    }
}

fn roundtrip_im(env: &mut TestEnv, ext: &mut ExternalIm) {
    env.wait_roundtrip_on(&ext.conn, &mut ext.queue, &mut ext.probe);
}

#[test]
fn external_input_method_should_replace_host_stand_in() {
    let mut env = TestEnv::new();
    let mut ext = bind_external_im(&mut env);
    assert_eq!(
        ext.probe.unavailable, 0,
        "an external IM must take the seat from the host stand-in"
    );

    let (mut queue, mut probe) = super::text_input::bind_probe(&mut env);
    super::text_input::create_text_input(&mut env, &mut queue, &mut probe);
    super::text_input::map_and_focus_window(&mut env, &mut queue, &mut probe);
    assert_eq!(probe.entered, 1, "text input enters the focused surface");

    super::text_input::enable_and_commit(&mut env, &mut queue, &mut probe);
    roundtrip_im(&mut env, &mut ext);
    assert_eq!(ext.probe.activates, 1, "external IM must be activated");
    assert!(ext.probe.dones >= 1, "activate must be followed by done");

    ext.im.commit_string("hi".into());
    ext.im.commit(ext.probe.dones);
    roundtrip_im(&mut env, &mut ext);
    env.wait_roundtrip(&mut queue, &mut probe);
    assert_eq!(probe.commit_strings, vec!["hi".to_string()]);
}

#[test]
fn second_external_input_method_should_be_unavailable() {
    let mut env = TestEnv::new();
    let mut first = bind_external_im(&mut env);
    let mut second = bind_external_im(&mut env);
    roundtrip_im(&mut env, &mut first);
    roundtrip_im(&mut env, &mut second);
    assert_eq!(
        first.probe.unavailable, 0,
        "first external IM keeps the seat"
    );
    assert_eq!(
        second.probe.unavailable, 1,
        "a second external IM must be told it is unavailable"
    );
}

#[test]
fn destroyed_external_input_method_should_release_the_seat() {
    let mut env = TestEnv::new();
    let mut ext = bind_external_im(&mut env);
    assert!(env.state.external_input_method_attached());
    ext.im.destroy();
    roundtrip_im(&mut env, &mut ext);
    assert!(
        !env.state.external_input_method_attached(),
        "destroying the owner must release the seat"
    );
    let mut next = bind_external_im(&mut env);
    roundtrip_im(&mut env, &mut next);
    assert_eq!(next.probe.unavailable, 0, "a new IM may take the seat");
    assert!(env.state.external_input_method_attached());
}

#[test]
fn stale_commit_from_external_input_method_should_be_discarded() {
    let mut env = TestEnv::new();
    let mut ext = bind_external_im(&mut env);
    let (mut queue, mut probe) = super::text_input::bind_probe(&mut env);
    super::text_input::create_text_input(&mut env, &mut queue, &mut probe);
    super::text_input::map_and_focus_window(&mut env, &mut queue, &mut probe);
    super::text_input::enable_and_commit(&mut env, &mut queue, &mut probe);
    roundtrip_im(&mut env, &mut ext);

    ext.im.commit_string("stale".into());
    ext.im.commit(ext.probe.dones.wrapping_add(5));
    roundtrip_im(&mut env, &mut ext);
    env.wait_roundtrip(&mut queue, &mut probe);
    assert_eq!(
        probe.done_serials.last().copied(),
        Some(0),
        "a serial the IM never saw must be discarded with done(0)"
    );
}

#[test]
fn seat_input_method_state_should_be_visible_from_other_threads() {
    use smithay::wayland::input_method::InputMethodHandle;
    use smithay::wayland::text_input::TextInputHandle;
    let env = TestEnv::new();
    let seat = env.state.smithay_runtime.seat.as_ref().expect("seat");
    let user_data = seat.user_data();
    let (im_visible, ti_visible) = std::thread::scope(|scope| {
        scope
            .spawn(|| {
                (
                    user_data.get::<InputMethodHandle>().is_some(),
                    user_data.get::<TextInputHandle>().is_some(),
                )
            })
            .join()
            .expect("probe thread")
    });
    assert!(
        im_visible,
        "host IM bound on the start thread must be seen by the dispatch thread"
    );
    assert!(ti_visible, "text-input focus must not split per thread");
}

#[test]
fn destroying_active_text_input_should_deactivate_input_method_and_free_the_seat() {
    let mut env = TestEnv::new();
    let mut ext = bind_external_im(&mut env);
    let (mut queue, mut probe) = super::text_input::bind_probe(&mut env);
    super::text_input::create_text_input(&mut env, &mut queue, &mut probe);
    let survivor = probe.text_input.take().expect("first text input");
    super::text_input::create_text_input(&mut env, &mut queue, &mut probe);
    super::text_input::map_and_focus_window(&mut env, &mut queue, &mut probe);
    super::text_input::enable_and_commit(&mut env, &mut queue, &mut probe);
    roundtrip_im(&mut env, &mut ext);
    assert_eq!(ext.probe.activates, 1);
    let dones_before = ext.probe.dones;
    let deactivates_before = ext.probe.deactivates;

    probe
        .text_input
        .take()
        .expect("active text input")
        .destroy();
    env.wait_roundtrip(&mut queue, &mut probe);
    roundtrip_im(&mut env, &mut ext);
    assert_eq!(
        ext.probe.deactivates,
        deactivates_before + 1,
        "destroying the enabled text input must deactivate the IM"
    );
    assert!(
        ext.probe.dones > dones_before,
        "deactivate must be followed by done"
    );

    probe.text_input = Some(survivor);
    super::text_input::enable_and_commit(&mut env, &mut queue, &mut probe);
    roundtrip_im(&mut env, &mut ext);
    assert_eq!(
        ext.probe.activates, 2,
        "the remaining text input must be able to enable afterwards"
    );
}
