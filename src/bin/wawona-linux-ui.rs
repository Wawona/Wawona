#[cfg(feature = "linux-ui")]
mod app {
    use std::cell::{Cell, RefCell};
    use std::collections::{HashMap, HashSet};
    use std::env;
    use std::path::Path;
    use std::process::Child;
    use std::rc::Rc;
    use std::sync::Arc;
    use std::time::Duration;

    use gtk4 as gtk;
    use libadwaita as adw;
    use adw::prelude::*;

    use wawona::ffi::api::WawonaCore;
    use wawona::ffi::api::{build_info, version};
    use wawona::ffi::types::{
        AxisSource, BufferData, DecorationMode, KeyState as WlKeyState, PointerAxis,
        PointerButton, RenderScene, WindowEvent, WindowId,
    };
    use wawona::linux::config::{
        self, LinuxAppConfig, LinuxMachineProfile, LinuxMachineType, LAUNCHER_PRESETS,
    };
    use wawona::linux::runtime::{
        self, ensure_runtime_dir, now_unix_ms, now_unix_s, write_runtime_env, write_runtime_state,
        RuntimeState,
    };
    use wawona::linux::{launcher, service};

    type State = Rc<RefCell<LinuxAppConfig>>;
    type MachineSessions = Rc<RefCell<HashMap<String, Child>>>;

    fn prune_dead_sessions(sessions: &MachineSessions) {
        sessions.borrow_mut().retain(|_, child| matches!(child.try_wait(), Ok(None)));
    }

    /// Returns `(running, pid_if_running)`.
    fn machine_session_status(machine_id: &str, sessions: &MachineSessions) -> (bool, Option<u32>) {
        let mut map = sessions.borrow_mut();
        let Some(child) = map.get_mut(machine_id) else {
            return (false, None);
        };
        match child.try_wait() {
            Ok(Some(_)) => {
                map.remove(machine_id);
                (false, None)
            }
            Ok(None) => (true, Some(child.id())),
            Err(_) => (true, Some(child.id())),
        }
    }

    fn stop_machine(machine_id: &str, sessions: &MachineSessions) {
        if let Some(mut child) = sessions.borrow_mut().remove(machine_id) {
            wawona::wlog!("UI", "Stopping machine id={} pid={}", machine_id, child.id());
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    fn try_launch_from_config(machine_id: &str, state: &State) -> Result<Child, String> {
        let cfg = state.borrow();
        let m = cfg
            .machines
            .iter()
            .find(|x| x.id == machine_id)
            .ok_or_else(|| "machine not found".to_string())?;
        let rt = runtime::read_runtime_state().map_err(|e| format!("{e}"))?;
        launcher::launch(m, &cfg.settings, &rt).map_err(|e| format!("{e}"))
    }

    fn refresh_editor_session_row(
        machine_id: &str,
        sessions: &MachineSessions,
        status: &gtk::Label,
        run_btn: &gtk::Button,
        stop_btn: &gtk::Button,
    ) {
        let (running, pid) = machine_session_status(machine_id, sessions);
        let msg = if running {
            pid.map(|p| format!("Running (pid {p})"))
                .unwrap_or_else(|| "Running".to_string())
        } else {
            "Stopped".to_string()
        };
        status.set_text(&msg);
        run_btn.set_sensitive(!running);
        stop_btn.set_sensitive(running);
    }

    struct CachedBuffer {
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        stride: u32,
    }

    struct ClientWindow {
        gtk_window: gtk::Window,
        drawing_area: gtk::DrawingArea,
        window_id: u64,
        /// `zwp_fullscreen_shell_v1` kiosk surfaces for this connection — drawn into this GtkWindow only.
        companion_window_ids: Vec<u64>,
        /// Allow internal `WindowEvent::Destroyed` teardown to bypass the user close interceptor.
        allow_host_close: Rc<Cell<bool>>,
    }

    struct CompositorState {
        core: Arc<WawonaCore>,
        buffer_cache: HashMap<(u32, u64), CachedBuffer>,
        scene: Option<RenderScene>,
        presented: Vec<(u32, u64)>,
        client_windows: HashMap<u64, ClientWindow>,
        /// Fullscreen-shell window ids waiting for a normal toplevel from the same client.
        pending_fullscreen_shell_by_client: HashMap<u64, Vec<u64>>,
        /// First non–fullscreen-shell Wayland window per client → its Gtk host (for kiosk + xdg pairing).
        primary_host_wayland_window_by_client: HashMap<u64, u64>,
        /// Latest GTK allocation observed for each host window during live resize.
        pending_host_resizes: HashMap<u64, (u32, u32)>,
        /// Tracks whether a resize transaction is currently open for this host window.
        resize_in_flight: HashSet<u64>,
        /// Last size sent to compositor for each host window (dedupe noisy GTK resize signals).
        last_dispatched_host_resizes: HashMap<u64, (u32, u32)>,
    }

    fn dispatch_pending_host_resize(cs: &mut CompositorState, wid: u64) {
        let Some((w, h)) = cs.pending_host_resizes.get(&wid).copied() else {
            return;
        };
        if w == 0 || h == 0 {
            wawona::wlog!(
                "COMPOSITOR",
                "Skipping host resize wid={} invalid size={}x{} (likely transient minimize/unfocus)",
                wid,
                w,
                h
            );
            return;
        }
        if cs
            .last_dispatched_host_resizes
            .get(&wid)
            .copied()
            == Some((w, h))
        {
            return;
        }

        let core = cs.core.clone();
        let companions = cs
            .client_windows
            .get(&wid)
            .map(|cw| cw.companion_window_ids.clone())
            .unwrap_or_default();
        cs.resize_in_flight.insert(wid);
        cs.last_dispatched_host_resizes.insert(wid, (w, h));

        wawona::wlog!(
            "COMPOSITOR",
            "Dispatching coalesced resize wid={} {}x{} companions={} in_flight={}",
            wid,
            w,
            h,
            companions.len(),
            cs.resize_in_flight.contains(&wid)
        );
        for c_wid in companions {
            core.set_window_size_local(WindowId { id: c_wid }, w, h);
        }
        core.resize_window(WindowId { id: wid }, w, h);
    }

    fn wayland_socket_exists() -> bool {
        let display = env::var("WAYLAND_DISPLAY").unwrap_or_default();
        let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_default();
        if display.is_empty() || runtime.is_empty() {
            return false;
        }
        let path = Path::new(&runtime).join(&display);
        path.exists() && !path.extension().is_some_and(|e| e == "lock")
    }

    fn start_embedded_compositor() -> Option<Arc<WawonaCore>> {
        wawona::wlog!("COMPOSITOR", "Starting embedded compositor in GTK process");
        let runtime_dir = match ensure_runtime_dir() {
            Ok(d) => d,
            Err(e) => {
                wawona::wlog!("COMPOSITOR", "Failed to ensure runtime dir: {}", e);
                return None;
            }
        };

        for i in 0..4 {
            let sock = runtime_dir.join(format!("wawona-{i}"));
            let lock = runtime_dir.join(format!("wawona-{i}.lock"));
            if sock.exists() { let _ = std::fs::remove_file(&sock); }
            if lock.exists() { let _ = std::fs::remove_file(&lock); }
        }

        for i in 0..4 {
            let candidate = format!("wawona-{i}");
            let core = WawonaCore::new();
            core.set_force_ssd(true);
            core.set_advertise_fullscreen_shell(true);
            core.set_output_size(1280, 800, 1.0);
            match core.start(Some(candidate.clone())) {
                Ok(_) => {
                    wawona::wlog!("COMPOSITOR", "Embedded compositor started socket={}", candidate);
                    let socket_path = core.get_socket_path();
                    let _ = write_runtime_env(&runtime_dir, &candidate);
                    let state = RuntimeState {
                        healthy: true,
                        pid: std::process::id(),
                        mode: "embedded-ui".to_string(),
                        xdg_runtime_dir: runtime_dir.display().to_string(),
                        wayland_display: candidate.clone(),
                        socket_path,
                        started_at_unix_s: now_unix_s(),
                        dispatch_timeout_ms: 16,
                        tick_interval_ms: 16,
                        last_tick_unix_s: now_unix_s(),
                        last_error: None,
                    };
                    let _ = write_runtime_state(&state);
                    return Some(core);
                }
                Err(e) => {
                    wawona::wlog!("COMPOSITOR", "Failed to bind socket=wawona-{}: {}", i, e);
                }
            }
        }
        None
    }

    fn setup_input_on_drawing_area(
        da: &gtk::DrawingArea,
        core: &Arc<WawonaCore>,
        wid: u64,
    ) {
        let window_id = WindowId { id: wid };

        // Mouse motion
        let motion_ctrl = gtk::EventControllerMotion::new();
        {
            let core = core.clone();
            let wid = window_id;
            motion_ctrl.connect_motion(move |_, x, y| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_pointer_motion(wid, x, y, ts);
                core.inject_pointer_frame(wid);
            });
        }
        {
            let core = core.clone();
            let wid = window_id;
            motion_ctrl.connect_enter(move |_, x, y| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_pointer_enter(wid, x, y, ts);
            });
        }
        {
            let core = core.clone();
            let wid = window_id;
            motion_ctrl.connect_leave(move |_| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_pointer_leave(wid, ts);
            });
        }
        da.add_controller(motion_ctrl);

        // Mouse buttons
        let click_ctrl = gtk::GestureClick::builder()
            .button(0)
            .build();
        {
            let core = core.clone();
            let wid = window_id;
            click_ctrl.connect_pressed(move |gesture, _n, x, y| {
                if let Some(w) = gesture.widget() {
                    let _ = w.grab_focus();
                }
                let btn = match gesture.current_button() {
                    1 => PointerButton::Left,
                    2 => PointerButton::Middle,
                    3 => PointerButton::Right,
                    b => PointerButton::Other(0x110 + b - 1),
                };
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_pointer_motion(wid, x, y, ts);
                core.inject_pointer_button(wid, btn, WlKeyState::Pressed, ts);
                core.inject_pointer_frame(wid);
            });
        }
        {
            let core = core.clone();
            let wid = window_id;
            click_ctrl.connect_released(move |gesture, _n, x, y| {
                let btn = match gesture.current_button() {
                    1 => PointerButton::Left,
                    2 => PointerButton::Middle,
                    3 => PointerButton::Right,
                    b => PointerButton::Other(0x110 + b - 1),
                };
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_pointer_motion(wid, x, y, ts);
                core.inject_pointer_button(wid, btn, WlKeyState::Released, ts);
                core.inject_pointer_frame(wid);
            });
        }
        da.add_controller(click_ctrl);

        // Scroll
        let scroll_ctrl = gtk::EventControllerScroll::new(
            gtk::EventControllerScrollFlags::VERTICAL | gtk::EventControllerScrollFlags::HORIZONTAL,
        );
        {
            let core = core.clone();
            let wid = window_id;
            scroll_ctrl.connect_scroll(move |_, dx, dy| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                if dy.abs() > 0.001 {
                    core.inject_pointer_axis(wid, PointerAxis::Vertical, dy * 15.0, 0, AxisSource::Wheel, ts);
                }
                if dx.abs() > 0.001 {
                    core.inject_pointer_axis(wid, PointerAxis::Horizontal, dx * 15.0, 0, AxisSource::Wheel, ts);
                }
                core.inject_pointer_frame(wid);
                gtk::glib::Propagation::Stop
            });
        }
        da.add_controller(scroll_ctrl);

        // Keyboard
        let key_ctrl = gtk::EventControllerKey::new();
        {
            let core = core.clone();
            key_ctrl.connect_key_pressed(move |_, keyval, keycode, _| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                let _ = keyval;
                core.inject_key(keycode - 8, WlKeyState::Pressed, ts);
                gtk::glib::Propagation::Stop
            });
        }
        {
            let core = core.clone();
            key_ctrl.connect_key_released(move |_, _keyval, keycode, _| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_key(keycode - 8, WlKeyState::Released, ts);
            });
        }
        da.add_controller(key_ctrl);

        da.set_focusable(true);
        da.set_can_focus(true);
    }

    pub fn run() {
        wawona::wlog!("UI", "Wawona Linux starting version={} build={}", version(), build_info());

        if wayland_socket_exists() {
            env::set_var("GDK_BACKEND", "wayland");
            wawona::wlog!("UI", "Wayland socket found; using wayland backend");
        } else {
            env::set_var("GDK_BACKEND", "x11");
            wawona::wlog!("UI", "No wayland socket; using x11 backend");
        }

        if let Err(err) = adw::init() {
            wawona::wlog!("UI", "GTK initialization failed: {}", err);
            eprintln!("Wawona Linux UI cannot start: {err}");
            return;
        }
        wawona::wlog!("UI", "GTK initialized backend={}",
            env::var("GDK_BACKEND").unwrap_or_else(|_| "auto".into()));

        let app = adw::Application::builder()
            .application_id("com.aspauldingcode.wawona.linux")
            .build();
        app.connect_activate(build_ui);
        wawona::wlog!("UI", "Starting GTK application main loop");
        let _ = app.run();
        wawona::wlog!("UI", "GTK application exited");
    }

    fn persist(cfg: &LinuxAppConfig) {
        match config::save(cfg) {
            Ok(_) => wawona::wlog!("UI", "Config saved machines={}", cfg.machines.len()),
            Err(e) => wawona::wlog!("UI", "Config save failed: {}", e),
        }
    }

    fn build_ui(app: &adw::Application) {
        wawona::wlog!("UI", "Building main window");

        let loaded = config::load_or_default().unwrap_or_default();
        wawona::wlog!("UI", "Config loaded machines={} selected={:?}",
            loaded.machines.len(), loaded.selected_machine_id);
        let state: State = Rc::new(RefCell::new(loaded));

        let compositor = start_embedded_compositor();
        let machine_sessions: MachineSessions = Rc::new(RefCell::new(HashMap::new()));
        let comp = Rc::new(RefCell::new(CompositorState {
            core: compositor.clone().unwrap_or_else(|| {
                wawona::wlog!("COMPOSITOR", "No embedded compositor; windows will not render");
                WawonaCore::new()
            }),
            buffer_cache: HashMap::new(),
            scene: None,
            presented: Vec::new(),
            client_windows: HashMap::new(),
            pending_fullscreen_shell_by_client: HashMap::new(),
            primary_host_wayland_window_by_client: HashMap::new(),
            pending_host_resizes: HashMap::new(),
            resize_in_flight: HashSet::new(),
            last_dispatched_host_resizes: HashMap::new(),
        }));

        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("Wawona")
            .default_width(400)
            .default_height(500)
            .width_request(300)
            .height_request(350)
            .build();
        window.set_resizable(true);

        let header = adw::HeaderBar::new();
        let title = gtk::Label::new(Some("Wawona"));
        title.add_css_class("title");
        header.set_title_widget(Some(&title));

        let new_btn = gtk::Button::with_label("New Machine");
        new_btn.add_css_class("suggested-action");
        header.pack_start(&new_btn);

        let settings_btn = gtk::Button::from_icon_name("emblem-system-symbolic");
        settings_btn.set_tooltip_text(Some("Settings"));
        header.pack_end(&settings_btn);

        let machine_list = gtk::ListBox::new();
        machine_list.set_selection_mode(gtk::SelectionMode::Single);
        machine_list.add_css_class("boxed-list");
        machine_list.set_margin_start(12);
        machine_list.set_margin_end(12);
        machine_list.set_margin_top(8);
        machine_list.set_margin_bottom(12);

        let scroll = gtk::ScrolledWindow::new();
        scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
        scroll.set_vexpand(true);
        scroll.set_child(Some(&machine_list));

        let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
        body.append(&scroll);

        window.set_titlebar(Some(&header));
        window.set_child(Some(&body));

        let machine_ids: Rc<RefCell<Vec<String>>> = Rc::new(RefCell::new(Vec::new()));
        rebuild_list(
            &machine_list,
            &state,
            &machine_ids,
            &window,
            machine_sessions.clone(),
        );

        // Compositor tick: dispatch events, pop buffers, poll window events, render
        if compositor.is_some() {
            let comp = comp.clone();
            let app = app.clone();
            gtk::glib::timeout_add_local(Duration::from_millis(16), move || {
                let mut cs = comp.borrow_mut();

                // 1. Frame presentation for previously drawn surfaces
                let presented: Vec<(u32, u64)> = cs.presented.drain(..).collect();
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                for (sid, bid) in &presented {
                    cs.core.notify_frame_presented(
                        wawona::ffi::types::SurfaceId::new(*sid),
                        Some(wawona::ffi::types::BufferId::new(*bid)),
                        ts,
                    );
                }
                if !presented.is_empty() {
                    cs.core.flush_clients();
                }

                // 2. Dispatch Wayland events
                cs.core.dispatch_events(0);

                // 3. Pop pending buffers into cache
                while let Some(wb) = cs.core.pop_pending_buffer() {
                    let sid = wb.surface_id.id;
                    let bid = wb.buffer.id.id;
                    if let BufferData::Shm { pixels, width, height, stride, .. } = wb.buffer.data {
                        cs.buffer_cache.insert((sid, bid), CachedBuffer {
                            pixels, width, height, stride,
                        });
                    }
                }

                cs.core.flush_clients();

                // 4. Poll window events → create/destroy per-client GTK windows
                let events = cs.core.poll_window_events();
                for event in events {
                    match event {
                        WindowEvent::Created { window_id, config } => {
                            let wid = window_id.id;
                            let cid = config.owner_client_internal_id;

                            if config.fullscreen_shell {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "Fullscreen shell wid={} client={} — embedding in primary host (no extra GtkWindow)",
                                    wid,
                                    cid
                                );
                                if let Some(&host_wid) =
                                    cs.primary_host_wayland_window_by_client.get(&cid)
                                {
                                    if let Some(host) = cs.client_windows.get_mut(&host_wid) {
                                        host.companion_window_ids.push(wid);
                                        host.drawing_area.queue_draw();
                                    }
                                } else {
                                    cs.pending_fullscreen_shell_by_client
                                        .entry(cid)
                                        .or_default()
                                        .push(wid);
                                }
                                continue;
                            }

                            let is_csd = config.decoration_mode == DecorationMode::ClientSide;
                            wawona::wlog!("COMPOSITOR", "Creating host window wid={} title='{}' decoration={:?} client={}",
                                wid, config.title, config.decoration_mode, cid);

                            let client_win = gtk::Window::builder()
                                .title(&config.title)
                                .default_width(config.width as i32)
                                .default_height(config.height as i32)
                                .resizable(true)
                                .decorated(!is_csd)
                                .application(&app)
                                .build();

                            let da = gtk::DrawingArea::new();
                            da.set_hexpand(true);
                            da.set_vexpand(true);
                            client_win.set_child(Some(&da));

                            let allow_host_close = Rc::new(Cell::new(false));
                            {
                                let core_close = cs.core.clone();
                                let win_id_close = wid;
                                let allow_host_close_gate = allow_host_close.clone();
                                let close_deferred = Rc::new(Cell::new(false));
                                let close_deferred_gate = close_deferred.clone();
                                client_win.connect_close_request(move |_win| {
                                    if allow_host_close_gate.get() {
                                        return gtk::glib::Propagation::Proceed;
                                    }

                                    let w = WindowId { id: win_id_close };
                                    if close_deferred_gate.get() {
                                        wawona::wlog!(
                                            "COMPOSITOR",
                                            "Host window close (×) wid={} second request → force_destroy_host_window",
                                            win_id_close
                                        );
                                        close_deferred_gate.set(false);
                                        let _ = core_close.force_destroy_host_window(w);
                                        return gtk::glib::Propagation::Stop;
                                    }

                                    wawona::wlog!(
                                        "COMPOSITOR",
                                        "Host window close (×) wid={} → xdg_toplevel.close",
                                        win_id_close
                                    );
                                    if !core_close.request_window_close(w) {
                                        wawona::wlog!(
                                            "COMPOSITOR",
                                            "No xdg toplevel for wid={}; force_destroy_host_window",
                                            win_id_close
                                        );
                                        let _ = core_close.force_destroy_host_window(w);
                                        return gtk::glib::Propagation::Stop;
                                    }

                                    close_deferred_gate.set(true);
                                    let core_timeout = core_close.clone();
                                    let allow_host_close_timeout = allow_host_close_gate.clone();
                                    let close_deferred_timeout = close_deferred_gate.clone();
                                    gtk::glib::timeout_add_local_once(
                                        Duration::from_millis(1500),
                                        move || {
                                            if close_deferred_timeout.get()
                                                && !allow_host_close_timeout.get()
                                            {
                                                wawona::wlog!(
                                                    "COMPOSITOR",
                                                    "Host close timeout wid={} → force_destroy_host_window",
                                                    win_id_close
                                                );
                                                close_deferred_timeout.set(false);
                                                let _ = core_timeout
                                                    .force_destroy_host_window(w);
                                            }
                                        },
                                    );
                                    gtk::glib::Propagation::Stop
                                });
                            }

                            setup_input_on_drawing_area(&da, &cs.core, wid);

                            // GTK keyboard focus ↔ wl_keyboard.enter/leave (see macOS becomeKey/resignKey)
                            {
                                let core_f = cs.core.clone();
                                let win_id_k = WindowId { id: wid };
                                let focus_ctrl = gtk::EventControllerFocus::new();
                                {
                                    let core = core_f.clone();
                                    let w = win_id_k;
                                    focus_ctrl.connect_enter(move |_c| {
                                        wawona::wlog!(
                                            "UI",
                                            "Keyboard focus gained (GTK) → Wayland wid={}",
                                            w.id
                                        );
                                        core.apply_keyboard_focus_for_window(w);
                                    });
                                }
                                {
                                    let core = core_f.clone();
                                    let w = win_id_k;
                                    focus_ctrl.connect_leave(move |_c| {
                                        wawona::wlog!(
                                            "UI",
                                            "Keyboard focus lost (GTK) → leave wid={}",
                                            w.id
                                        );
                                        core.inject_keyboard_leave(w);
                                    });
                                }
                                da.add_controller(focus_ctrl);
                            }

                            {
                                let da_active = da.clone();
                                client_win.connect_is_active_notify(move |win| {
                                    if win.is_active() {
                                        let _ = da_active.grab_focus();
                                    }
                                });
                            }

                            // Per-window resize → host + any fullscreen-shell companions (nested compositor output)
                            {
                                let comp_r = comp.clone();
                                da.connect_resize(move |_da, w, h| {
                                    let w = w as u32;
                                    let h = h as u32;
                                    wawona::wlog!("COMPOSITOR", "Window {} resize {}x{}", wid, w, h);
                                    let mut cs = comp_r.borrow_mut();
                                    cs.pending_host_resizes.insert(wid, (w, h));
                                    dispatch_pending_host_resize(&mut cs, wid);
                                });
                            }

                            let companion_window_ids = cs
                                .pending_fullscreen_shell_by_client
                                .remove(&cid)
                                .unwrap_or_default();
                            cs.primary_host_wayland_window_by_client
                                .entry(cid)
                                .or_insert(wid);

                            // Draw func
                            let comp_for_draw = comp.clone();
                            let wid_for_draw = wid;
                            da.set_draw_func(move |_da, cr, width, height| {
                                cr.set_source_rgb(0.12, 0.12, 0.14);
                                cr.rectangle(0.0, 0.0, width as f64, height as f64);
                                let _ = cr.fill();

                                let cs = comp_for_draw.borrow();
                                let scene = match cs.scene.as_ref() {
                                    Some(s) => s,
                                    None => return,
                                };

                                let draw_wids: Vec<u64> = {
                                    let c = comp_for_draw.borrow();
                                    if let Some(cw) = c.client_windows.get(&wid_for_draw) {
                                        let mut v = cw.companion_window_ids.clone();
                                        v.push(cw.window_id);
                                        v
                                    } else {
                                        vec![wid_for_draw]
                                    }
                                };

                                let mut to_present = Vec::new();
                                for node in &scene.nodes {
                                    if !draw_wids.contains(&node.window_id.id) {
                                        continue;
                                    }
                                    let sid = node.surface_id.id;
                                    let bid = node.texture.handle;
                                    if bid == 0 { continue; }

                                    let Some(buf) = cs.buffer_cache.get(&(sid, bid)) else { continue; };

                                    let surf = cairo::ImageSurface::create_for_data(
                                        buf.pixels.clone(),
                                        cairo::Format::ARgb32,
                                        buf.width as i32,
                                        buf.height as i32,
                                        buf.stride as i32,
                                    );
                                    let Ok(surf) = surf else { continue; };

                                    let _ = cr.save();
                                    let anchor_x = node.anchor_output_x as f64;
                                    let anchor_y = node.anchor_output_y as f64;
                                    let local_x = node.x as f64 - anchor_x;
                                    let local_y = node.y as f64 - anchor_y;
                                    cr.translate(local_x, local_y);

                                    let cr_x = node.content_rect.x as f64;
                                    let cr_y = node.content_rect.y as f64;
                                    let cr_w = node.content_rect.w as f64;
                                    let cr_h = node.content_rect.h as f64;
                                    let has_crop = cr_w > 0.0 && cr_h > 0.0
                                        && (cr_x > 0.001 || cr_y > 0.001
                                            || (cr_w - 1.0).abs() > 0.001
                                            || (cr_h - 1.0).abs() > 0.001);

                                    let src_x = cr_x * buf.width as f64;
                                    let src_y = cr_y * buf.height as f64;
                                    let src_w = cr_w * buf.width as f64;
                                    let src_h = cr_h * buf.height as f64;

                                    if has_crop {
                                        let sx = node.width as f64 / src_w;
                                        let sy = node.height as f64 / src_h;
                                        cr.scale(sx, sy);
                                        let _ = cr.set_source_surface(&surf, -src_x, -src_y);
                                        cr.rectangle(0.0, 0.0, src_w, src_h);
                                        let _ = cr.clip();
                                    } else {
                                        let sx = node.width as f64 / buf.width as f64;
                                        let sy = node.height as f64 / buf.height as f64;
                                        if (sx - 1.0).abs() > 0.001 || (sy - 1.0).abs() > 0.001 {
                                            cr.scale(sx, sy);
                                        }
                                        let _ = cr.set_source_surface(&surf, 0.0, 0.0);
                                    }

                                    if node.opacity < 1.0 {
                                        let _ = cr.paint_with_alpha(node.opacity as f64);
                                    } else {
                                        let _ = cr.paint();
                                    }
                                    let _ = cr.restore();

                                    to_present.push((sid, bid));
                                }

                                drop(cs);
                                let mut cs = comp_for_draw.borrow_mut();
                                for pair in to_present {
                                    if !cs.presented.contains(&pair) {
                                        cs.presented.push(pair);
                                    }
                                }
                            });

                            client_win.present();
                            cs.client_windows.insert(wid, ClientWindow {
                                gtk_window: client_win,
                                drawing_area: da,
                                window_id: wid,
                                companion_window_ids,
                                allow_host_close,
                            });
                        }
                        WindowEvent::Destroyed { window_id } => {
                            let wid = window_id.id;
                            cs.pending_host_resizes.remove(&wid);
                            cs.resize_in_flight.remove(&wid);
                            cs.last_dispatched_host_resizes.remove(&wid);
                            for cw in cs.client_windows.values_mut() {
                                cw.companion_window_ids.retain(|x| *x != wid);
                            }
                            cs.pending_fullscreen_shell_by_client
                                .values_mut()
                                .for_each(|v| v.retain(|x| *x != wid));
                            cs.pending_fullscreen_shell_by_client
                                .retain(|_, v| !v.is_empty());
                            cs.primary_host_wayland_window_by_client
                                .retain(|_, h| *h != wid);

                            if let Some(cw) = cs.client_windows.remove(&wid) {
                                wawona::wlog!("COMPOSITOR", "Destroying host GtkWindow wid={}", wid);
                                cw.allow_host_close.set(true);
                                cw.gtk_window.close();
                            } else {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "Wayland window wid={} destroyed (embedded or no Gtk host)",
                                    wid
                                );
                                for cw in cs.client_windows.values() {
                                    cw.drawing_area.queue_draw();
                                }
                            }
                        }
                        WindowEvent::TitleChanged { window_id, title } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                cw.gtk_window.set_title(Some(&title));
                            }
                        }
                        WindowEvent::SizeChanged { window_id, width, height, .. } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                cw.gtk_window.set_default_size(width as i32, height as i32);
                            }
                            if cs.resize_in_flight.remove(&window_id.id) {
                                if cs.pending_host_resizes.get(&window_id.id).copied()
                                    == Some((width, height))
                                {
                                    cs.pending_host_resizes.remove(&window_id.id);
                                }
                                dispatch_pending_host_resize(&mut cs, window_id.id);
                            }
                        }
                        WindowEvent::DecorationModeChanged { window_id, mode } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                let is_csd = mode == DecorationMode::ClientSide;
                                wawona::wlog!("COMPOSITOR", "Window {} decoration changed to {:?}", window_id.id, mode);
                                cw.gtk_window.set_decorated(!is_csd);
                            }
                        }
                        _ => {}
                    }
                }

                // 5. Get render scene and trigger redraws
                let scene = cs.core.get_render_scene();
                let needs_redraw = scene.needs_redraw;
                cs.scene = Some(scene);

                if needs_redraw {
                    for cw in cs.client_windows.values() {
                        cw.drawing_area.queue_draw();
                    }
                }

                drop(cs);
                gtk::glib::ControlFlow::Continue
            });
            wawona::wlog!("COMPOSITOR", "Compositor tick started at 60Hz");
        }

        {
            let state = state.clone();
            let window = window.clone();
            let machine_list = machine_list.clone();
            let machine_ids = machine_ids.clone();
            let sessions_n = machine_sessions.clone();
            new_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "New Machine button pressed");
                show_editor_dialog(
                    &window,
                    &state,
                    None,
                    &machine_list,
                    &machine_ids,
                    sessions_n.clone(),
                );
            });
        }

        {
            let state = state.clone();
            let window = window.clone();
            settings_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Settings button pressed");
                show_settings_dialog(&window, &state);
            });
        }

        wawona::wlog!("UI", "Main window presented");
        window.present();
    }

    // ── Machine list ─────────────────────────────────────────────────────

    fn rebuild_list(
        list: &gtk::ListBox,
        state: &State,
        ids: &Rc<RefCell<Vec<String>>>,
        parent: &gtk::ApplicationWindow,
        sessions: MachineSessions,
    ) {
        while let Some(child) = list.first_child() {
            list.remove(&child);
        }

        prune_dead_sessions(&sessions);

        let cfg = state.borrow();
        let mut id_vec = Vec::with_capacity(cfg.machines.len());

        if cfg.machines.is_empty() {
            let placeholder = adw::ActionRow::new();
            placeholder.set_title("No machines configured");
            placeholder.set_subtitle("Press \"New Machine\" to create one.");
            list.append(&placeholder);
        }

        for machine in &cfg.machines {
            let row = adw::ActionRow::new();
            row.set_title(&machine.name);
            row.set_subtitle(&format!(
                "{} — {}",
                machine.machine_type.user_facing_name(),
                machine.summary()
            ));
            row.set_activatable(true);

            let action_box = gtk::Box::new(gtk::Orientation::Horizontal, 4);

            let edit_btn = gtk::Button::from_icon_name("document-edit-symbolic");
            edit_btn.set_tooltip_text(Some("Edit"));
            edit_btn.set_valign(gtk::Align::Center);
            edit_btn.add_css_class("flat");

            let run_btn = gtk::Button::from_icon_name("media-playback-start-symbolic");
            run_btn.set_tooltip_text(Some("Run"));
            run_btn.set_valign(gtk::Align::Center);

            let stop_btn = gtk::Button::from_icon_name("media-playback-stop-symbolic");
            stop_btn.set_tooltip_text(Some("Stop"));
            stop_btn.set_valign(gtk::Align::Center);

            let (running, _) = machine_session_status(&machine.id, &sessions);
            run_btn.set_sensitive(!running);
            stop_btn.set_sensitive(running);

            let delete_btn = gtk::Button::from_icon_name("user-trash-symbolic");
            delete_btn.set_tooltip_text(Some("Delete"));
            delete_btn.set_valign(gtk::Align::Center);
            delete_btn.add_css_class("flat");

            action_box.append(&edit_btn);
            action_box.append(&run_btn);
            action_box.append(&stop_btn);
            action_box.append(&delete_btn);
            row.add_suffix(&action_box);

            let machine_id = machine.id.clone();
            {
                let state = state.clone();
                let list = list.clone();
                let ids = ids.clone();
                let parent = parent.clone();
                let sessions_e = sessions.clone();
                edit_btn.connect_clicked(move |_| {
                    let profile = state.borrow().machines.iter().find(|m| m.id == machine_id).cloned();
                    if let Some(profile) = profile {
                        wawona::wlog!("UI", "Edit pressed for machine name='{}' id={}", profile.name, profile.id);
                        show_editor_dialog(
                            &parent,
                            &state,
                            Some(profile),
                            &list,
                            &ids,
                            sessions_e.clone(),
                        );
                    }
                });
            }

            let machine_id = machine.id.clone();
            let machine_name = machine.name.clone();
            {
                let state = state.clone();
                let list = list.clone();
                let ids = ids.clone();
                let parent = parent.clone();
                let machine_name = machine_name.clone();
                let sessions_r = sessions.clone();
                run_btn.connect_clicked(move |btn| {
                    wawona::wlog!(
                        "UI",
                        "Run pressed for machine name='{}' id={}",
                        machine_name,
                        machine_id
                    );
                    match try_launch_from_config(&machine_id, &state) {
                        Ok(child) => {
                            wawona::wlog!("UI", "Launched '{}' pid={}", machine_name, child.id());
                            sessions_r.borrow_mut().insert(machine_id.clone(), child);
                            rebuild_list(&list, &state, &ids, &parent, sessions_r.clone());
                        }
                        Err(e) => {
                            wawona::wlog!("UI", "Launch failed for '{}': {}", machine_name, e);
                            if let Some(root) = btn.root() {
                                if let Ok(w) = root.downcast::<gtk::Window>() {
                                    let msg = if e.contains("runtime") || e.contains("XDG") {
                                        "Wawona compositor is not running. Launch the app (embedded compositor) or start the host from Settings → Diagnostics."
                                    } else {
                                        e.as_str()
                                    };
                                    let dlg = gtk::MessageDialog::new(
                                        Some(&w),
                                        gtk::DialogFlags::MODAL,
                                        gtk::MessageType::Warning,
                                        gtk::ButtonsType::Ok,
                                        msg,
                                    );
                                    dlg.connect_response(|d, _| d.close());
                                    dlg.present();
                                }
                            }
                        }
                    }
                });
            }

            let machine_id = machine.id.clone();
            let machine_name_stop = machine.name.clone();
            {
                let state = state.clone();
                let list = list.clone();
                let ids = ids.clone();
                let parent = parent.clone();
                let sessions_s = sessions.clone();
                stop_btn.connect_clicked(move |_| {
                    wawona::wlog!(
                        "UI",
                        "Stop pressed for machine name='{}' id={}",
                        machine_name_stop,
                        machine_id
                    );
                    stop_machine(&machine_id, &sessions_s);
                    rebuild_list(&list, &state, &ids, &parent, sessions_s.clone());
                });
            }

            let machine_id = machine.id.clone();
            let machine_name_del = machine.name.clone();
            {
                let state = state.clone();
                let list = list.clone();
                let ids = ids.clone();
                let parent = parent.clone();
                let sessions_d = sessions.clone();
                delete_btn.connect_clicked(move |_| {
                    wawona::wlog!("UI", "Delete pressed for machine name='{}' id={}", machine_name_del, machine_id);
                    let mut cfg = state.borrow_mut();
                    cfg.machines.retain(|m| m.id != machine_id);
                    if cfg.selected_machine_id.as_deref() == Some(&machine_id) {
                        cfg.selected_machine_id = cfg.machines.first().map(|m| m.id.clone());
                    }
                    persist(&cfg);
                    drop(cfg);
                    rebuild_list(&list, &state, &ids, &parent, sessions_d.clone());
                });
            }

            list.append(&row);
            id_vec.push(machine.id.clone());
        }

        drop(cfg);
        *ids.borrow_mut() = id_vec;
    }

    // ── Machine editor dialog ────────────────────────────────────────────

    fn show_editor_dialog(
        parent: &gtk::ApplicationWindow,
        state: &State,
        existing: Option<LinuxMachineProfile>,
        machine_list: &gtk::ListBox,
        machine_ids: &Rc<RefCell<Vec<String>>>,
        sessions: MachineSessions,
    ) {
        let is_new = existing.is_none();
        let profile = existing.unwrap_or_else(|| LinuxMachineProfile::new(""));
        wawona::wlog!("UI", "Editor dialog opened is_new={} id={}", is_new, profile.id);

        let dialog = gtk::Window::builder()
            .transient_for(parent).modal(true)
            .default_width(480).default_height(560).resizable(true)
            .title(if is_new { "New Machine" } else { "Edit Machine" })
            .build();

        let dialog_header = adw::HeaderBar::new();
        let cancel_btn = gtk::Button::with_label("Cancel");
        let save_btn = gtk::Button::with_label("Save");
        save_btn.add_css_class("suggested-action");
        dialog_header.pack_start(&cancel_btn);
        dialog_header.pack_end(&save_btn);
        let dialog_title = gtk::Label::new(Some(if is_new { "New Machine" } else { &profile.name }));
        dialog_title.add_css_class("title");
        dialog_header.set_title_widget(Some(&dialog_title));

        let profile_group = adw::PreferencesGroup::new();
        profile_group.set_title("Profile");
        let name_entry = gtk::Entry::builder().placeholder_text("Name").text(&profile.name).build();
        let name_row = adw::ActionRow::new();
        name_row.set_title("Name"); name_row.add_suffix(&name_entry); name_row.set_activatable(false);
        profile_group.add(&name_row);

        let type_combo = gtk::ComboBoxText::new();
        type_combo.append(Some("native"), "Native");
        type_combo.append(Some("ssh_waypipe"), "SSH + Waypipe");
        type_combo.append(Some("ssh_terminal"), "SSH Terminal");
        type_combo.set_active_id(Some(match profile.machine_type {
            LinuxMachineType::Native => "native",
            LinuxMachineType::SshWaypipe => "ssh_waypipe",
            LinuxMachineType::SshTerminal => "ssh_terminal",
        }));
        let type_row = adw::ActionRow::new();
        type_row.set_title("Type"); type_row.add_suffix(&type_combo); type_row.set_activatable(false);
        profile_group.add(&type_row);

        let launcher_group = adw::PreferencesGroup::new();
        launcher_group.set_title("Wayland Client");
        launcher_group.set_description(Some("Connects to the compositor via local Wayland socket."));
        let selected_launcher = Rc::new(RefCell::new(profile.selected_launcher.clone()));
        let mut first_radio: Option<gtk::CheckButton> = None;
        for &(name, display_name) in LAUNCHER_PRESETS {
            let row = adw::ActionRow::new();
            row.set_title(display_name); row.set_subtitle(name); row.set_activatable(false);
            let radio = gtk::CheckButton::new();
            if let Some(ref first) = first_radio { radio.set_group(Some(first)); } else { first_radio = Some(radio.clone()); }
            if profile.selected_launcher == name { radio.set_active(true); }
            let selected = selected_launcher.clone();
            let ln = name.to_string();
            radio.connect_toggled(move |btn| { if btn.is_active() { *selected.borrow_mut() = ln.clone(); } });
            row.add_prefix(&radio);
            launcher_group.add(&row);
        }

        let remote_group = adw::PreferencesGroup::new();
        remote_group.set_title("Remote Host");
        let host_entry = gtk::Entry::builder().placeholder_text("host.example.com").text(&profile.ssh_host).build();
        let user_entry = gtk::Entry::builder().placeholder_text("username").text(&profile.ssh_user).build();
        let password_entry = gtk::PasswordEntry::builder().show_peek_icon(true).build();
        password_entry.set_text(&profile.ssh_password);
        let port_entry = gtk::Entry::builder().placeholder_text("22").text(&profile.ssh_port.to_string()).build();
        for (t, w) in [("Host", host_entry.clone().upcast::<gtk::Widget>()), ("Username", user_entry.clone().upcast::<gtk::Widget>()), ("Password", password_entry.clone().upcast::<gtk::Widget>()), ("Port", port_entry.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); remote_group.add(&row);
        }

        let command_group = adw::PreferencesGroup::new();
        let cmd_entry = gtk::Entry::builder().text(&profile.remote_command).build();
        let cmd_row = adw::ActionRow::new(); cmd_row.set_activatable(false); cmd_row.add_suffix(&cmd_entry); command_group.add(&cmd_row);

        let update_sections = {
            let lg = launcher_group.clone(); let rg = remote_group.clone(); let cg = command_group.clone();
            let cr = cmd_row.clone(); let ce = cmd_entry.clone();
            move |type_id: &str| {
                lg.set_visible(type_id == "native");
                let is_ssh = type_id == "ssh_waypipe" || type_id == "ssh_terminal";
                rg.set_visible(is_ssh);
                cg.set_visible(type_id == "native" || is_ssh);
                if type_id == "native" {
                    cg.set_title("Custom Command");
                    cg.set_description(Some("Optional shell command. When set, this overrides the selected Wayland client preset."));
                    cr.set_title("Command");
                    ce.set_placeholder_text(Some("e.g. foot --server"));
                } else if type_id == "ssh_waypipe" {
                    cg.set_title("Waypipe Remote Command");
                    cg.set_description(None);
                    cr.set_title("Command");
                    ce.set_placeholder_text(Some("e.g. weston-terminal"));
                } else if type_id == "ssh_terminal" {
                    cg.set_title("SSH Command");
                    cg.set_description(None);
                    cr.set_title("Command");
                    ce.set_placeholder_text(Some("e.g. bash -l"));
                }
            }
        };
        let initial_type = type_combo.active_id().map(|s| s.to_string()).unwrap_or_else(|| "native".into());
        update_sections(&initial_type);
        { let u = update_sections.clone(); type_combo.connect_changed(move |c| { let id = c.active_id().map(|s| s.to_string()).unwrap_or_else(|| "native".into()); u(&id); }); }

        let session_group = adw::PreferencesGroup::new();
        session_group.set_title("Session");
        session_group.set_description(Some("Run or stop the Wayland client / SSH session for this machine."));
        let status_lbl = gtk::Label::new(None);
        status_lbl.set_xalign(1.0);
        let status_row = adw::ActionRow::new();
        status_row.set_title("Status");
        status_row.add_suffix(&status_lbl);
        status_row.set_activatable(false);
        session_group.add(&status_row);
        let editor_run_btn = gtk::Button::from_icon_name("media-playback-start-symbolic");
        editor_run_btn.set_tooltip_text(Some("Run"));
        let editor_stop_btn = gtk::Button::from_icon_name("media-playback-stop-symbolic");
        editor_stop_btn.set_tooltip_text(Some("Stop"));
        let session_actions = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        session_actions.append(&editor_run_btn);
        session_actions.append(&editor_stop_btn);
        let actions_row = adw::ActionRow::new();
        actions_row.set_title("Control");
        actions_row.add_suffix(&session_actions);
        actions_row.set_activatable(false);
        session_group.add(&actions_row);

        let form_page = adw::PreferencesPage::new();
        form_page.add(&profile_group); form_page.add(&launcher_group); form_page.add(&remote_group); form_page.add(&command_group);
        form_page.add(&session_group);
        let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content.append(&dialog_header); content.append(&form_page);
        dialog.set_child(Some(&content));

        let editor_mid = profile.id.clone();
        if is_new {
            session_group.set_sensitive(false);
            session_group.set_description(Some(
                "Save the machine first, then reopen Edit to run or stop this profile.",
            ));
            status_lbl.set_text("Not saved yet");
            editor_run_btn.set_sensitive(false);
            editor_stop_btn.set_sensitive(false);
        } else {
            refresh_editor_session_row(
                &editor_mid,
                &sessions,
                &status_lbl,
                &editor_run_btn,
                &editor_stop_btn,
            );
        }

        {
            let st = state.clone();
            let sessions_er = sessions.clone();
            let status_lbl = status_lbl.clone();
            let editor_run_btn_for_refresh = editor_run_btn.clone();
            let editor_stop_btn_for_refresh = editor_stop_btn.clone();
            let mid = editor_mid.clone();
            editor_run_btn.clone().connect_clicked(move |btn| {
                match try_launch_from_config(&mid, &st) {
                    Ok(child) => {
                        wawona::wlog!("UI", "Editor Run ok id={} pid={}", mid, child.id());
                        sessions_er.borrow_mut().insert(mid.clone(), child);
                        refresh_editor_session_row(
                            &mid,
                            &sessions_er,
                            &status_lbl,
                            &editor_run_btn_for_refresh,
                            &editor_stop_btn_for_refresh,
                        );
                    }
                    Err(e) => {
                        wawona::wlog!("UI", "Editor Run failed: {}", e);
                        if let Some(root) = btn.root() {
                            if let Ok(w) = root.downcast::<gtk::Window>() {
                                let dlg_err = gtk::MessageDialog::new(
                                    Some(&w),
                                    gtk::DialogFlags::MODAL,
                                    gtk::MessageType::Warning,
                                    gtk::ButtonsType::Ok,
                                    e.as_str(),
                                );
                                dlg_err.connect_response(|d, _| d.close());
                                dlg_err.present();
                            }
                        }
                    }
                }
            });
        }

        {
            let st = state.clone();
            let sessions_es = sessions.clone();
            let status_lbl = status_lbl.clone();
            let editor_run_btn_for_refresh = editor_run_btn.clone();
            let editor_stop_btn_for_refresh = editor_stop_btn.clone();
            let mid = editor_mid.clone();
            let ml = machine_list.clone();
            let mi = machine_ids.clone();
            let p = parent.clone();
            editor_stop_btn.clone().connect_clicked(move |_| {
                stop_machine(&mid, &sessions_es);
                refresh_editor_session_row(
                    &mid,
                    &sessions_es,
                    &status_lbl,
                    &editor_run_btn_for_refresh,
                    &editor_stop_btn_for_refresh,
                );
                rebuild_list(&ml, &st, &mi, &p, sessions_es.clone());
            });
        }

        { let d = dialog.clone(); cancel_btn.connect_clicked(move |_| { d.close(); }); }

        {
            let d = dialog.clone(); let st = state.clone(); let pid = profile.id.clone();
            let ml = machine_list.clone(); let mi = machine_ids.clone(); let p = parent.clone();
            let sessions_sv = sessions.clone();
            save_btn.connect_clicked(move |_| {
                let tid = type_combo.active_id().map(|s| s.to_string()).unwrap_or_else(|| "native".into());
                let nm = name_entry.text().to_string();
                let nm = if nm.trim().is_empty() { "Unnamed".to_string() } else { nm };
                let mt = match tid.as_str() { "ssh_waypipe" => LinuxMachineType::SshWaypipe, "ssh_terminal" => LinuxMachineType::SshTerminal, _ => LinuxMachineType::Native };
                let updated = LinuxMachineProfile { id: pid.clone(), name: nm.clone(), machine_type: mt,
                    selected_launcher: selected_launcher.borrow().clone(), ssh_host: host_entry.text().to_string(),
                    ssh_user: user_entry.text().to_string(), ssh_port: port_entry.text().parse::<u16>().unwrap_or(22),
                    ssh_password: password_entry.text().to_string(), remote_command: cmd_entry.text().to_string() };
                let mut cfg = st.borrow_mut();
                if let Some(existing) = cfg.machines.iter_mut().find(|m| m.id == pid) { *existing = updated; } else { cfg.machines.push(updated); }
                cfg.selected_machine_id = Some(pid.clone());
                persist(&cfg);
                wawona::wlog!("UI", "Machine saved name='{}' id={} type={} launcher={}", nm, pid, tid, selected_launcher.borrow());
                drop(cfg);
                rebuild_list(&ml, &st, &mi, &p, sessions_sv.clone());
                d.close();
            });
        }
        dialog.present();
    }

    // ── Settings dialog (1:1 with macOS SettingsRootView) ──────────────

    fn show_settings_dialog(parent: &gtk::ApplicationWindow, state: &State) {
        wawona::wlog!("UI", "Settings dialog opened");
        let dialog = gtk::Window::builder().transient_for(parent).modal(true)
            .default_width(720).default_height(560).resizable(true).title("Settings").build();

        let header = adw::HeaderBar::new();
        let done_btn = gtk::Button::with_label("Done");
        done_btn.add_css_class("suggested-action");
        header.pack_end(&done_btn);

        let sidebar = gtk::ListBox::new();
        sidebar.set_selection_mode(gtk::SelectionMode::Single);
        sidebar.add_css_class("navigation-sidebar");
        sidebar.set_width_request(180);

        let sections = [
            "Display", "Input", "Graphics", "SSH and Waypipe",
            "Advanced", "Launch Agent", "Diagnostics", "About",
        ];
        for name in &sections {
            let row = gtk::Label::new(Some(name));
            row.set_xalign(0.0);
            row.set_margin_start(8);
            row.set_margin_end(8);
            row.set_margin_top(4);
            row.set_margin_bottom(4);
            sidebar.append(&row);
        }

        let stack = gtk::Stack::new();
        stack.set_hexpand(true);
        stack.set_vexpand(true);

        let cfg = state.borrow();

        // Display
        let display_page = adw::PreferencesPage::new();
        let display_group = adw::PreferencesGroup::new();
        display_group.set_title("Display");
        let auto_scale = gtk::Switch::new();
        auto_scale.set_valign(gtk::Align::Center);
        auto_scale.set_active(cfg.settings.auto_scale);
        let wayland_display = gtk::Entry::new();
        wayland_display.set_text(&cfg.settings.wayland_display);
        for (t, w) in [("Auto Scale", auto_scale.clone().upcast::<gtk::Widget>()), ("Wayland Display", wayland_display.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); display_group.add(&row);
        }
        display_page.add(&display_group);
        stack.add_named(&display_page, Some("Display"));

        // Input
        let input_page = adw::PreferencesPage::new();
        let input_group = adw::PreferencesGroup::new();
        input_group.set_title("Input");
        let input_profile = gtk::Entry::new();
        input_profile.set_text(&cfg.settings.input_profile);
        let key_repeat = gtk::SpinButton::with_range(1.0, 60.0, 1.0);
        key_repeat.set_value(cfg.settings.key_repeat as f64);
        for (t, w) in [("Default Input Profile", input_profile.clone().upcast::<gtk::Widget>()), ("Key Repeat", key_repeat.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); input_group.add(&row);
        }
        input_page.add(&input_group);
        stack.add_named(&input_page, Some("Input"));

        // Graphics
        let graphics_page = adw::PreferencesPage::new();
        let graphics_group = adw::PreferencesGroup::new();
        graphics_group.set_title("Graphics");
        let renderer = gtk::ComboBoxText::new();
        for r in ["vulkan", "software"] {
            let label = r[..1].to_uppercase() + &r[1..];
            renderer.append(Some(r), &label);
        }
        renderer.set_active_id(Some(&cfg.settings.renderer));
        let force_ssd = gtk::Switch::new();
        force_ssd.set_valign(gtk::Align::Center);
        force_ssd.set_active(cfg.settings.force_ssd);
        let color_ops = gtk::Switch::new();
        color_ops.set_valign(gtk::Align::Center);
        color_ops.set_active(cfg.settings.color_operations);
        for (t, w) in [("Renderer", renderer.clone().upcast::<gtk::Widget>()), ("Force Server-Side Decorations", force_ssd.clone().upcast::<gtk::Widget>()), ("HDR / Color Operations", color_ops.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); graphics_group.add(&row);
        }
        graphics_page.add(&graphics_group);
        stack.add_named(&graphics_page, Some("Graphics"));

        // SSH and Waypipe
        let ssh_page = adw::PreferencesPage::new();
        let ssh_group = adw::PreferencesGroup::new();
        ssh_group.set_title("SSH");
        let ssh_host = gtk::Entry::new(); ssh_host.set_text(&cfg.settings.ssh_host);
        let ssh_user = gtk::Entry::new(); ssh_user.set_text(&cfg.settings.ssh_user);
        let ssh_password = gtk::PasswordEntry::builder().show_peek_icon(true).build();
        ssh_password.set_text(&cfg.settings.ssh_password);
        let ssh_port = gtk::Entry::new(); ssh_port.set_text(&cfg.settings.ssh_port.to_string());
        for (t, w) in [("Host", ssh_host.clone().upcast::<gtk::Widget>()), ("User", ssh_user.clone().upcast::<gtk::Widget>()), ("Password", ssh_password.clone().upcast::<gtk::Widget>()), ("Port", ssh_port.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); ssh_group.add(&row);
        }
        let waypipe_group = adw::PreferencesGroup::new();
        waypipe_group.set_title("Waypipe");
        let wp_compress = gtk::Entry::new(); wp_compress.set_text(&cfg.settings.waypipe_compression);
        let wp_video = gtk::Entry::new(); wp_video.set_text(&cfg.settings.waypipe_video);
        let wp_debug = gtk::Switch::new(); wp_debug.set_valign(gtk::Align::Center); wp_debug.set_active(cfg.settings.waypipe_debug);
        let wp_enabled = gtk::Switch::new(); wp_enabled.set_valign(gtk::Align::Center); wp_enabled.set_active(cfg.settings.waypipe_enabled);
        for (t, w) in [("Compression", wp_compress.clone().upcast::<gtk::Widget>()), ("Video", wp_video.clone().upcast::<gtk::Widget>()), ("Debug", wp_debug.clone().upcast::<gtk::Widget>()), ("Default Waypipe Enabled", wp_enabled.clone().upcast::<gtk::Widget>())] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(&w); row.set_activatable(false); waypipe_group.add(&row);
        }
        ssh_page.add(&ssh_group);
        ssh_page.add(&waypipe_group);
        stack.add_named(&ssh_page, Some("SSH and Waypipe"));

        // Advanced
        let advanced_page = adw::PreferencesPage::new();
        let advanced_group = adw::PreferencesGroup::new();
        advanced_group.set_title("Advanced");
        let log_level = gtk::ComboBoxText::new();
        for l in ["debug", "info", "warn", "error"] {
            let label = l[..1].to_uppercase() + &l[1..];
            log_level.append(Some(l), &label);
        }
        log_level.set_active_id(Some(&cfg.settings.log_level));
        let ll_row = adw::ActionRow::new(); ll_row.set_title("Log Level"); ll_row.add_suffix(&log_level); ll_row.set_activatable(false);
        advanced_group.add(&ll_row);
        advanced_page.add(&advanced_group);
        stack.add_named(&advanced_page, Some("Advanced"));

        // Launch Agent
        let agent_page = adw::PreferencesPage::new();
        let agent_group = adw::PreferencesGroup::new();
        agent_group.set_title("Launch Agent and Runtime");
        let install_btn = gtk::Button::with_label("Install systemd user units + autostart");
        let start_host_btn = gtk::Button::with_label("Start compositor host service");
        let restart_host_btn = gtk::Button::with_label("Restart compositor host service");
        let stop_host_btn = gtk::Button::with_label("Stop compositor host service");
        let start_tray_btn = gtk::Button::with_label("Start tray applet service");
        for (t, b) in [("Install", &install_btn), ("Host Start", &start_host_btn), ("Host Restart", &restart_host_btn), ("Host Stop", &stop_host_btn), ("Tray", &start_tray_btn)] {
            let row = adw::ActionRow::new(); row.set_title(t); row.add_suffix(b); row.set_activatable(false); agent_group.add(&row);
        }
        install_btn.connect_clicked(|_| { let _ = service::install_user_units(); });
        start_host_btn.connect_clicked(|_| { let _ = service::start_compositor_service(); });
        restart_host_btn.connect_clicked(|_| { let _ = service::restart_compositor_service(); });
        stop_host_btn.connect_clicked(|_| { let _ = service::stop_compositor_service(); });
        start_tray_btn.connect_clicked(|_| { let _ = service::start_tray_service(); });
        agent_page.add(&agent_group);
        stack.add_named(&agent_page, Some("Launch Agent"));

        // Diagnostics
        let diag_page = adw::PreferencesPage::new();
        let diag_group = adw::PreferencesGroup::new();
        diag_group.set_title("Runtime Diagnostics");
        let state_row = adw::ActionRow::new();
        state_row.set_title("Runtime State");
        state_row.set_subtitle(&match runtime::read_runtime_state() {
            Ok(rt) => format!("healthy={} display={} socket={}", rt.healthy, rt.wayland_display, rt.socket_path),
            Err(_) => "No runtime state available".to_string(),
        });
        diag_group.add(&state_row);
        diag_page.add(&diag_group);
        stack.add_named(&diag_page, Some("Diagnostics"));

        // About
        let about_page = adw::PreferencesPage::new();
        let about_group = adw::PreferencesGroup::new();
        about_group.set_title("Wawona");
        let ver_row = adw::ActionRow::new();
        ver_row.set_title("Version");
        ver_row.set_subtitle(&format!("{} ({})", version(), build_info()));
        about_group.add(&ver_row);
        let desc_row = adw::ActionRow::new();
        desc_row.set_title("Description");
        desc_row.set_subtitle("Multi-platform compositor control plane.");
        about_group.add(&desc_row);
        let deps_group = adw::PreferencesGroup::new();
        deps_group.set_title("Dependencies");
        for dep in ["Wayland", "waypipe", "xkbcommon", "Mesa", "GTK4", "libadwaita"] {
            let row = adw::ActionRow::new(); row.set_title(dep); deps_group.add(&row);
        }
        about_page.add(&about_group);
        about_page.add(&deps_group);
        stack.add_named(&about_page, Some("About"));

        drop(cfg);

        // Sidebar selection drives stack
        {
            let stack = stack.clone();
            sidebar.connect_row_selected(move |_, row| {
                if let Some(row) = row {
                    let idx = row.index() as usize;
                    if idx < sections.len() {
                        stack.set_visible_child_name(sections[idx]);
                    }
                }
            });
        }
        if let Some(first_row) = sidebar.row_at_index(0) {
            sidebar.select_row(Some(&first_row));
        }

        let split = gtk::Paned::new(gtk::Orientation::Horizontal);
        split.set_position(180);
        split.set_wide_handle(true);
        split.set_shrink_start_child(false);
        split.set_shrink_end_child(false);

        let sidebar_scroll = gtk::ScrolledWindow::new();
        sidebar_scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
        sidebar_scroll.set_child(Some(&sidebar));

        let detail_scroll = gtk::ScrolledWindow::new();
        detail_scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
        detail_scroll.set_child(Some(&stack));

        split.set_start_child(Some(&sidebar_scroll));
        split.set_end_child(Some(&detail_scroll));

        let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
        content.append(&header);
        content.append(&split);
        dialog.set_child(Some(&content));

        // Done → save all settings
        {
            let d = dialog.clone();
            let st = state.clone();
            done_btn.connect_clicked(move |_| {
                let mut cfg = st.borrow_mut();
                cfg.settings.wayland_display = wayland_display.text().to_string();
                cfg.settings.auto_scale = auto_scale.is_active();
                cfg.settings.input_profile = input_profile.text().to_string();
                cfg.settings.key_repeat = key_repeat.value() as u32;
                cfg.settings.renderer = renderer.active_id().map(|s| s.to_string()).unwrap_or_else(|| "vulkan".into());
                cfg.settings.force_ssd = force_ssd.is_active();
                cfg.settings.color_operations = color_ops.is_active();
                cfg.settings.ssh_host = ssh_host.text().to_string();
                cfg.settings.ssh_user = ssh_user.text().to_string();
                cfg.settings.ssh_port = ssh_port.text().parse::<u16>().unwrap_or(22);
                cfg.settings.ssh_password = ssh_password.text().to_string();
                cfg.settings.waypipe_compression = wp_compress.text().to_string();
                cfg.settings.waypipe_video = wp_video.text().to_string();
                cfg.settings.waypipe_debug = wp_debug.is_active();
                cfg.settings.waypipe_enabled = wp_enabled.is_active();
                cfg.settings.log_level = log_level.active_id().map(|s| s.to_string()).unwrap_or_else(|| "info".into());
                persist(&cfg);
                wawona::wlog!("UI", "Settings saved");
                d.close();
            });
        }
        dialog.present();
    }
}

#[cfg(feature = "linux-ui")]
fn main() { app::run(); }

#[cfg(not(feature = "linux-ui"))]
fn main() { eprintln!("wawona-linux-ui requires --features linux-ui"); }
