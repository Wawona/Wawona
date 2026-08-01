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
    use wawona::linux::config;
    use wawona::linux::machine_profile::MachineType;
    use wawona::linux::runtime::{
        self, ensure_runtime_dir, now_unix_ms, now_unix_s, write_runtime_env, write_runtime_state,
        RuntimeState,
    };
    use wawona::linux::ui::{
        a11y, build_home_shell, clamp_content, install_breakpoint, rebuild_home, show_editor,
        show_settings, AppState, HomeShell, LayoutBinding, MachineSessions, RebuildHome,
        SharedAppState,
    };
    use wawona::linux::ui_model::LayoutMode;
    use wawona::linux::service;

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
        /// When true, skip opaque host fill so CSD rounded corners stay transparent.
        client_side_decorated: bool,
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
        /// Host windows currently in an xdg interactive-resize session.
        interactive_resize_active: HashSet<u64>,
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
        if cs.interactive_resize_active.insert(wid) {
            core.begin_interactive_resize(WindowId { id: wid });
        }
        for c_wid in companions {
            core.set_window_size_local(WindowId { id: c_wid }, w, h);
        }
        core.resize_window(WindowId { id: wid }, w, h);
    }

    fn settle_interactive_resize(cs: &mut CompositorState, wid: u64, w: u32, h: u32) {
        if !cs.interactive_resize_active.remove(&wid) {
            return;
        }
        let w = w.max(1);
        let h = h.max(1);
        wawona::wlog!(
            "COMPOSITOR",
            "Settling interactive resize wid={} {}x{}",
            wid,
            w,
            h
        );
        cs.core
            .end_interactive_resize(WindowId { id: wid }, w, h);
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

    fn build_ui(app: &adw::Application) {
        wawona::wlog!("UI", "Building main window");

        let loaded = AppState::load();
        wawona::wlog!(
            "UI",
            "Config loaded machines={} active={:?}",
            loaded.store.profiles.len(),
            loaded.store.active_machine_id
        );
        let state: SharedAppState = Rc::new(RefCell::new(loaded));
        let layout_binding = LayoutBinding::new(LayoutMode::Expanded);

        let compositor = start_embedded_compositor();
        // Propagate the GTK/GDK monitor scale factor into wl_output so HiDPI
        // clients render at native density instead of a hardcoded 1x.
        if let Some(core) = compositor.as_ref() {
            if let Some(display) = gtk::gdk::Display::default() {
                let monitors = display.monitors();
                let scale = (0..monitors.n_items())
                    .filter_map(|i| {
                        monitors
                            .item(i)
                            .and_then(|obj| obj.downcast::<gtk::gdk::Monitor>().ok())
                            .map(|m| m.scale_factor())
                    })
                    .max()
                    .unwrap_or(1)
                    .max(1);
                if scale > 1 {
                    wawona::wlog!("COMPOSITOR", "GDK monitor scale factor: {}", scale);
                    core.set_output_size(1280, 800, scale as f32);
                }
            }
        }
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
            interactive_resize_active: HashSet::new(),
        }));

        let window = adw::ApplicationWindow::builder()
            .application(app)
            .title("Wawona Machine Control Panel")
            .default_width(900)
            .default_height(640)
            .width_request(320)
            .height_request(480)
            .build();
        window.set_resizable(true);
        install_breakpoint(&window, &layout_binding);

        // Toolbar mirrors macOS `detailToolbarContent`: title "Machines",
        // search in the toolbar, and trailing primary actions [Add][Settings].
        let header = adw::HeaderBar::new();

        // pack_end order: first packed sits furthest right, so Settings goes
        // in before Add to render as [Add][Settings].
        let settings_btn = gtk::Button::from_icon_name("emblem-system-symbolic");
        settings_btn.set_tooltip_text(Some("Settings"));
        a11y::set_wwn_a11y(
            &settings_btn,
            a11y::id::MACHINES_SETTINGS,
            Some("Settings"),
        );
        header.pack_end(&settings_btn);

        let new_btn_content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        new_btn_content.append(&gtk::Image::from_icon_name("list-add-symbolic"));
        new_btn_content.append(&gtk::Label::new(Some("Add")));
        let new_btn = gtk::Button::new();
        new_btn.set_child(Some(&new_btn_content));
        new_btn.set_tooltip_text(Some("Add Machine Profile"));
        a11y::set_wwn_a11y(&new_btn, a11y::id::MACHINES_ADD, Some("Add Machine"));
        header.pack_end(&new_btn);

        let rebuild_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));
        let rebuild_slot_for_shell = rebuild_slot.clone();
        let on_rebuild = Rc::new(move || {
            if let Some(f) = rebuild_slot_for_shell.borrow().as_ref() {
                f();
            }
        });
        let home = build_home_shell(on_rebuild);
        header.set_title_widget(Some(&home.search));

        let home_body = clamp_content(&home.root);
        home_body.set_vexpand(true);
        let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
        root.append(&header);
        root.append(&home_body);
        window.set_content(Some(&root));

        {
            let home_c = home.clone();
            let state_c = state.clone();
            let window_c = window.clone();
            let sessions_c = machine_sessions.clone();
            let binding_c = layout_binding.clone();
            *rebuild_slot.borrow_mut() = Some(Rc::new(move || {
                rebuild_home(RebuildHome {
                    shell: &home_c,
                    state: &state_c,
                    parent: &window_c,
                    sessions: sessions_c.clone(),
                    layout: binding_c.get(),
                });
            }));
        }
        if let Some(rebuild) = rebuild_slot.borrow().as_ref() {
            rebuild();
        }

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
                            a11y::set_wwn_a11y(
                                &da,
                                a11y::id::COMPOSITOR_SURFACE,
                                Some("Wayland application"),
                            );
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
                                let core_act = cs.core.clone();
                                let wid_act = wid;
                                client_win.connect_is_active_notify(move |win| {
                                    let active = win.is_active();
                                    if active {
                                        let _ = da_active.grab_focus();
                                    }
                                    core_act.set_window_activated(
                                        WindowId { id: wid_act },
                                        active,
                                        true,
                                    );
                                });
                            }

                            // Host chrome max/fs → xdg_toplevel state (SSD + CSD hosts).
                            {
                                let core_m = cs.core.clone();
                                let da_m = da.clone();
                                let wid_m = wid;
                                client_win.connect_notify_local(Some("maximized"), move |win, _| {
                                    let w = da_m.width().max(1) as u32;
                                    let h = da_m.height().max(1) as u32;
                                    core_m.apply_host_window_maximized(
                                        WindowId { id: wid_m },
                                        win.is_maximized(),
                                        w,
                                        h,
                                    );
                                });
                            }
                            {
                                let core_f = cs.core.clone();
                                let da_f = da.clone();
                                let wid_f = wid;
                                client_win.connect_notify_local(Some("fullscreened"), move |win, _| {
                                    let w = da_f.width().max(1) as u32;
                                    let h = da_f.height().max(1) as u32;
                                    core_f.apply_host_window_fullscreen(
                                        WindowId { id: wid_f },
                                        win.is_fullscreen(),
                                        w,
                                        h,
                                    );
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
                                let cs = comp_for_draw.borrow();
                                let host_csd = cs
                                    .client_windows
                                    .get(&wid_for_draw)
                                    .map(|cw| cw.client_side_decorated)
                                    .unwrap_or(false);
                                if !host_csd {
                                    cr.set_source_rgb(0.12, 0.12, 0.14);
                                    cr.rectangle(0.0, 0.0, width as f64, height as f64);
                                    let _ = cr.fill();
                                }

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

                                // Host window origin in output coords: companion
                                // nodes (popups) are positioned relative to it,
                                // not to their own window anchor (which would
                                // collapse every popup to (0,0)).
                                let host_anchor = scene
                                    .nodes
                                    .iter()
                                    .find(|n| n.window_id.id == wid_for_draw)
                                    .map(|n| (n.anchor_output_x, n.anchor_output_y));

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
                                    let (anchor_x, anchor_y) =
                                        if node.window_id.id != wid_for_draw {
                                            let (hx, hy) = host_anchor.unwrap_or((
                                                node.anchor_output_x,
                                                node.anchor_output_y,
                                            ));
                                            (hx as f64, hy as f64)
                                        } else {
                                            (
                                                node.anchor_output_x as f64,
                                                node.anchor_output_y as f64,
                                            )
                                        };
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
                            {
                                let comp_init = comp.clone();
                                let da_init = da.clone();
                                let wid_init = wid;
                                gtk::glib::idle_add_local_once(move || {
                                    let w = da_init.width().max(1) as u32;
                                    let h = da_init.height().max(1) as u32;
                                    let mut cs = comp_init.borrow_mut();
                                    cs.pending_host_resizes.insert(wid_init, (w, h));
                                    dispatch_pending_host_resize(&mut cs, wid_init);
                                });
                            }
                            cs.client_windows.insert(wid, ClientWindow {
                                gtk_window: client_win,
                                drawing_area: da,
                                window_id: wid,
                                companion_window_ids,
                                allow_host_close,
                                client_side_decorated: is_csd,
                            });
                        }
                        WindowEvent::Destroyed { window_id } => {
                            let wid = window_id.id;
                            cs.pending_host_resizes.remove(&wid);
                            cs.resize_in_flight.remove(&wid);
                            cs.last_dispatched_host_resizes.remove(&wid);
                            cs.interactive_resize_active.remove(&wid);
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
                                if cs.pending_host_resizes.contains_key(&window_id.id) {
                                    dispatch_pending_host_resize(&mut cs, window_id.id);
                                } else {
                                    // No newer host tick pending — clear
                                    // xdg_toplevel.state.resizing with a settle
                                    // configure (even if size is unchanged).
                                    settle_interactive_resize(
                                        &mut cs,
                                        window_id.id,
                                        width,
                                        height,
                                    );
                                }
                            }
                        }
                        WindowEvent::PopupCreated { window_id, parent_id, x, y, width, height } => {
                            // Composite the popup inside the host window that
                            // renders its parent (toplevel or another popup's
                            // host) — same mechanism as fullscreen-shell
                            // companions.
                            let pid = parent_id.id;
                            let host_wid = if cs.client_windows.contains_key(&pid) {
                                Some(pid)
                            } else {
                                cs.client_windows
                                    .iter()
                                    .find(|(_, cw)| cw.companion_window_ids.contains(&pid))
                                    .map(|(hwid, _)| *hwid)
                            };
                            wawona::wlog!(
                                "COMPOSITOR",
                                "Popup wid={} parent={} at ({},{}) {}x{} → host {:?}",
                                window_id.id, pid, x, y, width, height, host_wid
                            );
                            if let Some(hwid) = host_wid {
                                if let Some(host) = cs.client_windows.get_mut(&hwid) {
                                    if !host.companion_window_ids.contains(&window_id.id) {
                                        host.companion_window_ids.push(window_id.id);
                                    }
                                    host.drawing_area.queue_draw();
                                }
                            }
                        }
                        WindowEvent::PopupRepositioned { window_id, .. } => {
                            let wid = window_id.id;
                            for cw in cs.client_windows.values() {
                                if cw.companion_window_ids.contains(&wid) {
                                    cw.drawing_area.queue_draw();
                                }
                            }
                        }
                        WindowEvent::DecorationModeChanged { window_id, mode } => {
                            let is_csd = mode == DecorationMode::ClientSide;
                            let dims = if let Some(cw) = cs.client_windows.get_mut(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "Window {} decoration changed to {:?}", window_id.id, mode);
                                cw.client_side_decorated = is_csd;
                                cw.gtk_window.set_decorated(!is_csd);
                                let w = cw.drawing_area.width().max(1) as u32;
                                let h = cw.drawing_area.height().max(1) as u32;
                                Some((w, h))
                            } else {
                                None
                            };
                            if let Some((w, h)) = dims {
                                cs.pending_host_resizes.insert(window_id.id, (w, h));
                                dispatch_pending_host_resize(&mut cs, window_id.id);
                                if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                    cw.drawing_area.queue_draw();
                                }
                            }
                        }
                        WindowEvent::MinimizeRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "MinimizeRequested wid={}", window_id.id);
                                cw.gtk_window.minimize();
                            }
                        }
                        WindowEvent::MaximizeRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "MaximizeRequested wid={}", window_id.id);
                                cw.gtk_window.maximize();
                            }
                        }
                        WindowEvent::UnmaximizeRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "UnmaximizeRequested wid={}", window_id.id);
                                cw.gtk_window.unmaximize();
                            }
                        }
                        WindowEvent::FullscreenRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "FullscreenRequested wid={}", window_id.id);
                                cw.gtk_window.fullscreen();
                            }
                        }
                        WindowEvent::UnfullscreenRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "UnfullscreenRequested wid={}", window_id.id);
                                cw.gtk_window.unfullscreen();
                            }
                        }
                        WindowEvent::CloseRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!("COMPOSITOR", "CloseRequested wid={} → host close", window_id.id);
                                cw.allow_host_close.set(true);
                                cw.gtk_window.close();
                            }
                        }
                        WindowEvent::Activated { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                cw.gtk_window.present();
                                let _ = cw.drawing_area.grab_focus();
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
            let home = home.clone();
            let sessions_n = machine_sessions.clone();
            let binding = layout_binding.clone();
            new_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Add Machine button pressed");
                let default_type = MachineType::Native;
                show_editor(
                    &window,
                    &state,
                    None,
                    default_type,
                    &home,
                    sessions_n.clone(),
                    binding.get(),
                );
            });
        }

        {
            let state = state.clone();
            let window = window.clone();
            let binding = layout_binding.clone();
            settings_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Settings button pressed");
                show_settings(&window, &state, binding.get());
            });
        }

        wawona::wlog!("UI", "Main window presented");
        window.present();
    }
}
#[cfg(feature = "linux-ui")]
fn main() { app::run(); }

#[cfg(not(feature = "linux-ui"))]
fn main() { eprintln!("wawona-linux-ui requires --features linux-ui"); }
