#[cfg(feature = "linux-ui")]
mod app {
    use std::cell::{Cell, RefCell};
    use std::collections::{HashMap, HashSet};
    use std::env;
    use std::path::Path;
    use std::rc::Rc;
    use std::sync::Arc;
    use std::time::Duration;

    use adw::prelude::*;
    use gtk4 as gtk;
    use libadwaita as adw;

    use wawona::ffi::api::WawonaCore;
    use wawona::ffi::api::{build_info, version};
    use wawona::ffi::types::{
        AxisSource, BufferData, DecorationMode, KeyState as WlKeyState, PointerAxis, PointerButton,
        RenderScene, WindowEvent, WindowId, WindowSizeCause,
    };
    use wawona::linux::machine_profile::MachineType;
    use wawona::linux::runtime::{
        ensure_runtime_dir, now_unix_ms, now_unix_s, read_runtime_state, write_runtime_env,
        write_runtime_state, RuntimeState,
    };
    use wawona::linux::ui::{
        a11y, bind_content_sidebar_toggle, build_home_shell, build_settings_view,
        build_tab_overview_view, build_work_status_view, clamp_content, ensure_settings_css,
        install_adaptive_split_view, is_touchscreen_active, make_resizable_sidebar,
        maybe_show_welcome, rebuild_home, scrollable_sidebar, show_editor,
        sidebar_column_with_toggle, AppState, LayoutBinding, MachineSessions, RebuildHome,
        SharedAppState,
    };
    use wawona::linux::ui_model::LayoutMode;
    use wawona::wlog;

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
        /// `zwp_fullscreen_shell_v1` kiosk surfaces for this connection. Drawn into this GtkWindow only.
        companion_window_ids: Vec<u64>,
        /// Allow internal `WindowEvent::Destroyed` teardown to bypass the user close interceptor.
        allow_host_close: Rc<Cell<bool>>,
        /// When true, skip opaque host fill so CSD rounded corners stay transparent.
        client_side_decorated: bool,
        /// Nested weston/niri / terminals: do not OWL-shrink on ClientCommit.
        fills_host: bool,
    }

    struct CompositorState {
        core: Arc<WawonaCore>,
        buffer_cache: HashMap<(u32, u64), CachedBuffer>,
        scene: Option<RenderScene>,
        presented: Vec<(u32, u64)>,
        client_windows: HashMap<u64, ClientWindow>,
        /// Fullscreen-shell window ids waiting for a normal toplevel from the same client.
        pending_fullscreen_shell_by_client: HashMap<u64, Vec<u64>>,
        /// First non-fullscreen-shell Wayland window per client → its Gtk host (for kiosk + xdg pairing).
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

    /// Snapshot the largest Wayland SHM surface into the active machine thumbnail.
    fn maybe_save_wayland_thumbnail(
        cs: &CompositorState,
        state: &SharedAppState,
        last_ms: &Cell<i64>,
    ) {
        let now = now_unix_ms() as i64;
        if now.saturating_sub(last_ms.get()) < 1200 {
            return;
        }
        let machine_id = {
            let app = state.borrow();
            let Some(id) = app.store.active_machine_id.clone() else {
                return;
            };
            let profile = app.store.profile(&id);
            if !wawona::linux::session_exit::thumbnails_enabled(&app.settings, profile) {
                return;
            }
            id
        };
        let Some(scene) = cs.scene.as_ref() else {
            return;
        };
        let mut best: Option<(u32, u32, u32, Vec<u8>)> = None;
        let mut best_area = 0u64;
        for node in &scene.nodes {
            let sid = node.surface_id.id;
            let bid = node.texture.handle;
            if bid == 0 {
                continue;
            }
            let Some(buf) = cs.buffer_cache.get(&(sid, bid)) else {
                continue;
            };
            if buf.width < 8 || buf.height < 8 {
                continue;
            }
            let area = buf.width as u64 * buf.height as u64;
            if area > best_area {
                best_area = area;
                best = Some((buf.width, buf.height, buf.stride, buf.pixels.clone()));
            }
        }
        let Some((width, height, stride, pixels)) = best else {
            return;
        };
        last_ms.set(now);
        if let Err(err) = wawona::linux::thumbnail_store::save_argb32_premul(
            &machine_id,
            width,
            height,
            stride,
            &pixels,
        ) {
            wawona::wlog!("UI", "machine thumbnail save failed: {err}");
        }
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
        if cs.last_dispatched_host_resizes.get(&wid).copied() == Some((w, h)) {
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
        cs.core.end_interactive_resize(WindowId { id: wid }, w, h);
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
            let is_alive = std::os::unix::net::UnixStream::connect(&sock).is_ok();
            if !is_alive {
                if sock.exists() {
                    let _ = std::fs::remove_file(&sock);
                }
                if lock.exists() {
                    let _ = std::fs::remove_file(&lock);
                }
            }
        }

        for i in 0..4 {
            let candidate = format!("wawona-{i}");
            let core = WawonaCore::new();
            core.set_force_ssd(true);
            core.set_advertise_fullscreen_shell(true);
            core.set_output_size(1280, 800, 1.0);
            match core.start(Some(candidate.clone())) {
                Ok(_) => {
                    wawona::wlog!(
                        "COMPOSITOR",
                        "Embedded compositor started socket={}",
                        candidate
                    );
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

    fn setup_input_on_drawing_area(da: &gtk::DrawingArea, core: &Arc<WawonaCore>, wid: u64) {
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
        let click_ctrl = gtk::GestureClick::builder().button(0).build();
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
                core.inject_keyboard_enter(wid, Vec::new());
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

        // Focus controller for keyboard enter / leave
        let focus_ctrl = gtk::EventControllerFocus::new();
        {
            let core = core.clone();
            let wid = window_id;
            focus_ctrl.connect_enter(move |_| {
                core.inject_keyboard_enter(wid, Vec::new());
            });
        }
        {
            let core = core.clone();
            let wid = window_id;
            focus_ctrl.connect_leave(move |_| {
                core.inject_keyboard_leave(wid);
            });
        }
        da.add_controller(focus_ctrl);

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
                    core.inject_pointer_axis(
                        wid,
                        PointerAxis::Vertical,
                        dy * 15.0,
                        0,
                        AxisSource::Wheel,
                        ts,
                    );
                }
                if dx.abs() > 0.001 {
                    core.inject_pointer_axis(
                        wid,
                        PointerAxis::Horizontal,
                        dx * 15.0,
                        0,
                        AxisSource::Wheel,
                        ts,
                    );
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
                core.inject_key(keycode.saturating_sub(8), WlKeyState::Pressed, ts);
                gtk::glib::Propagation::Stop
            });
        }
        {
            let core = core.clone();
            key_ctrl.connect_key_released(move |_, _keyval, keycode, _| {
                let ts = (now_unix_ms() & 0xFFFF_FFFF) as u32;
                core.inject_key(keycode.saturating_sub(8), WlKeyState::Released, ts);
            });
        }
        da.add_controller(key_ctrl);

        da.set_focusable(true);
        da.set_can_focus(true);
    }

    pub fn run() {
        wawona::wlog!(
            "UI",
            "Wawona Linux starting version={} build={}",
            version(),
            build_info()
        );

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
        wawona::wlog!(
            "UI",
            "GTK initialized backend={}",
            env::var("GDK_BACKEND").unwrap_or_else(|_| "auto".into())
        );

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
        if let Some(core) = compositor.as_ref() {
            wawona::linux::embedded_core::set(core.clone());
        }
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
                wawona::wlog!(
                    "COMPOSITOR",
                    "No embedded compositor; windows will not render"
                );
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
            .title("Wawona")
            .default_width(900)
            .default_height(640)
            .width_request(240)
            .height_request(360)
            .build();
        window.set_resizable(true);
        let split_view = adw::OverlaySplitView::new();
        split_view.set_min_sidebar_width(180.0);
        split_view.set_max_sidebar_width(520.0);
        split_view.set_sidebar_width_fraction(0.25);
        split_view.set_enable_show_gesture(true);
        split_view.set_enable_hide_gesture(true);
        split_view.set_show_sidebar(true);

        let key_controller = gtk::EventControllerKey::new();
        let split_view_key = split_view.clone();
        key_controller.connect_key_pressed(move |_, keyval, _, state| {
            let is_ctrl = state.contains(gtk::gdk::ModifierType::CONTROL_MASK);
            if (is_ctrl
                && (keyval == gtk::gdk::Key::b
                    || keyval == gtk::gdk::Key::B
                    || keyval == gtk::gdk::Key::backslash))
                || keyval == gtk::gdk::Key::F9
            {
                let shows = split_view_key.shows_sidebar();
                split_view_key.set_show_sidebar(!shows);
                gtk::glib::Propagation::Stop
            } else {
                gtk::glib::Propagation::Proceed
            }
        });
        window.add_controller(key_controller);

        let icon_theme = gtk::IconTheme::for_display(&gtk4::prelude::WidgetExt::display(&window));
        if let Ok(entries) = std::fs::read_dir("/nix/store") {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.contains("adwaita-icon-theme")
                        && !name.ends_with(".drv")
                        && !name.ends_with(".xz")
                    {
                        let icons_dir = path.join("share").join("icons");
                        if icons_dir.is_dir() {
                            icon_theme.add_search_path(&icons_dir);
                        }
                    }
                }
            }
        }

        // Toolbar mirrors macOS: inline navigation title "Machine Configuration",
        // search in the bar, trailing Add and Settings. The window name stays
        // Wawona. No second app-name mark in the header.
        let header = adw::HeaderBar::new();

        let toggle_icon_name = [
            "sidebar-show-symbolic",
            "view-sidebar-symbolic",
            "pan-start-symbolic",
        ]
        .into_iter()
        .find(|&ic| icon_theme.has_icon(ic))
        .unwrap_or("sidebar-show-symbolic");

        let toggle_sidebar_btn = gtk::Button::from_icon_name(toggle_icon_name);
        toggle_sidebar_btn.set_tooltip_text(Some("Toggle Sidebar (Ctrl+B)"));
        a11y::set_wwn_a11y(
            &toggle_sidebar_btn,
            "wwn.machines.toggleSidebar",
            Some("Toggle Sidebar"),
        );
        let split_view_toggle = split_view.clone();
        toggle_sidebar_btn.connect_clicked(move |_| {
            let shows = split_view_toggle.shows_sidebar();
            split_view_toggle.set_show_sidebar(!shows);
        });
        header.pack_start(&toggle_sidebar_btn);

        let view_title = adw::WindowTitle::new("Machine Configuration", "");
        a11y::set_wwn_a11y(
            &view_title,
            "wwn.header.title",
            Some("Machine Configuration"),
        );
        header.set_title_widget(Some(&view_title));

        // pack_end order: first packed sits furthest right, so Settings goes
        // in before Add to render as [Search][Add][Settings].
        let settings_btn = gtk::Button::from_icon_name("emblem-system-symbolic");
        settings_btn.set_tooltip_text(Some("Settings"));
        a11y::set_wwn_a11y(&settings_btn, a11y::id::MACHINES_SETTINGS, Some("Settings"));
        header.pack_end(&settings_btn);

        let new_btn = gtk::Button::from_icon_name("list-add-symbolic");
        new_btn.add_css_class("suggested-action");
        new_btn.set_tooltip_text(Some("Add Machine Profile"));
        a11y::set_wwn_a11y(&new_btn, a11y::id::MACHINES_ADD, Some("Add Machine"));
        header.pack_end(&new_btn);

        let search_toggle_btn = gtk::ToggleButton::new();
        search_toggle_btn.set_icon_name("system-search-symbolic");
        search_toggle_btn.set_tooltip_text(Some("Search Machines (Ctrl+F)"));
        a11y::set_wwn_a11y(
            &search_toggle_btn,
            "wwn.machines.searchToggle",
            Some("Search Machines"),
        );
        header.pack_end(&search_toggle_btn);

        let rebuild_slot: Rc<RefCell<Option<Rc<dyn Fn()>>>> = Rc::new(RefCell::new(None));
        let rebuild_slot_for_shell = rebuild_slot.clone();
        let on_rebuild = Rc::new(move || {
            if let Some(f) = rebuild_slot_for_shell.borrow().as_ref() {
                f();
            }
        });
        let home = build_home_shell(on_rebuild.clone());
        home.search.set_hexpand(false);
        home.search.set_width_chars(12);
        home.search.set_max_width_chars(20);
        header.pack_end(&home.search);

        let search_revealer = gtk::Revealer::new();
        search_revealer.set_transition_type(gtk::RevealerTransitionType::SlideDown);
        let compact_search_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        compact_search_box.add_css_class("compact-search-bar");
        let compact_search = gtk::SearchEntry::new();
        compact_search.set_placeholder_text(Some("Search machines"));
        compact_search.set_hexpand(true);
        a11y::set_wwn_a11y(
            &compact_search,
            a11y::id::MACHINES_SEARCH,
            Some("Search machines"),
        );
        let compact_clamp = clamp_content(&compact_search);
        compact_clamp.set_hexpand(true);
        compact_search_box.append(&compact_clamp);
        search_revealer.set_child(Some(&compact_search_box));

        let rev_c = search_revealer.clone();
        let cs_focus = compact_search.clone();
        search_toggle_btn.connect_toggled(move |btn| {
            let active = btn.is_active();
            rev_c.set_reveal_child(active);
            if active {
                cs_focus.grab_focus();
            }
        });

        let st_escape = search_toggle_btn.clone();
        compact_search.connect_stop_search(move |_| {
            st_escape.set_active(false);
        });

        let bottom_bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        bottom_bar.add_css_class("bottom-search-toolbar");
        let bottom_search = gtk::SearchEntry::new();
        bottom_search.set_placeholder_text(Some("Search machines"));
        bottom_search.set_hexpand(true);
        bottom_search.add_css_class("search-entry");
        a11y::set_wwn_a11y(
            &bottom_search,
            a11y::id::MACHINES_SEARCH,
            Some("Search machines"),
        );

        let bottom_add_btn = gtk::Button::from_icon_name("list-add-symbolic");
        bottom_add_btn.set_tooltip_text(Some("Add Machine Profile"));
        bottom_add_btn.add_css_class("suggested-action");
        bottom_add_btn.add_css_class("circular");
        bottom_add_btn.add_css_class("bottom-add-btn");
        a11y::set_wwn_a11y(&bottom_add_btn, a11y::id::MACHINES_ADD, Some("Add Machine"));

        bottom_bar.append(&bottom_search);
        bottom_bar.append(&bottom_add_btn);

        {
            let query_rc = home.query.clone();
            let on_reb = on_rebuild.clone();
            let s_top = home.search.clone();
            let s_compact = compact_search.clone();
            let s_bottom = bottom_search.clone();

            let q1 = query_rc.clone();
            let r1 = on_reb.clone();
            let sc1 = s_compact.clone();
            let sb1 = s_bottom.clone();
            s_top.connect_search_changed(move |entry| {
                let text = entry.text().to_string();
                if *q1.borrow() != text {
                    *q1.borrow_mut() = text.clone();
                    if sc1.text().as_str() != text {
                        sc1.set_text(&text);
                    }
                    if sb1.text().as_str() != text {
                        sb1.set_text(&text);
                    }
                    r1();
                }
            });

            let q2 = query_rc.clone();
            let r2 = on_reb.clone();
            let st2 = s_top.clone();
            let sb2 = s_bottom.clone();
            s_compact.connect_search_changed(move |entry| {
                let text = entry.text().to_string();
                if *q2.borrow() != text {
                    *q2.borrow_mut() = text.clone();
                    if st2.text().as_str() != text {
                        st2.set_text(&text);
                    }
                    if sb2.text().as_str() != text {
                        sb2.set_text(&text);
                    }
                    r2();
                }
            });

            let q3 = query_rc.clone();
            let r3 = on_reb.clone();
            let st3 = s_top.clone();
            let sc3 = s_compact.clone();
            s_bottom.connect_search_changed(move |entry| {
                let text = entry.text().to_string();
                if *q3.borrow() != text {
                    *q3.borrow_mut() = text.clone();
                    if st3.text().as_str() != text {
                        st3.set_text(&text);
                    }
                    if sc3.text().as_str() != text {
                        sc3.set_text(&text);
                    }
                    r3();
                }
            });
        }

        ensure_settings_css();

        let sidebar_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
        sidebar_box.add_css_class("sidebar");

        let sidebar_list = gtk::ListBox::new();
        sidebar_list.set_selection_mode(gtk::SelectionMode::Single);
        sidebar_list.add_css_class("navigation-sidebar");
        sidebar_list.set_margin_start(8);
        sidebar_list.set_margin_end(8);
        sidebar_list.set_margin_top(8);

        let icon_theme = gtk::IconTheme::for_display(&gtk4::prelude::WidgetExt::display(&window));
        let make_sidebar_row = |name: &str, icons: &[&str], css_class: &str, a11y_id: &str| {
            let row = gtk::ListBoxRow::new();
            row.set_focusable(false);
            let row_box = gtk::Box::new(gtk::Orientation::Horizontal, 10);
            row_box.set_margin_start(10);
            row_box.set_margin_end(10);
            row_box.set_margin_top(8);
            row_box.set_margin_bottom(8);

            let chosen_icon = icons
                .iter()
                .copied()
                .find(|&ic| icon_theme.has_icon(ic))
                .unwrap_or_else(|| icons.first().copied().unwrap_or(""));

            let icon = gtk::Image::from_icon_name(chosen_icon);
            icon.set_pixel_size(18);
            icon.add_css_class(css_class);
            row_box.append(&icon);

            let label = gtk::Label::new(Some(name));
            label.set_xalign(0.0);
            label.set_hexpand(true);
            label.add_css_class("heading");
            row_box.append(&label);

            row.set_child(Some(&row_box));
            a11y::set_wwn_a11y(&row, a11y_id, Some(name));
            row
        };

        let make_section_hdr = |title: &str| {
            let lbl = gtk::Label::new(Some(title));
            lbl.add_css_class("dim-label");
            lbl.add_css_class("caption-heading");
            lbl.set_xalign(0.0);
            lbl.set_margin_start(12);
            lbl.set_margin_top(12);
            lbl.set_margin_bottom(4);
            lbl
        };

        let row_machines = make_sidebar_row(
            "Machines",
            &[
                "user-desktop-symbolic",
                "computer-symbolic",
                "video-display-symbolic",
            ],
            "wwn-icon-indigo",
            a11y::id::MACHINES_ROOT,
        );
        sidebar_list.append(&row_machines);

        let row_overview = make_sidebar_row(
            "Tab Overview",
            &["view-grid-symbolic", "window-restore-symbolic"],
            "wwn-icon-blue",
            a11y::id::MACHINES_OVERVIEW,
        );
        sidebar_list.append(&row_overview);

        let row_work_status = make_sidebar_row(
            "Work Status",
            &[
                "view-list-symbolic",
                "task-due-symbolic",
                "checkbox-checked-symbolic",
            ],
            "wwn-icon-orange",
            "wwn.projectStatus",
        );
        sidebar_list.append(&row_work_status);

        sidebar_list.set_header_func(move |row, _before| match row.index() {
            0 => row.set_header(Some(&make_section_hdr("Machines"))),
            2 => row.set_header(Some(&make_section_hdr("Project"))),
            _ => row.set_header(gtk::Widget::NONE),
        });

        sidebar_box.append(&sidebar_list);

        // Tags section
        let tags_section_box = gtk::Box::new(gtk::Orientation::Vertical, 2);
        tags_section_box.set_margin_start(8);
        tags_section_box.set_margin_end(8);
        tags_section_box.set_margin_top(8);

        let tags_header_box = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let tags_hdr = make_section_hdr("Tags");
        tags_hdr.set_hexpand(true);
        tags_header_box.append(&tags_hdr);

        let add_tag_btn = gtk::Button::from_icon_name("list-add-symbolic");
        add_tag_btn.add_css_class("flat");
        add_tag_btn.add_css_class("circular");
        add_tag_btn.set_tooltip_text(Some("New Tag"));
        a11y::set_wwn_a11y(&add_tag_btn, "wwn.sidebar.tag.add", Some("New Tag"));
        tags_header_box.append(&add_tag_btn);
        tags_section_box.append(&tags_header_box);

        let tags_list = gtk::ListBox::new();
        tags_list.set_selection_mode(gtk::SelectionMode::Single);
        tags_list.add_css_class("navigation-sidebar");
        tags_section_box.append(&tags_list);

        sidebar_box.append(&tags_section_box);

        {
            let window_t = window.clone();
            let state_t = state.clone();
            let on_rebuild_t = on_rebuild.clone();
            add_tag_btn.connect_clicked(move |_| {
                wawona::linux::ui::show_new_tag_dialog(
                    &window_t,
                    None,
                    state_t.clone(),
                    on_rebuild_t.clone(),
                );
            });
        }

        let spacer = gtk::Box::new(gtk::Orientation::Vertical, 0);
        spacer.set_vexpand(true);
        sidebar_box.append(&spacer);

        let wayland_display_str = read_runtime_state()
            .map(|rt| rt.wayland_display)
            .unwrap_or_else(|_| "wawona-0".to_string());
        let footer_card = gtk::Box::new(gtk::Orientation::Vertical, 4);
        footer_card.set_margin_start(12);
        footer_card.set_margin_end(12);
        footer_card.set_margin_bottom(12);
        footer_card.add_css_class("card");

        let footer_inner = gtk::Box::new(gtk::Orientation::Vertical, 4);
        footer_inner.set_margin_start(10);
        footer_inner.set_margin_end(10);
        footer_inner.set_margin_top(8);
        footer_inner.set_margin_bottom(8);

        let f_top = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let dot = gtk::Image::from_icon_name("media-record-symbolic");
        dot.set_pixel_size(10);
        dot.add_css_class("wwn-icon-green");
        f_top.append(&dot);
        let f_disp = gtk::Label::new(Some(&wayland_display_str));
        f_disp.add_css_class("heading");
        f_top.append(&f_disp);
        footer_inner.append(&f_top);

        let f_proto = gtk::Label::new(Some("32 Wayland Protocols"));
        f_proto.add_css_class("dim-label");
        f_proto.add_css_class("caption");
        f_proto.set_xalign(0.0);
        footer_inner.append(&f_proto);
        footer_card.append(&footer_inner);
        sidebar_box.append(&footer_card);

        let sidebar_scroll = scrollable_sidebar(&sidebar_box);
        let sidebar_column = sidebar_column_with_toggle(
            &split_view,
            &sidebar_scroll,
            toggle_icon_name,
            "wwn.machines.sidebarToggle",
        );
        bind_content_sidebar_toggle(&split_view, &toggle_sidebar_btn);
        let resizable_sidebar = make_resizable_sidebar(&split_view, &sidebar_column, 0.25);
        split_view.set_sidebar(Some(&resizable_sidebar));

        let content_stack = gtk::Stack::new();
        content_stack.set_transition_type(gtk::StackTransitionType::None);
        content_stack.set_hhomogeneous(false);
        content_stack.set_vhomogeneous(false);
        content_stack.set_hexpand(true);
        content_stack.set_vexpand(true);

        let home_body = clamp_content(&home.root);
        home_body.set_vexpand(true);
        let machines_page = gtk::Box::new(gtk::Orientation::Vertical, 0);
        machines_page.append(&header);
        machines_page.append(&search_revealer);
        machines_page.append(&home_body);
        machines_page.append(&bottom_bar);
        content_stack.add_named(&machines_page, Some("machines"));

        {
            let is_touch = is_touchscreen_active();
            let top_search_c = home.search.clone();
            let toggle_btn_c = search_toggle_btn.clone();
            let revealer_c = search_revealer.clone();
            let new_btn_c = new_btn.clone();
            let bottom_bar_c = bottom_bar.clone();
            let last_state = Rc::new(Cell::new(None::<(bool, bool)>));

            machines_page.add_tick_callback(move |widget, _| {
                let w = widget.width();
                if w <= 0 {
                    return gtk::glib::ControlFlow::Continue;
                }
                let is_compact = w < 760;
                if last_state.get() == Some((is_touch, is_compact)) {
                    return gtk::glib::ControlFlow::Continue;
                }
                last_state.set(Some((is_touch, is_compact)));

                if is_touch {
                    top_search_c.set_visible(false);
                    toggle_btn_c.set_visible(false);
                    revealer_c.set_reveal_child(false);
                    new_btn_c.set_visible(false);
                    bottom_bar_c.set_visible(true);
                } else {
                    bottom_bar_c.set_visible(false);
                    new_btn_c.set_visible(true);
                    if is_compact {
                        top_search_c.set_visible(false);
                        toggle_btn_c.set_visible(true);
                    } else {
                        top_search_c.set_visible(true);
                        toggle_btn_c.set_visible(false);
                        revealer_c.set_reveal_child(false);
                        toggle_btn_c.set_active(false);
                    }
                }

                gtk::glib::ControlFlow::Continue
            });
        }

        let editor_slot = gtk::Box::new(gtk::Orientation::Vertical, 0);
        editor_slot.set_hexpand(true);
        editor_slot.set_vexpand(true);
        content_stack.add_named(&editor_slot, Some("editor"));

        let tab_overview_slot = gtk::Box::new(gtk::Orientation::Vertical, 0);
        tab_overview_slot.set_hexpand(true);
        tab_overview_slot.set_vexpand(true);
        content_stack.add_named(&tab_overview_slot, Some("tab_overview"));

        let terminal_slot = gtk::Box::new(gtk::Orientation::Vertical, 0);
        terminal_slot.set_hexpand(true);
        terminal_slot.set_vexpand(true);
        content_stack.add_named(&terminal_slot, Some("terminal"));

        let active_terminal: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));

        let split_view_for_status = split_view.clone();
        let work_status_page = build_work_status_view(Some(Rc::new(move || {
            let shows = split_view_for_status.shows_sidebar();
            split_view_for_status.set_show_sidebar(!shows);
        })));
        content_stack.add_named(&work_status_page, Some("work_status"));

        split_view.set_content(Some(&content_stack));
        install_adaptive_split_view(&window, &split_view, &layout_binding);

        let root_stack = gtk::Stack::new();
        root_stack.set_transition_type(gtk::StackTransitionType::OverUpDown);
        root_stack.set_transition_duration(280);
        root_stack.set_hhomogeneous(false);
        root_stack.set_vhomogeneous(false);
        root_stack.set_hexpand(true);
        root_stack.set_vexpand(true);

        root_stack.add_named(&split_view, Some("main"));

        let settings_container = gtk::Box::new(gtk::Orientation::Vertical, 0);
        settings_container.set_hexpand(true);
        settings_container.set_vexpand(true);
        settings_container.add_css_class("settings-overlay-sheet");
        root_stack.add_named(&settings_container, Some("settings"));

        let root_overlay = gtk::Overlay::new();
        root_overlay.set_child(Some(&root_stack));
        root_overlay.set_hexpand(true);
        root_overlay.set_vexpand(true);

        window.set_content(Some(&root_overlay));

        let open_settings = {
            let root_stack = root_stack.clone();
            let settings_container = settings_container.clone();
            let state = state.clone();
            let on_rebuild = on_rebuild.clone();
            Rc::new(move || {
                while let Some(c) = settings_container.first_child() {
                    settings_container.remove(&c);
                }
                let root_stack_c = root_stack.clone();
                let on_rebuild_c = on_rebuild.clone();
                let on_done = Rc::new(move || {
                    on_rebuild_c();
                    root_stack_c.set_visible_child_name("main");
                });
                let settings_view = build_settings_view(&state, on_done);
                settings_container.append(&settings_view);
                root_stack.set_visible_child_name("settings");
            })
        };

        {
            let content_stack = content_stack.clone();
            let tab_overview_slot = tab_overview_slot.clone();
            let sidebar_list_c = sidebar_list.clone();
            let state = state.clone();
            let sessions = machine_sessions.clone();
            let on_rebuild = on_rebuild.clone();
            let active_terminal_tab = active_terminal.clone();
            let split_view_for_list = split_view.clone();
            let tags_list_c = tags_list.clone();
            let home_c = home.clone();
            sidebar_list.connect_row_selected(move |_, row| {
                let Some(r) = row else { return };
                tags_list_c.unselect_all();
                if split_view_for_list.is_collapsed() {
                    split_view_for_list.set_show_sidebar(false);
                }
                match r.index() {
                    0 => {
                        let was_filtered = home_c.selected_tag_id.borrow().is_some();
                        home_c.selected_tag_id.replace(None);
                        content_stack.set_visible_child_name("machines");
                        if was_filtered {
                            on_rebuild();
                        }
                    }
                    1 => {
                        while let Some(c) = tab_overview_slot.first_child() {
                            tab_overview_slot.remove(&c);
                        }
                        let stack_c = content_stack.clone();
                        let side_c = sidebar_list_c.clone();
                        let on_rebuild_c = on_rebuild.clone();
                        let active_term_c = active_terminal_tab.clone();
                        let on_select = Rc::new({
                            let stack_c = stack_c.clone();
                            let side_c = side_c.clone();
                            let on_rebuild_c = on_rebuild_c.clone();
                            let active_term_c = active_term_c.clone();
                            move |mid: String| {
                                on_rebuild_c();
                                if active_term_c.borrow().as_deref() == Some(&mid) {
                                    stack_c.set_visible_child_name("terminal");
                                } else {
                                    stack_c.set_visible_child_name("machines");
                                    if let Some(r0) = side_c.row_at_index(0) {
                                        side_c.select_row(Some(&r0));
                                    }
                                }
                            }
                        });
                        let on_close = Rc::new({
                            let stack_c = stack_c.clone();
                            let side_c = side_c.clone();
                            move || {
                                stack_c.set_visible_child_name("machines");
                                if let Some(r0) = side_c.row_at_index(0) {
                                    side_c.select_row(Some(&r0));
                                }
                            }
                        });
                        let tab_view =
                            build_tab_overview_view(&state, sessions.clone(), on_select, on_close);
                        tab_overview_slot.append(&tab_view);
                        content_stack.set_visible_child_name("tab_overview");
                    }
                    2 => {
                        content_stack.set_visible_child_name("work_status");
                    }
                    _ => {}
                }
            });
        }

        let is_rebuilding_tags = Rc::new(Cell::new(false));
        {
            let state = state.clone();
            let home = home.clone();
            let sidebar_list = sidebar_list.clone();
            let content_stack = content_stack.clone();
            let split_view = split_view.clone();
            let on_rebuild = on_rebuild.clone();
            let is_rebuilding_tags = is_rebuilding_tags.clone();
            tags_list.connect_row_selected(move |_, row| {
                if is_rebuilding_tags.get() {
                    return;
                }
                let Some(r) = row else { return };
                let idx = r.index() as usize;
                let tags = state.borrow().tags.tags.clone();
                if let Some(tag) = tags.get(idx) {
                    if home.selected_tag_id.borrow().as_deref() == Some(&tag.id) {
                        return;
                    }
                    sidebar_list.unselect_all();
                    home.selected_tag_id.replace(Some(tag.id.clone()));
                    content_stack.set_visible_child_name("machines");
                    if split_view.is_collapsed() {
                        split_view.set_show_sidebar(false);
                    }
                    on_rebuild();
                }
            });
        }

        let rebuild_tags_list = {
            let tags_list = tags_list.clone();
            let state = state.clone();
            let home = home.clone();
            let window = window.clone();
            let on_rebuild = on_rebuild.clone();
            let is_rebuilding_tags = is_rebuilding_tags.clone();

            Rc::new(move || {
                is_rebuilding_tags.set(true);
                while let Some(c) = tags_list.first_child() {
                    tags_list.remove(&c);
                }

                let all_tags = state.borrow().tags.tags.clone();
                let current_sel = home.selected_tag_id.borrow().clone();

                for tag in all_tags {
                    let row = gtk::ListBoxRow::new();
                    row.set_focusable(false);
                    let row_box = gtk::Box::new(gtk::Orientation::Horizontal, 10);
                    row_box.set_margin_start(10);
                    row_box.set_margin_end(10);
                    row_box.set_margin_top(6);
                    row_box.set_margin_bottom(6);

                    let dot = wawona::linux::ui::color_dot(&tag.color_hex, 10);
                    row_box.append(&dot);

                    let name_lbl = gtk::Label::new(Some(&tag.name));
                    name_lbl.set_xalign(0.0);
                    name_lbl.set_hexpand(true);
                    name_lbl.add_css_class("heading");
                    row_box.append(&name_lbl);

                    let count = state
                        .borrow()
                        .tags
                        .tag_ids_by_machine
                        .values()
                        .filter(|ids| ids.contains(&tag.id))
                        .count();
                    if count > 0 {
                        let count_lbl = gtk::Label::new(Some(&count.to_string()));
                        count_lbl.add_css_class("dim-label");
                        count_lbl.add_css_class("caption");
                        row_box.append(&count_lbl);
                    }

                    row.set_child(Some(&row_box));
                    a11y::set_wwn_a11y(
                        &row,
                        &format!("wwn.sidebar.tag.{}", tag.id),
                        Some(&tag.name),
                    );

                    let right_click = gtk::GestureClick::new();
                    right_click.set_button(3);
                    let tag_c = tag.clone();
                    let state_c = state.clone();
                    let window_c = window.clone();
                    let on_rebuild_c = on_rebuild.clone();
                    let home_c = home.clone();
                    let row_c = row.clone();
                    right_click.connect_pressed(move |_, _, x, y| {
                        let popover = gtk::Popover::new();
                        let menu_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
                        menu_box.set_margin_start(4);
                        menu_box.set_margin_end(4);
                        menu_box.set_margin_top(4);
                        menu_box.set_margin_bottom(4);

                        let edit_btn = gtk::Button::with_label("Edit Tag...");
                        edit_btn.add_css_class("flat");
                        let tag_edit = tag_c.clone();
                        let state_edit = state_c.clone();
                        let window_edit = window_c.clone();
                        let on_rebuild_edit = on_rebuild_c.clone();
                        let pop_edit = popover.clone();
                        edit_btn.connect_clicked(move |_| {
                            pop_edit.popdown();
                            wawona::linux::ui::show_edit_tag_dialog(
                                &window_edit,
                                &tag_edit,
                                state_edit.clone(),
                                on_rebuild_edit.clone(),
                            );
                        });
                        menu_box.append(&edit_btn);

                        let del_btn = gtk::Button::with_label("Delete Tag");
                        del_btn.add_css_class("flat");
                        del_btn.add_css_class("destructive-action");
                        let tag_id_del = tag_c.id.clone();
                        let state_del = state_c.clone();
                        let home_del = home_c.clone();
                        let on_rebuild_del = on_rebuild_c.clone();
                        let pop_del = popover.clone();
                        del_btn.connect_clicked(move |_| {
                            pop_del.popdown();
                            {
                                let mut app = state_del.borrow_mut();
                                app.tags.delete_tag(&tag_id_del);
                                app.persist_tags();
                            }
                            if home_del.selected_tag_id.borrow().as_deref() == Some(&tag_id_del) {
                                home_del.selected_tag_id.replace(None);
                            }
                            on_rebuild_del();
                        });
                        menu_box.append(&del_btn);

                        popover.set_child(Some(&menu_box));
                        popover.set_parent(&row_c);
                        popover.connect_closed(|p| {
                            p.unparent();
                        });
                        let rect = gtk::gdk::Rectangle::new(x as i32, y as i32, 1, 1);
                        popover.set_pointing_to(Some(&rect));
                        popover.popup();
                    });
                    row.add_controller(right_click);

                    tags_list.append(&row);

                    if current_sel.as_deref() == Some(&tag.id) {
                        tags_list.select_row(Some(&row));
                    }
                }
                is_rebuilding_tags.set(false);
            })
        };

        match std::env::var("WAWONA_INITIAL_PAGE").as_deref() {
            Ok("tab_overview") => {
                sidebar_list.select_row(Some(&row_overview));
            }
            Ok("settings") => {
                open_settings();
            }
            Ok("work_status") => {
                sidebar_list.select_row(Some(&row_work_status));
            }
            _ => {
                sidebar_list.select_row(Some(&row_machines));
                content_stack.set_visible_child_name("machines");
            }
        }

        let open_editor = Rc::new({
            let window = window.clone();
            let state = state.clone();
            let home = home.clone();
            let sessions = machine_sessions.clone();
            let layout_binding = layout_binding.clone();
            let on_rebuild = on_rebuild.clone();
            move |existing: Option<wawona::linux::machine_profile::MachineProfile>| {
                show_editor(
                    &window,
                    &state,
                    existing,
                    MachineType::Native,
                    &home,
                    sessions.clone(),
                    layout_binding.get(),
                    Some(on_rebuild.clone()),
                );
            }
        });

        let open_terminal = Rc::new({
            let terminal_slot = terminal_slot.clone();
            let content_stack = content_stack.clone();
            let sidebar_list = sidebar_list.clone();
            let state = state.clone();
            let sessions = machine_sessions.clone();
            let on_rebuild = on_rebuild.clone();
            let active_terminal = active_terminal.clone();
            move |mid: String, launch: wawona::linux::ui::TerminalLaunch| {
                if active_terminal.borrow().as_deref() == Some(&mid)
                    && terminal_slot.first_child().is_some()
                {
                    let mut app = state.borrow_mut();
                    let _ = app.store.set_active(Some(mid.clone()));
                    drop(app);
                    content_stack.set_visible_child_name("terminal");
                    return;
                }

                let mname = {
                    let app = state.borrow();
                    app.store
                        .profile(&mid)
                        .map(|p| p.name.clone())
                        .unwrap_or_else(|| "Terminal".into())
                };

                match wawona::linux::ui::start_terminal(&launch) {
                    Ok((child, session, master)) => {
                        wlog!(
                            "UI",
                            "Started in-app terminal '{}' pid={}",
                            mname,
                            child.id()
                        );
                        let pid = child.id();
                        sessions.borrow_mut().insert(mid.clone(), child);
                        {
                            let mut app = state.borrow_mut();
                            let _ = app.store.set_active(Some(mid.clone()));
                        }
                        *active_terminal.borrow_mut() = Some(mid.clone());

                        let stack_c = content_stack.clone();
                        let side_c = sidebar_list.clone();
                        let on_rebuild_c = on_rebuild.clone();

                        let on_back = Rc::new({
                            let stack_c = stack_c.clone();
                            let side_c = side_c.clone();
                            let on_rebuild_c = on_rebuild_c.clone();
                            move || {
                                on_rebuild_c();
                                stack_c.set_visible_child_name("machines");
                                if let Some(r0) = side_c.row_at_index(0) {
                                    side_c.select_row(Some(&r0));
                                }
                            }
                        });

                        let on_stop = Rc::new({
                            let stack_c = stack_c.clone();
                            let side_c = side_c.clone();
                            let on_rebuild_c = on_rebuild_c.clone();
                            let sessions_c = sessions.clone();
                            let mid_c = mid.clone();
                            let active_term_c = active_terminal.clone();
                            move || {
                                *active_term_c.borrow_mut() = None;
                                if let Some(mut ch) = sessions_c.borrow_mut().remove(&mid_c) {
                                    let _ = ch.kill();
                                }
                                on_rebuild_c();
                                stack_c.set_visible_child_name("machines");
                                if let Some(r0) = side_c.row_at_index(0) {
                                    side_c.select_row(Some(&r0));
                                }
                            }
                        });

                        let term_view = wawona::linux::ui::build_terminal_view(
                            session,
                            master,
                            pid,
                            &mname,
                            wawona::linux::ui::launch_subtitle(&launch),
                            on_back,
                            on_stop,
                        );

                        while let Some(c) = terminal_slot.first_child() {
                            terminal_slot.remove(&c);
                        }
                        terminal_slot.append(&term_view);
                        content_stack.set_visible_child_name("terminal");
                        on_rebuild();
                    }
                    Err(e) => {
                        wlog!("UI", "Failed to start in-app terminal: {}", e);
                    }
                }
            }
        });

        {
            let home_c = home.clone();
            let state_c = state.clone();
            let window_c = window.clone();
            let sessions_c = machine_sessions.clone();
            let binding_c = layout_binding.clone();
            let open_editor_edit = open_editor.clone();
            let open_terminal_rebuild = open_terminal.clone();
            let rebuild_tags_c = rebuild_tags_list.clone();
            *rebuild_slot.borrow_mut() = Some(Rc::new(move || {
                rebuild_tags_c();
                let open_ed = open_editor_edit.clone();
                let open_term = open_terminal_rebuild.clone();
                rebuild_home(RebuildHome {
                    shell: &home_c,
                    state: &state_c,
                    parent: &window_c,
                    sessions: sessions_c.clone(),
                    layout: binding_c.get(),
                    on_edit: Some(Rc::new(move |profile| {
                        open_ed(Some(profile));
                    })),
                    on_open_terminal: Some(open_term),
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
            let state_for_thumb = state.clone();
            let last_thumb_ms = Rc::new(Cell::new(0i64));
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
                    if let BufferData::Shm {
                        pixels,
                        width,
                        height,
                        stride,
                        ..
                    } = wb.buffer.data
                    {
                        cs.buffer_cache.insert(
                            (sid, bid),
                            CachedBuffer {
                                pixels,
                                width,
                                height,
                                stride,
                            },
                        );
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
                                    "Fullscreen shell wid={} client={}. Embedding in primary host (no extra GtkWindow)",
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
                            wawona::wlog!(
                                "COMPOSITOR",
                                "Creating host window wid={} title='{}' decoration={:?} client={}",
                                wid,
                                config.title,
                                config.decoration_mode,
                                cid
                            );

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
                                client_win.connect_notify_local(
                                    Some("maximized"),
                                    move |win, _| {
                                        let w = da_m.width().max(1) as u32;
                                        let h = da_m.height().max(1) as u32;
                                        core_m.apply_host_window_maximized(
                                            WindowId { id: wid_m },
                                            win.is_maximized(),
                                            w,
                                            h,
                                        );
                                    },
                                );
                            }
                            {
                                let core_f = cs.core.clone();
                                let da_f = da.clone();
                                let wid_f = wid;
                                client_win.connect_notify_local(
                                    Some("fullscreened"),
                                    move |win, _| {
                                        let w = da_f.width().max(1) as u32;
                                        let h = da_f.height().max(1) as u32;
                                        core_f.apply_host_window_fullscreen(
                                            WindowId { id: wid_f },
                                            win.is_fullscreen(),
                                            w,
                                            h,
                                        );
                                    },
                                );
                            }

                            // Per-window resize → host + any fullscreen-shell companions (nested compositor output)
                            {
                                let comp_r = comp.clone();
                                da.connect_resize(move |_da, w, h| {
                                    let w = w as u32;
                                    let h = h as u32;
                                    wawona::wlog!(
                                        "COMPOSITOR",
                                        "Window {} resize {}x{}",
                                        wid,
                                        w,
                                        h
                                    );
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
                                    if bid == 0 {
                                        continue;
                                    }

                                    let Some(buf) = cs.buffer_cache.get(&(sid, bid)) else {
                                        continue;
                                    };

                                    let surf = cairo::ImageSurface::create_for_data(
                                        buf.pixels.clone(),
                                        cairo::Format::ARgb32,
                                        buf.width as i32,
                                        buf.height as i32,
                                        buf.stride as i32,
                                    );
                                    let Ok(surf) = surf else {
                                        continue;
                                    };

                                    let _ = cr.save();
                                    let (anchor_x, anchor_y) = if node.window_id.id != wid_for_draw
                                    {
                                        let (hx, hy) = host_anchor.unwrap_or((
                                            node.anchor_output_x,
                                            node.anchor_output_y,
                                        ));
                                        (hx as f64, hy as f64)
                                    } else {
                                        (node.anchor_output_x as f64, node.anchor_output_y as f64)
                                    };
                                    let local_x = node.x as f64 - anchor_x;
                                    let local_y = node.y as f64 - anchor_y;
                                    cr.translate(local_x, local_y);

                                    let cr_x = node.content_rect.x as f64;
                                    let cr_y = node.content_rect.y as f64;
                                    let cr_w = node.content_rect.w as f64;
                                    let cr_h = node.content_rect.h as f64;
                                    let has_crop = cr_w > 0.0
                                        && cr_h > 0.0
                                        && (cr_x > 0.001
                                            || cr_y > 0.001
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

                            let fills_host = config.fills_host;
                            client_win.present();
                            if !fills_host {
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
                            } else if config.width > 0 && config.height > 0 {
                                cs.last_dispatched_host_resizes
                                    .insert(wid, (config.width, config.height));
                            }
                            cs.client_windows.insert(
                                wid,
                                ClientWindow {
                                    gtk_window: client_win,
                                    drawing_area: da,
                                    window_id: wid,
                                    companion_window_ids,
                                    allow_host_close,
                                    client_side_decorated: is_csd,
                                    fills_host,
                                },
                            );
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
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "Destroying host GtkWindow wid={}",
                                    wid
                                );
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
                        WindowEvent::SizeChanged {
                            window_id,
                            width,
                            height,
                            cause,
                            ..
                        } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                if !(cw.fills_host && cause == WindowSizeCause::ClientCommit) {
                                    cw.gtk_window.set_default_size(width as i32, height as i32);
                                }
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
                                    // No newer host tick pending. Clear
                                    // xdg_toplevel.state.resizing with a settle
                                    // configure (even if size is unchanged).
                                    settle_interactive_resize(&mut cs, window_id.id, width, height);
                                }
                            }
                        }
                        WindowEvent::PopupCreated {
                            window_id,
                            parent_id,
                            x,
                            y,
                            width,
                            height,
                        } => {
                            // Composite the popup inside the host window that
                            // renders its parent (toplevel or another popup's
                            // host). Same mechanism as fullscreen-shell
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
                                window_id.id,
                                pid,
                                x,
                                y,
                                width,
                                height,
                                host_wid
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
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "Window {} decoration changed to {:?}",
                                    window_id.id,
                                    mode
                                );
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
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "MinimizeRequested wid={}",
                                    window_id.id
                                );
                                cw.gtk_window.minimize();
                            }
                        }
                        WindowEvent::MaximizeRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "MaximizeRequested wid={}",
                                    window_id.id
                                );
                                cw.gtk_window.maximize();
                            }
                        }
                        WindowEvent::UnmaximizeRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "UnmaximizeRequested wid={}",
                                    window_id.id
                                );
                                cw.gtk_window.unmaximize();
                            }
                        }
                        WindowEvent::FullscreenRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "FullscreenRequested wid={}",
                                    window_id.id
                                );
                                cw.gtk_window.fullscreen();
                            }
                        }
                        WindowEvent::UnfullscreenRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "UnfullscreenRequested wid={}",
                                    window_id.id
                                );
                                cw.gtk_window.unfullscreen();
                            }
                        }
                        WindowEvent::CloseRequested { window_id } => {
                            if let Some(cw) = cs.client_windows.get(&window_id.id) {
                                wawona::wlog!(
                                    "COMPOSITOR",
                                    "CloseRequested wid={} → host close",
                                    window_id.id
                                );
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
                        WindowEvent::SystemBell { surface_id } => {
                            wawona::wlog!(
                                "COMPOSITOR",
                                "SystemBell surface_id={} → gdk Display::beep",
                                surface_id
                            );
                            if let Some(display) = gtk::gdk::Display::default() {
                                display.beep();
                            }
                        }
                        _ => {}
                    }
                }

                // 5. Get render scene and trigger redraws
                let scene = cs.core.get_render_scene();
                let needs_redraw = scene.needs_redraw;
                cs.scene = Some(scene);
                maybe_save_wayland_thumbnail(&cs, &state_for_thumb, &last_thumb_ms);

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
            let open_editor_add = open_editor.clone();
            new_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Add Machine button pressed");
                open_editor_add(None);
            });

            let open_editor_bottom = open_editor.clone();
            bottom_add_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Bottom Add Machine button pressed");
                open_editor_bottom(None);
            });
        }

        {
            let open_settings_btn = open_settings.clone();
            settings_btn.connect_clicked(move |_| {
                wawona::wlog!("UI", "Settings button pressed");
                open_settings_btn();
            });
        }

        {
            let sidebar_list_c = sidebar_list.clone();
            let open_editor_c = open_editor.clone();
            let open_settings_key = open_settings.clone();
            let bottom_search_key = bottom_search.clone();
            let compact_search_key = compact_search.clone();
            let top_search_key = home.search.clone();
            let search_toggle_key = search_toggle_btn.clone();

            let key_ctrl = gtk::EventControllerKey::new();
            key_ctrl.connect_key_pressed(move |_, keyval, _, state| {
                let is_ctrl = state.contains(gtk::gdk::ModifierType::CONTROL_MASK);
                if is_ctrl {
                    match keyval {
                        gtk::gdk::Key::comma => {
                            open_settings_key();
                            return gtk::glib::Propagation::Stop;
                        }
                        gtk::gdk::Key::_1 => {
                            if let Some(r0) = sidebar_list_c.row_at_index(0) {
                                sidebar_list_c.select_row(Some(&r0));
                            }
                            return gtk::glib::Propagation::Stop;
                        }
                        gtk::gdk::Key::_2 => {
                            if let Some(r1) = sidebar_list_c.row_at_index(1) {
                                sidebar_list_c.select_row(Some(&r1));
                            }
                            return gtk::glib::Propagation::Stop;
                        }
                        gtk::gdk::Key::_3 => {
                            if let Some(r2) = sidebar_list_c.row_at_index(2) {
                                sidebar_list_c.select_row(Some(&r2));
                            }
                            return gtk::glib::Propagation::Stop;
                        }
                        gtk::gdk::Key::n => {
                            open_editor_c(None);
                            return gtk::glib::Propagation::Stop;
                        }
                        gtk::gdk::Key::f | gtk::gdk::Key::F => {
                            if is_touchscreen_active() {
                                bottom_search_key.grab_focus();
                            } else if search_toggle_key.is_visible() {
                                search_toggle_key.set_active(true);
                                compact_search_key.grab_focus();
                            } else {
                                top_search_key.grab_focus();
                            }
                            return gtk::glib::Propagation::Stop;
                        }
                        _ => {}
                    }
                }
                gtk::glib::Propagation::Proceed
            });
            window.add_controller(key_ctrl);
        }

        wawona::wlog!("UI", "Main window presented");
        window.present();
        maybe_show_welcome(&home, &state);
    }
}
#[cfg(feature = "linux-ui")]
fn main() {
    app::run();
}

#[cfg(not(feature = "linux-ui"))]
fn main() {
    eprintln!("wawona-linux-ui requires --features linux-ui");
}
