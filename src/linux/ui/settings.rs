//! Settings dialog with full parity to Apple and Android Global Settings.

use std::cell::RefCell;
use std::rc::Rc;

use gtk4 as gtk;
use gtk4::{gdk, gio, glib};
use libadwaita as adw;

use adw::prelude::*;
use gtk::prelude::*;

use crate::ffi::api::{build_number, version};
use crate::linux::runtime;
use crate::linux::service;
use crate::linux::ui::modal_sheet::present_sheet;
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;
use crate::wlog;

struct SettingsSectionMeta {
    name: &'static str,
    icon: &'static str,
    css_class: &'static str,
    a11y_id: &'static str,
}

const SETTINGS_SECTIONS: &[SettingsSectionMeta] = &[
    SettingsSectionMeta {
        name: "Display",
        icon: "display-brightness-symbolic",
        css_class: "wwn-icon-blue",
        a11y_id: "wwn.settings.display",
    },
    SettingsSectionMeta {
        name: "Input",
        icon: "caps-lock-symbolic",
        css_class: "wwn-icon-purple",
        a11y_id: "wwn.settings.input",
    },
    SettingsSectionMeta {
        name: "Graphics",
        icon: "color-select-symbolic",
        css_class: "wwn-icon-red",
        a11y_id: "wwn.settings.graphics",
    },
    SettingsSectionMeta {
        name: "Env Vars",
        icon: "text-x-generic-symbolic",
        css_class: "wwn-icon-teal",
        a11y_id: "wwn.settings.environment",
    },
    SettingsSectionMeta {
        name: "Waypipe",
        icon: "network-workgroup-symbolic",
        css_class: "wwn-icon-blue",
        a11y_id: "wwn.settings.waypipe",
    },
    SettingsSectionMeta {
        name: "SSH",
        icon: "dialog-password-symbolic",
        css_class: "wwn-icon-slate",
        a11y_id: "wwn.settings.ssh",
    },
    SettingsSectionMeta {
        name: "About",
        icon: "dialog-information-symbolic",
        css_class: "wwn-icon-purple",
        a11y_id: "wwn.settings.about",
    },
    SettingsSectionMeta {
        name: "Dependencies",
        icon: "application-x-executable-symbolic",
        css_class: "wwn-icon-brown",
        a11y_id: "wwn.settings.dependencies",
    },
    SettingsSectionMeta {
        name: "Launch Agent",
        icon: "system-run-symbolic",
        css_class: "wwn-icon-slate",
        a11y_id: "wwn.settings.launchagent",
    },
    SettingsSectionMeta {
        name: "Diagnostics",
        icon: "process-working-symbolic",
        css_class: "wwn-icon-orange",
        a11y_id: "wwn.settings.diagnostics",
    },
];

pub fn build_settings_view(state: &SharedAppState, on_done: Rc<dyn Fn()>) -> gtk::Box {
    let (body, _) = build_settings_view_internal(state, on_done);
    body
}

pub fn build_settings_view_internal(
    state: &SharedAppState,
    on_done: Rc<dyn Fn()>,
) -> (gtk::Box, adw::OverlaySplitView) {
    wlog!("UI", "Building settings view");
    ensure_settings_css();

    let split_view = adw::OverlaySplitView::new();
    split_view.set_min_sidebar_width(200.0);
    split_view.set_max_sidebar_width(280.0);
    split_view.set_sidebar_width_fraction(0.28);
    split_view.set_enable_show_gesture(true);
    split_view.set_enable_hide_gesture(true);
    split_view.set_show_sidebar(true);
    split_view.set_hexpand(true);
    split_view.set_vexpand(true);

    let header = adw::HeaderBar::new();
    header.set_show_end_title_buttons(false);
    header.set_show_start_title_buttons(false);

    let toggle_sidebar_btn = gtk::Button::from_icon_name("sidebar-show-symbolic");
    toggle_sidebar_btn.set_tooltip_text(Some("Toggle Sidebar"));
    let split_view_toggle = split_view.clone();
    toggle_sidebar_btn.connect_clicked(move |_| {
        let shows = split_view_toggle.shows_sidebar();
        split_view_toggle.set_show_sidebar(!shows);
    });
    header.pack_start(&toggle_sidebar_btn);

    let title_lbl = gtk::Label::new(Some("Settings"));
    title_lbl.add_css_class("title");
    header.set_title_widget(Some(&title_lbl));

    let done_btn = gtk::Button::from_icon_name("object-select-symbolic");
    done_btn.add_css_class("suggested-action");
    done_btn.set_tooltip_text(Some("Done"));
    crate::linux::ui::a11y::set_wwn_a11y(
        &done_btn,
        crate::linux::ui::a11y::id::SETTINGS_DONE,
        Some("Done"),
    );
    header.pack_end(&done_btn);

    let sidebar = gtk::ListBox::new();
    sidebar.set_selection_mode(gtk::SelectionMode::Single);
    sidebar.add_css_class("navigation-sidebar");
    sidebar.set_size_request(180, -1);
    crate::linux::ui::a11y::set_wwn_a11y(
        &sidebar,
        crate::linux::ui::a11y::id::SETTINGS_ROOT,
        Some("Settings"),
    );

    for meta in SETTINGS_SECTIONS {
        let row = gtk::ListBoxRow::new();
        let row_box = gtk::Box::new(gtk::Orientation::Horizontal, 10);
        row_box.set_margin_start(10);
        row_box.set_margin_end(10);
        row_box.set_margin_top(6);
        row_box.set_margin_bottom(6);

        let icon = gtk::Image::from_icon_name(meta.icon);
        icon.set_pixel_size(18);
        icon.add_css_class(meta.css_class);
        row_box.append(&icon);

        let label = gtk::Label::new(Some(meta.name));
        label.set_xalign(0.0);
        label.set_hexpand(true);
        row_box.append(&label);

        row.set_child(Some(&row_box));
        crate::linux::ui::a11y::set_wwn_a11y(&row, meta.a11y_id, Some(meta.name));
        sidebar.append(&row);
    }

    let stack = gtk::Stack::new();
    stack.set_hexpand(true);
    stack.set_vexpand(true);

    let cfg = state.borrow();
    let settings = &cfg.settings;

    let renderer_value = Rc::new(RefCell::new(settings.renderer.clone()));
    let compositor_backend_value = Rc::new(RefCell::new(settings.compositor_backend.clone()));
    let vulkan_driver_value = Rc::new(RefCell::new(settings.vulkan_driver.clone()));
    let opengl_driver_value = Rc::new(RefCell::new(settings.opengl_driver.clone()));
    let ssh_auth_method_value = Rc::new(RefCell::new(settings.ssh_auth_method.clone()));
    let ssh_key_type_value = Rc::new(RefCell::new(settings.ssh_key_type.clone()));
    let wp_compress_value = Rc::new(RefCell::new(settings.waypipe_compression.clone()));
    let wp_video_value = Rc::new(RefCell::new(settings.waypipe_video.clone()));
    let wp_video_enc_value = Rc::new(RefCell::new(settings.waypipe_video_encoding.clone()));
    let wp_video_dec_value = Rc::new(RefCell::new(settings.waypipe_video_decoding.clone()));
    let log_level_value = Rc::new(RefCell::new(settings.log_level.clone()));
    let start_behavior_value = Rc::new(RefCell::new(settings.start_behavior.clone()));

    // MARK: Display
    let display_page = adw::PreferencesPage::new();
    let display_group = adw::PreferencesGroup::new();
    display_group.set_title("Display");
    display_group.set_description(Some(
        "Nested compositor presentation, color management, and window decorations.",
    ));
    let color_ops = add_switch_row(&display_group, "Color Operations / HDR", settings.color_operations);
    add_combo_row(
        &display_group,
        "Display Backend",
        &["auto", "wayland", "drm"],
        &settings.compositor_backend,
        compositor_backend_value.clone(),
    );
    let nested_compositors_switch = add_switch_row(
        &display_group,
        "Nested Compositors",
        settings.nested_compositors,
    );
    let multiple_clients_switch = add_switch_row(
        &display_group,
        "Multiple Clients",
        settings.multiple_clients,
    );
    add_named_combo_row(
        &display_group,
        "Default Start Type",
        &[("prompt", "Prompt"), ("newTab", "New Tab"), ("newWindow", "New Window")],
        &settings.start_behavior,
        start_behavior_value.clone(),
    );
    display_page.add(&display_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &display_page,
        crate::linux::ui::a11y::id::SETTINGS_DISPLAY,
        Some("Display"),
    );
    stack.add_named(&display_page, Some("Display"));

    // MARK: Input
    let input_page = adw::PreferencesPage::new();
    let input_group = adw::PreferencesGroup::new();
    input_group.set_title("Input");
    input_group.set_description(Some(
        "Keyboard repeat rates, cursor visibility, and clipboard synchronization.",
    ));
    let input_profile = add_entry_row(&input_group, "Default Input Profile", &settings.input_profile);
    let key_repeat = add_spin_row(&input_group, "Key Repeat", settings.key_repeat as f64, 1.0, 60.0, 1.0);
    let virtual_cursor_switch = add_switch_row(&input_group, "Show Virtual Cursor", settings.show_virtual_cursor);
    let universal_clipboard_switch = add_switch_row(
        &input_group,
        "Universal Clipboard",
        settings.universal_clipboard,
    );
    input_page.add(&input_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &input_page,
        crate::linux::ui::a11y::id::SETTINGS_INPUT,
        Some("Input"),
    );
    stack.add_named(&input_page, Some("Input"));

    // MARK: Graphics
    let graphics_page = adw::PreferencesPage::new();
    let graphics_group = adw::PreferencesGroup::new();
    graphics_group.set_title("Graphics");
    graphics_group.set_description(Some(
        "Rendering subsystem, hardware acceleration drivers, and session thumbnails.",
    ));
    add_combo_row(
        &graphics_group,
        "Renderer",
        &["vulkan", "software"],
        &settings.renderer,
        renderer_value.clone(),
    );
    let linux_vk_drivers = crate::domain::settings_catalog::allowed_vulkan_drivers(
        crate::domain::settings_catalog::SettingsHost::Linux,
    );
    add_combo_row(
        &graphics_group,
        "Vulkan Driver",
        linux_vk_drivers,
        &settings.vulkan_driver,
        vulkan_driver_value.clone(),
    );
    let linux_gl_drivers = crate::domain::settings_catalog::allowed_opengl_drivers(
        crate::domain::settings_catalog::SettingsHost::Linux,
    );
    add_combo_row(
        &graphics_group,
        "OpenGL Driver",
        linux_gl_drivers,
        &settings.opengl_driver,
        opengl_driver_value.clone(),
    );
    let session_thumbnails_switch = add_switch_row(
        &graphics_group,
        "Session Thumbnails",
        settings.session_thumbnails,
    );
    graphics_page.add(&graphics_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &graphics_page,
        crate::linux::ui::a11y::id::SETTINGS_GRAPHICS,
        Some("Graphics"),
    );
    stack.add_named(&graphics_page, Some("Graphics"));

    // MARK: Environment Variables
    let env_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    env_box.set_hexpand(true);
    env_box.set_vexpand(true);

    let conn_pref_page = adw::PreferencesPage::new();
    let conn_group = adw::PreferencesGroup::new();
    conn_group.set_title("Compositor Endpoint");
    conn_group.set_description(Some(
        "Wayland socket endpoint and TCP network listener port.",
    ));
    let wayland_display = add_entry_row(&conn_group, "Wayland Display", &settings.wayland_display);
    let tcp_port = add_spin_row(&conn_group, "TCP Listener Port", settings.tcp_port as f64, 1024.0, 65535.0, 1.0);
    conn_pref_page.add(&conn_group);
    env_box.append(&conn_pref_page);

    let env_overrides_cell = Rc::new(RefCell::new(settings.environment_overrides.clone()));
    let env_unsets_cell = Rc::new(RefCell::new(settings.environment_unsets.clone()));

    let env_manager_view = crate::linux::ui::env_vars::build_env_vars_view(
        env_overrides_cell.clone(),
        env_unsets_cell.clone(),
        settings,
    );
    env_box.append(&env_manager_view);

    crate::linux::ui::a11y::set_wwn_a11y(
        &env_box,
        crate::linux::ui::a11y::id::SETTINGS_ENVIRONMENT,
        Some("Env Vars"),
    );
    stack.add_named(&env_box, Some("Env Vars"));

    // MARK: Waypipe
    let waypipe_page = adw::PreferencesPage::new();
    let waypipe_group = adw::PreferencesGroup::new();
    waypipe_group.set_title("Waypipe Parameters");
    waypipe_group.set_description(Some(
        "Wayland protocol proxy configuration for remote streaming over SSH or unix sockets.",
    ));
    let wp_enabled = add_switch_row(&waypipe_group, "Default Waypipe Enabled", settings.waypipe_enabled);
    let wp_display = add_spin_row(&waypipe_group, "Display Number", settings.waypipe_display as f64, 0.0, 99.0, 1.0);
    let wp_socket = add_entry_row(&waypipe_group, "Socket Path", &settings.waypipe_socket);
    add_combo_row(
        &waypipe_group,
        "Compression",
        &["lz4", "zstd", "none"],
        &settings.waypipe_compression,
        wp_compress_value.clone(),
    );
    let wp_compress_level = add_spin_row(&waypipe_group, "Compression Level", settings.waypipe_compress_level as f64, 1.0, 22.0, 1.0);
    let wp_threads = add_spin_row(&waypipe_group, "Worker Threads", settings.waypipe_threads as f64, 0.0, 32.0, 1.0);
    add_combo_row(
        &waypipe_group,
        "Video Compression",
        &["none", "h264", "vp9", "av1"],
        &settings.waypipe_video,
        wp_video_value.clone(),
    );
    add_combo_row(
        &waypipe_group,
        "Video Encoding",
        &["hw", "sw", "hwenc", "swenc"],
        &settings.waypipe_video_encoding,
        wp_video_enc_value.clone(),
    );
    add_combo_row(
        &waypipe_group,
        "Video Decoding",
        &["hw", "sw", "hwdec", "swdec"],
        &settings.waypipe_video_decoding,
        wp_video_dec_value.clone(),
    );
    let wp_video_bpf = add_entry_row(&waypipe_group, "Bits Per Frame", &settings.waypipe_video_bpf);
    let wp_remote_cmd = add_entry_row(&waypipe_group, "Remote Command", &settings.waypipe_remote_command);
    let wp_title_prefix = add_entry_row(&waypipe_group, "Title Prefix", &settings.waypipe_title_prefix);
    let wp_no_gpu = add_switch_row(&waypipe_group, "Disable GPU (Force SHM)", settings.waypipe_no_gpu);
    let wp_oneshot = add_switch_row(&waypipe_group, "One-shot Exit", settings.waypipe_oneshot);
    let wp_unlink_socket = add_switch_row(&waypipe_group, "Unlink Socket on Exit", settings.waypipe_unlink_socket);
    let wp_login_shell = add_switch_row(&waypipe_group, "Login Shell", settings.waypipe_login_shell);
    let wp_debug = add_switch_row(&waypipe_group, "Debug Mode", settings.waypipe_debug);
    waypipe_page.add(&waypipe_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &waypipe_page,
        crate::linux::ui::a11y::id::SETTINGS_WAYPIPE,
        Some("Waypipe"),
    );
    stack.add_named(&waypipe_page, Some("Waypipe"));

    // MARK: SSH
    let ssh_page = adw::PreferencesPage::new();
    let ssh_group = adw::PreferencesGroup::new();
    ssh_group.set_title("SSH Connection");
    ssh_group.set_description(Some(
        "Remote SSH server credentials and public key authentication details.",
    ));
    let ssh_host = add_entry_row(&ssh_group, "Host", &settings.ssh_host);
    let ssh_user = add_entry_row(&ssh_group, "User", &settings.ssh_user);
    let ssh_port = add_spin_row(&ssh_group, "Port", settings.ssh_port as f64, 1.0, 65535.0, 1.0);
    add_combo_row(
        &ssh_group,
        "Auth Method",
        &["public_key", "password"],
        &settings.ssh_auth_method,
        ssh_auth_method_value.clone(),
    );
    let ssh_password = add_password_row(&ssh_group, "Password", &settings.ssh_password);
    let ssh_key_path = add_entry_row(&ssh_group, "Key Path", &settings.ssh_key_path);
    let ssh_key_passphrase = add_password_row(&ssh_group, "Key Passphrase", &settings.ssh_key_passphrase);
    add_combo_row(
        &ssh_group,
        "Key Type",
        &["ed25519", "ecdsa", "rsa"],
        &settings.ssh_key_type,
        ssh_key_type_value.clone(),
    );

    let ssh_status_lbl = gtk::Label::new(None);
    ssh_status_lbl.set_wrap(true);
    ssh_status_lbl.set_xalign(0.0);
    ssh_status_lbl.add_css_class("dim-label");

    let generate_key_btn = gtk::Button::with_label("Generate Key");
    {
        let key_type_val = ssh_key_type_value.clone();
        let key_path_ent = ssh_key_path.clone();
        let key_pass_ent = ssh_key_passphrase.clone();
        let status_lbl = ssh_status_lbl.clone();
        generate_key_btn.connect_clicked(move |_| {
            let kt = key_type_val.borrow().clone();
            let kp = key_path_ent.text().to_string();
            let pass = key_pass_ent.text().to_string();
            match linux_generate_ssh_key(&kt, &kp, &pass) {
                Ok(msg) => status_lbl.set_text(&msg),
                Err(err) => status_lbl.set_text(&err),
            }
        });
    }
    add_row(&ssh_group, "Generate Key", &generate_key_btn);

    let test_ssh_btn = gtk::Button::with_label("Test Connection");
    {
        let host_ent = ssh_host.clone();
        let user_ent = ssh_user.clone();
        let port_spin = ssh_port.clone();
        let status_lbl = ssh_status_lbl.clone();
        test_ssh_btn.connect_clicked(move |_| {
            let h = host_ent.text().to_string();
            let u = user_ent.text().to_string();
            let p = port_spin.value() as u16;
            match linux_test_ssh_connection(&h, &u, p) {
                Ok(msg) => status_lbl.set_text(&msg),
                Err(err) => status_lbl.set_text(&err),
            }
        });
    }
    add_row(&ssh_group, "Test Connection", &test_ssh_btn);
    ssh_group.add(&ssh_status_lbl);
    ssh_page.add(&ssh_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &ssh_page,
        crate::linux::ui::a11y::id::SETTINGS_SSH,
        Some("SSH"),
    );
    stack.add_named(&ssh_page, Some("SSH"));

    // MARK: Dependencies
    let deps_page = adw::PreferencesPage::new();
    let deps_group = adw::PreferencesGroup::new();
    deps_group.set_title("Bundled Dependencies");
    deps_group.set_description(Some(
        "Packages linked into this Linux UI build. Not another platform's list.",
    ));
    let deps_json = include_str!("settings_dependencies.json");
    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(deps_json) {
        if let Some(packages) = parsed.get("packages").and_then(|p| p.as_array()) {
            for pkg in packages {
                let name = pkg
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Package");
                let version = pkg.get("version").and_then(|v| v.as_str()).unwrap_or("");
                let role = pkg.get("role").and_then(|v| v.as_str()).unwrap_or("");
                let license = pkg.get("license").and_then(|v| v.as_str()).unwrap_or("");
                let url = pkg.get("url").and_then(|v| v.as_str()).unwrap_or("");
                add_dependency_row(&deps_group, name, version, role, license, url);
            }
        }
    }
    // MARK: About
    let about_page = adw::PreferencesPage::new();

    let banner = adw::PreferencesGroup::new();
    let mark = adw::ActionRow::new();
    mark.set_title("Wawona");
    mark.set_subtitle(&format!("v{}", version()));
    let icon_frame = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    icon_frame.set_overflow(gtk::Overflow::Hidden);
    icon_frame.set_size_request(64, 64);
    icon_frame.add_css_class("wwn-about-icon-frame");
    let icon = gtk::Image::new();
    icon.set_pixel_size(64);
    if let Some(bytes) = bundled_about_png("WawonaAbout.png") {
        set_rounded_favicon(&icon, bytes, 64, 14.0);
    }
    icon_frame.append(&icon);
    mark.add_prefix(&icon_frame);
    banner.add(&mark);
    about_page.add(&banner);

    let links = adw::PreferencesGroup::new();
    for (title, subtitle, url, icon) in WAWN_ABOUT_LINKS {
        add_about_link_row(&links, title, subtitle, url, icon);
    }
    about_page.add(&links);

    let facts = adw::PreferencesGroup::new();
    add_info_row(&facts, "Version", &format!("v{}", version()));
    add_info_row(&facts, "Build", &build_number());
    add_info_row(&facts, "Platform", "Linux");
    add_combo_row(
        &facts,
        "Log Level",
        &["debug", "info", "warn", "error"],
        &settings.log_level,
        log_level_value.clone(),
    );
    let copy_logs = gtk::Button::with_label("Copy Logs");
    crate::linux::ui::a11y::set_wwn_a11y(
        &copy_logs,
        crate::linux::ui::a11y::id::SETTINGS_COPY_LOGS,
        Some("Copy Logs"),
    );
    let report_bug = gtk::Button::with_label("Report a Bug on GitHub");
    report_bug.add_css_class("suggested-action");
    crate::linux::ui::a11y::set_wwn_a11y(
        &report_bug,
        crate::linux::ui::a11y::id::SETTINGS_REPORT_BUG,
        Some("Report a Bug on GitHub"),
    );
    add_row(&facts, "Diagnostics", &copy_logs);
    add_row(&facts, "GitHub", &report_bug);
    copy_logs.connect_clicked(|_| {
        linux_copy_bug_diagnostics();
    });
    report_bug.connect_clicked(|_| {
        linux_open_github_bug_report();
    });
    about_page.add(&facts);
    stack.add_named(&about_page, Some("About"));

    deps_page.add(&deps_group);
    stack.add_named(&deps_page, Some("Dependencies"));

    // MARK: Launch Agent
    let agent_page = adw::PreferencesPage::new();
    let agent_group = adw::PreferencesGroup::new();
    agent_group.set_title("Launch Agent and Runtime");
    let install_btn = gtk::Button::with_label("Install systemd user units + autostart");
    let uninstall_btn = gtk::Button::with_label("Uninstall systemd units + autostart");
    let start_host_btn = gtk::Button::with_label("Start compositor host service");
    let restart_host_btn = gtk::Button::with_label("Restart compositor host service");
    let stop_host_btn = gtk::Button::with_label("Stop compositor host service");
    let start_tray_btn = gtk::Button::with_label("Start tray applet service");
    let stop_tray_btn = gtk::Button::with_label("Stop tray applet service");
    for (t, b) in [
        ("Install", &install_btn),
        ("Uninstall", &uninstall_btn),
        ("Host Start", &start_host_btn),
        ("Host Restart", &restart_host_btn),
        ("Host Stop", &stop_host_btn),
        ("Tray Start", &start_tray_btn),
        ("Tray Stop", &stop_tray_btn),
    ] {
        add_row(&agent_group, t, b);
    }
    install_btn.connect_clicked(|_| {
        let _ = service::install_user_units();
    });
    uninstall_btn.connect_clicked(|_| {
        let _ = service::uninstall_user_units();
    });
    start_host_btn.connect_clicked(|_| {
        let _ = service::start_compositor_service();
    });
    restart_host_btn.connect_clicked(|_| {
        let _ = service::restart_compositor_service();
    });
    stop_host_btn.connect_clicked(|_| {
        let _ = service::stop_compositor_service();
    });
    start_tray_btn.connect_clicked(|_| {
        let _ = service::start_tray_service();
    });
    stop_tray_btn.connect_clicked(|_| {
        let _ = service::stop_tray_service();
    });
    agent_page.add(&agent_group);
    stack.add_named(&agent_page, Some("Launch Agent"));

    // MARK: Diagnostics
    let diag_page = adw::PreferencesPage::new();
    let diag_group = adw::PreferencesGroup::new();
    diag_group.set_title("Runtime Diagnostics");
    add_info_row(
        &diag_group,
        "Runtime State",
        &match runtime::read_runtime_state() {
            Ok(rt) => format!(
                "healthy={} display={} socket={}",
                rt.healthy, rt.wayland_display, rt.socket_path
            ),
            Err(_) => "No runtime state available".to_string(),
        },
    );
    add_info_row(&diag_group, "Host OS", &linux_host_os());
    add_info_row(&diag_group, "CPU", &linux_cpu_info());
    add_info_row(&diag_group, "GPU Driver", &linux_gpu_driver());
    add_info_row(
        &diag_group,
        "XDG_RUNTIME_DIR",
        &std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "(unset)".into()),
    );
    add_info_row(
        &diag_group,
        "KVM Hypervisor",
        if std::path::Path::new("/dev/kvm").exists() {
            "Available (/dev/kvm accessible)"
        } else {
            "Unavailable (/dev/kvm missing)"
        },
    );
    diag_page.add(&diag_group);

    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machines and Containers");
    vm_group.set_description(Some(
        "KVM hypervisor and OCI container parameters for Relay Linux guests.",
    ));
    add_info_row(
        &vm_group,
        "Virtual Machine Engine",
        "Wawona Relay (KVM via cloud-hypervisor or crosvm). Fail closed without /dev/kvm.",
    );
    let vm_vsock_port = add_spin_row(
        &vm_group,
        "VSock Port",
        settings.vm_vsock_port as f64,
        1024.0,
        65535.0,
        1.0,
    );
    add_info_row(
        &vm_group,
        "Container Runtime",
        "OCI-in-VM. Containers unpack OCI images, then run on the same Relay KVM VM.",
    );
    let container_image_store =
        add_entry_row(&vm_group, "Container Image Store", &settings.container_image_store);
    diag_page.add(&vm_group);
    stack.add_named(&diag_page, Some("Diagnostics"));

    drop(cfg);

    let sidebar_scroll = gtk::ScrolledWindow::new();
    sidebar_scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
    sidebar_scroll.set_child(Some(&sidebar));

    split_view.set_sidebar(Some(&sidebar_scroll));
    split_view.set_content(Some(&stack));

    {
        let stack = stack.clone();
        let split_view_c = split_view.clone();
        sidebar.connect_row_selected(move |_, row| {
            if let Some(row) = row {
                let idx = row.index() as usize;
                if idx < SETTINGS_SECTIONS.len() {
                    stack.set_visible_child_name(SETTINGS_SECTIONS[idx].name);
                    if split_view_c.is_collapsed() {
                        split_view_c.set_show_sidebar(false);
                    }
                }
            }
        });
    }
    let initial_section_idx = std::env::var("WAWONA_SETTINGS_SECTION")
        .ok()
        .and_then(|name| {
            SETTINGS_SECTIONS
                .iter()
                .position(|s| s.name.eq_ignore_ascii_case(&name))
        })
        .unwrap_or(0) as i32;
    if let Some(initial_row) = sidebar.row_at_index(initial_section_idx) {
        sidebar.select_row(Some(&initial_row));
        stack.set_visible_child_name(SETTINGS_SECTIONS[initial_section_idx as usize].name);
    }

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.append(&header);
    body.append(&split_view);

    let st = state.clone();
    let on_done_c = on_done.clone();
    done_btn.connect_clicked(move |_| {
        let mut app = st.borrow_mut();
        app.settings.wayland_display = wayland_display.text().to_string();
        app.settings.auto_scale = true;
        app.settings.compositor_backend = compositor_backend_value.borrow().clone();
        app.settings.nested_compositors = nested_compositors_switch.is_active();
        app.settings.multiple_clients = multiple_clients_switch.is_active();
        app.settings.input_profile = input_profile.text().to_string();
        app.settings.key_repeat = key_repeat.value() as u32;
        app.settings.touch_pointer_emulation = false;
        app.settings.show_virtual_cursor = virtual_cursor_switch.is_active();
        app.settings.universal_clipboard = universal_clipboard_switch.is_active();
        app.settings.renderer = renderer_value.borrow().clone();
        app.settings.force_ssd = true;
        app.settings.color_operations = color_ops.is_active();
        app.settings.vulkan_driver = crate::domain::settings_catalog::sanitize_vulkan_driver(
            crate::domain::settings_catalog::SettingsHost::Linux,
            &vulkan_driver_value.borrow(),
        )
        .to_string();
        app.settings.opengl_driver = crate::domain::settings_catalog::sanitize_opengl_driver(
            crate::domain::settings_catalog::SettingsHost::Linux,
            &opengl_driver_value.borrow(),
        )
        .to_string();
        app.settings.dmabuf_enabled = true;
        app.settings.tcp_port = tcp_port.value() as u16;
        app.settings.ssh_host = ssh_host.text().to_string();
        app.settings.ssh_user = ssh_user.text().to_string();
        app.settings.ssh_port = ssh_port.value() as u16;
        app.settings.ssh_password = ssh_password.text().to_string();
        app.settings.ssh_auth_method = ssh_auth_method_value.borrow().clone();
        app.settings.ssh_key_path = ssh_key_path.text().to_string();
        app.settings.ssh_key_passphrase = ssh_key_passphrase.text().to_string();
        app.settings.ssh_key_type = ssh_key_type_value.borrow().clone();
        app.settings.session_thumbnails = session_thumbnails_switch.is_active();
        app.settings.shake_to_close = false;
        app.settings.swipe_back_to_close = false;
        app.settings.start_behavior = start_behavior_value.borrow().clone();
        app.settings.vm_vsock_port = vm_vsock_port.value() as u32;
        app.settings.container_image_store = container_image_store.text().to_string();
        app.settings.waypipe_compression = wp_compress_value.borrow().clone();
        app.settings.waypipe_video = wp_video_value.borrow().clone();
        app.settings.waypipe_video_encoding = wp_video_enc_value.borrow().clone();
        app.settings.waypipe_video_decoding = wp_video_dec_value.borrow().clone();
        app.settings.waypipe_video_bpf = wp_video_bpf.text().to_string();
        app.settings.waypipe_no_gpu = wp_no_gpu.is_active();
        app.settings.waypipe_oneshot = wp_oneshot.is_active();
        app.settings.waypipe_unlink_socket = wp_unlink_socket.is_active();
        app.settings.waypipe_login_shell = wp_login_shell.is_active();
        app.settings.waypipe_title_prefix = wp_title_prefix.text().to_string();
        app.settings.waypipe_remote_command = wp_remote_cmd.text().to_string();
        app.settings.waypipe_debug = wp_debug.is_active();
        app.settings.waypipe_enabled = wp_enabled.is_active();
        app.settings.waypipe_display = wp_display.value() as u32;
        app.settings.waypipe_socket = wp_socket.text().to_string();
        app.settings.waypipe_compress_level = wp_compress_level.value() as u32;
        app.settings.waypipe_threads = wp_threads.value() as u32;
        app.settings.log_level = log_level_value.borrow().clone();
        app.settings.environment_overrides = env_overrides_cell.borrow().clone();
        app.settings.environment_unsets = env_unsets_cell.borrow().clone();
        app.persist_settings();
        wlog!("UI", "Settings saved");
        drop(app);
        on_done_c();
    });

    (body, split_view)
}

pub fn show_settings(parent: &adw::ApplicationWindow, state: &SharedAppState, layout: LayoutMode) {
    let dialog_holder: Rc<RefCell<Option<adw::Window>>> = Rc::new(RefCell::new(None));
    let dh = dialog_holder.clone();
    let (body, split_view) = build_settings_view_internal(
        state,
        Rc::new(move || {
            if let Some(d) = dh.borrow().as_ref() {
                d.close();
            }
        }),
    );
    let dialog = present_sheet(parent, "Settings", &body, layout);

    if let Ok(cond) = adw::BreakpointCondition::parse("max-width: 760px") {
        let bp = adw::Breakpoint::new(cond);
        bp.add_setter(&split_view, "collapsed", Some(&true.to_value()));
        bp.add_setter(&split_view, "show-sidebar", Some(&false.to_value()));
        dialog.add_breakpoint(bp);
    }
    if layout.is_compact() {
        split_view.set_collapsed(true);
        split_view.set_show_sidebar(true);
    }

    *dialog_holder.borrow_mut() = Some(dialog);
}

fn linux_host_os() -> String {
    if let Ok(text) = std::fs::read_to_string("/etc/os-release") {
        for line in text.lines() {
            if let Some(val) = line.strip_prefix("PRETTY_NAME=") {
                return val.trim_matches('"').to_string();
            }
        }
    }
    "Linux".to_string()
}

fn linux_cpu_info() -> String {
    if let Ok(text) = std::fs::read_to_string("/proc/cpuinfo") {
        for line in text.lines() {
            if let Some(val) = line.strip_prefix("model name\t: ") {
                return val.to_string();
            }
        }
    }
    "Unknown CPU".to_string()
}

fn linux_gpu_driver() -> String {
    if let Ok(out) = std::process::Command::new("lspci").output() {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            if line.contains("VGA") || line.contains("3D") {
                return line.to_string();
            }
        }
    }
    "DRM / Mesa".to_string()
}

fn linux_copy_bug_diagnostics() {
    let mut diag = format!("Wawona Linux UI Diagnostics\nVersion: {}\nBuild: {}\nOS: {}\nCPU: {}\nGPU: {}\n",
        version(), build_number(), linux_host_os(), linux_cpu_info(), linux_gpu_driver());
    if let Ok(rt) = runtime::read_runtime_state() {
        diag.push_str(&format!("Runtime: healthy={} display={} socket={}\n", rt.healthy, rt.wayland_display, rt.socket_path));
    }
    if let Some(display) = gtk::gdk::Display::default() {
        display.clipboard().set_text(&diag);
    }
}

fn linux_open_github_bug_report() {
    linux_open_url("https://github.com/Wawona/Wawona/issues/new");
}

fn linux_open_url(url: &str) {
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn linux_generate_ssh_key(key_type: &str, path: &str, passphrase: &str) -> Result<String, String> {
    let path = if path.is_empty() {
        let home = std::env::var("HOME").map_err(|e| e.to_string())?;
        format!("{home}/.ssh/id_{key_type}")
    } else {
        path.to_string()
    };
    if std::path::Path::new(&path).exists() {
        return Err(format!("Key file already exists at {path}"));
    }
    let status = std::process::Command::new("ssh-keygen")
        .args(["-t", key_type, "-f", &path, "-N", passphrase, "-C", "wawona-linux"])
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(format!("Generated {key_type} key at {path}"))
    } else {
        Err("ssh-keygen command failed".to_string())
    }
}

fn linux_test_ssh_connection(host: &str, user: &str, port: u16) -> Result<String, String> {
    if host.is_empty() {
        return Err("Host cannot be empty".to_string());
    }
    let target = if user.is_empty() {
        host.to_string()
    } else {
        format!("{user}@{host}")
    };
    let out = std::process::Command::new("ssh")
        .args(["-p", &port.to_string(), "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", &target, "echo ok"])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok("SSH connection succeeded".to_string())
    } else {
        Err(format!("SSH connection failed: {}", String::from_utf8_lossy(&out.stderr)))
    }
}

const WAWN_ABOUT_LINKS: &[(&str, &str, &str, &str)] = &[
    (
        "Website",
        "Wawona.io",
        "https://wawona.io",
        "bundle:WawonaWebsite.png",
    ),
    (
        "Alex Spaulding",
        "Founder",
        "https://aspauldingcode.com",
        "https://github.com/aspauldingcode.png?size=160",
    ),
    (
        "GitHub",
        "aspauldingcode",
        "https://github.com/aspauldingcode",
        "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png",
    ),
    (
        "X",
        "aspauldingcode",
        "https://x.com/aspauldingcode",
        "bundle:X.png",
    ),
    (
        "LinkedIn",
        "aspauldingcode",
        "https://www.linkedin.com/in/aspauldingcode/",
        "https://upload.wikimedia.org/wikipedia/commons/c/ca/LinkedIn_logo_initials.png",
    ),
    (
        "Ko-fi",
        "aspauldingcode",
        "https://ko-fi.com/aspauldingcode",
        "https://ko-fi.com/android-icon-192x192.png",
    ),
    (
        "Sponsors",
        "GitHub Sponsors",
        "https://github.com/sponsors/aspauldingcode",
        "bundle:GitHubSponsors.png",
    ),
    (
        "GitHub",
        "Wawona",
        "https://github.com/Wawona/Wawona",
        "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png",
    ),
];

fn add_about_link_row(
    group: &adw::PreferencesGroup,
    title: &str,
    subtitle: &str,
    url: &str,
    icon: &str,
) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_subtitle(subtitle);
    row.set_subtitle_lines(1);
    row.set_activatable(true);
    let frame = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    frame.set_overflow(gtk::Overflow::Hidden);
    frame.add_css_class("wwn-favicon-frame");
    let image = gtk::Image::new();
    image.set_pixel_size(28);
    frame.append(&image);
    row.add_prefix(&frame);
    load_about_favicon(&image, icon);
    let gesture = gtk::GestureClick::new();
    let open_url = url.to_string();
    gesture.connect_released(move |_, _, _, _| {
        linux_open_url(&open_url);
    });
    row.add_controller(gesture);
    group.add(&row);
}

pub fn ensure_settings_css() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            ".wwn-favicon-frame { border-radius: 6px; }\n\
             .wwn-about-icon-frame { border-radius: 14px; }\n\
             .wwn-favicon { border-radius: 6px; }\n\
             .wwn-icon-blue { color: #3584e4; }\n\
             .wwn-icon-purple { color: #9141ac; }\n\
             .wwn-icon-red { color: #e01b24; }\n\
             .wwn-icon-orange { color: #ff7800; }\n\
             .wwn-icon-teal { color: #21a499; }\n\
             .wwn-icon-green { color: #2ec27e; }\n\
             .wwn-icon-indigo { color: #44458d; }\n\
             .wwn-icon-brown { color: #986a44; }\n\
             .wwn-icon-slate { color: #5e5c64; }\n",
        );
        if let Some(display) = gtk::gdk::Display::default() {
            gtk::style_context_add_provider_for_display(
                &display,
                &provider,
                gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
    });
}

fn load_about_favicon(image: &gtk::Image, spec: &str) {
    if let Some(name) = spec.strip_prefix("bundle:") {
        if let Some(bytes) = bundled_about_png(name) {
            set_favicon_bytes(image, bytes);
        } else {
            image.set_icon_name(Some("web-browser-symbolic"));
        }
        return;
    }
    let url = spec.to_string();
    if !url.starts_with("http://") && !url.starts_with("https://") {
        image.set_icon_name(Some("web-browser-symbolic"));
        return;
    }
    let cache_path = favicon_cache_file(&url);
    if cache_path.is_file() {
        if let Ok(bytes) = std::fs::read(&cache_path) {
            set_favicon_bytes(image, &bytes);
            return;
        }
    }
    image.set_icon_name(Some("web-browser-symbolic"));
    let (tx, rx) = std::sync::mpsc::channel::<Option<Vec<u8>>>();
    let image_c = image.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(100), move || {
        match rx.try_recv() {
            Ok(Some(bytes)) => {
                set_favicon_bytes(&image_c, &bytes);
                glib::ControlFlow::Break
            }
            Ok(None) => glib::ControlFlow::Break,
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        }
    });
    std::thread::spawn(move || {
        let bytes_opt = download_url_bytes(&url);
        if let Some(ref bytes) = bytes_opt {
            let _ = std::fs::write(&cache_path, bytes);
        }
        let _ = tx.send(bytes_opt);
    });
}

fn set_rounded_favicon(image: &gtk::Image, bytes: &[u8], target_size: i32, radius: f64) {
    if let Some(texture) = create_rounded_texture(bytes, target_size, radius) {
        image.set_paintable(Some(&texture));
    }
}

fn set_favicon_bytes(image: &gtk::Image, bytes: &[u8]) {
    set_rounded_favicon(image, bytes, 28, 6.0);
}

fn bundled_about_png(name: &str) -> Option<&'static [u8]> {
    match name {
        "WawonaAbout.png" => Some(include_bytes!(
            "../../resources/Wawona.icon/Assets/WawonaAbout.png"
        )),
        "WawonaWebsite.png" => Some(include_bytes!(
            "../../resources/Wawona.icon/Assets/WawonaWebsite.png"
        )),
        "X.png" => Some(include_bytes!(
            "../../resources/Wawona.icon/Assets/X.png"
        )),
        "GitHubSponsors.png" => Some(include_bytes!(
            "../../resources/Wawona.icon/Assets/GitHubSponsors.png"
        )),
        _ => None,
    }
}

fn favicon_cache_file(url: &str) -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    std::path::Path::new(&home)
        .join(".cache/wawona/favicons")
        .join(format!("{:016x}.png", fnv64(url.as_bytes())))
}

fn download_url_bytes(url: &str) -> Option<Vec<u8>> {
    let tmp = favicon_cache_file(url).with_extension("tmp");
    if let Some(parent) = tmp.parent() {
        std::fs::create_dir_all(parent).ok()?;
    }
    let ok = std::process::Command::new("curl")
        .args(["-fsSL", "--max-time", "20", "-o"])
        .arg(&tmp)
        .arg(url)
        .status()
        .ok()?
        .success();
    if !ok {
        let _ = std::fs::remove_file(&tmp);
        return None;
    }
    let bytes = std::fs::read(&tmp).ok()?;
    let _ = std::fs::remove_file(&tmp);
    if bytes.is_empty() { None } else { Some(bytes) }
}

fn fnv64(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn show_dependency_detail(
    parent: Option<&gtk::Window>,
    name: &str,
    version: &str,
    role: &str,
    license: &str,
    url: &str,
) {
    let heading = if version.is_empty() {
        name.to_string()
    } else {
        format!("{name} {version}")
    };
    let dialog = adw::MessageDialog::new(
        parent,
        Some(&heading),
        None,
    );
    let mut body = String::new();
    if !role.is_empty() {
        body.push_str(role);
    }
    if !license.is_empty() {
        if !body.is_empty() {
            body.push_str("\n\n");
        }
        body.push_str(&format!("License: {license}"));
    }
    dialog.set_body(&body);

    if !url.is_empty() {
        dialog.add_response("open_url", "Open Website");
        dialog.set_response_appearance("open_url", adw::ResponseAppearance::Suggested);
    }
    dialog.add_response("close", "Close");
    dialog.set_default_response(Some(if !url.is_empty() { "open_url" } else { "close" }));
    dialog.set_close_response("close");

    let open_url = url.to_string();
    dialog.connect_response(None, move |d, response| {
        if response == "open_url" && !open_url.is_empty() {
            linux_open_url(&open_url);
        }
        d.close();
    });
    dialog.present();
}

fn add_dependency_row(
    group: &adw::PreferencesGroup,
    name: &str,
    version: &str,
    role: &str,
    license: &str,
    url: &str,
) {
    let row = adw::ActionRow::new();
    row.set_title(name);
    row.set_title_lines(1);
    row.set_subtitle(role);
    row.set_subtitle_lines(1);
    row.set_activatable(true);

    if !version.is_empty() {
        let ver_lbl = gtk::Label::new(Some(version));
        ver_lbl.add_css_class("dim-label");
        row.add_suffix(&ver_lbl);
    }
    let chevron = gtk::Image::from_icon_name("go-next-symbolic");
    row.add_suffix(&chevron);

    let name = name.to_string();
    let version = version.to_string();
    let role = role.to_string();
    let license = license.to_string();
    let url = url.to_string();

    row.connect_activated(move |r| {
        let root_win = r.root().and_downcast::<gtk::Window>();
        show_dependency_detail(
            root_win.as_ref(),
            &name,
            &version,
            &role,
            &license,
            &url,
        );
    });

    group.add(&row);
}

fn add_switch_row(group: &adw::PreferencesGroup, title: &str, active: bool) -> adw::SwitchRow {
    let row = adw::SwitchRow::new();
    row.set_title(title);
    row.set_active(active);
    group.add(&row);
    row
}

fn add_entry_row(group: &adw::PreferencesGroup, title: &str, text: &str) -> adw::EntryRow {
    let row = adw::EntryRow::new();
    row.set_title(title);
    row.set_text(text);
    group.add(&row);
    row
}

fn add_password_row(group: &adw::PreferencesGroup, title: &str, text: &str) -> adw::PasswordEntryRow {
    let row = adw::PasswordEntryRow::new();
    row.set_title(title);
    row.set_text(text);
    group.add(&row);
    row
}

fn add_spin_row(group: &adw::PreferencesGroup, title: &str, val: f64, min: f64, max: f64, step: f64) -> adw::SpinRow {
    let adj = gtk::Adjustment::new(val, min, max, step, step * 2.0, 0.0);
    let row = adw::SpinRow::new(Some(&adj), 1.0, 0);
    row.set_title(title);
    group.add(&row);
    row
}

fn add_combo_row(
    group: &adw::PreferencesGroup,
    title: &str,
    choices: &[&str],
    current: &str,
    target_value: Rc<RefCell<String>>,
) -> adw::ComboRow {
    let row = adw::ComboRow::new();
    row.set_title(title);
    let labels: Vec<String> = choices.iter().map(|s| s.to_string()).collect();
    let model = gtk::StringList::new(choices);
    row.set_model(Some(&model));
    if let Some(idx) = choices.iter().position(|&s| s == current) {
        row.set_selected(idx as u32);
    }
    let choices_v = labels;
    let target_v = target_value;
    row.connect_selected_notify(move |c| {
        let idx = c.selected() as usize;
        if let Some(val) = choices_v.get(idx) {
            *target_v.borrow_mut() = val.clone();
        }
    });
    group.add(&row);
    row
}

fn add_named_combo_row(
    group: &adw::PreferencesGroup,
    title: &str,
    choices: &[(&str, &str)],
    current: &str,
    target_value: Rc<RefCell<String>>,
) -> adw::ComboRow {
    let row = adw::ComboRow::new();
    row.set_title(title);
    let display_labels: Vec<&str> = choices.iter().map(|(_, label)| *label).collect();
    let model = gtk::StringList::new(&display_labels);
    row.set_model(Some(&model));
    let norm_current = match current {
        "tab" => "newTab",
        "window" => "newWindow",
        other => other,
    };
    if let Some(idx) = choices.iter().position(|(id, _)| *id == norm_current || *id == current) {
        row.set_selected(idx as u32);
    }
    let ids: Vec<String> = choices.iter().map(|(id, _)| id.to_string()).collect();
    let target_v = target_value;
    row.connect_selected_notify(move |c| {
        let idx = c.selected() as usize;
        if let Some(val) = ids.get(idx) {
            *target_v.borrow_mut() = val.clone();
        }
    });
    group.add(&row);
    row
}

fn add_row(group: &adw::PreferencesGroup, title: &str, widget: &impl IsA<gtk::Widget>) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.add_suffix(widget);
    row.set_activatable(false);
    group.add(&row);
}

fn add_info_row(group: &adw::PreferencesGroup, title: &str, value: &str) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_subtitle(value);
    row.set_subtitle_lines(0);
    group.add(&row);
}

fn create_rounded_texture(bytes: &[u8], target_size: i32, radius: f64) -> Option<gdk::Texture> {
    let raw_tex = gdk::Texture::from_bytes(&glib::Bytes::from(bytes)).ok()?;
    let orig_w = raw_tex.width();
    let orig_h = raw_tex.height();
    if orig_w <= 0 || orig_h <= 0 {
        return None;
    }

    let target_w = target_size;
    let target_h = target_size;
    let dst_stride = target_w * 4;

    let surface = cairo::ImageSurface::create(cairo::Format::ARgb32, target_w, target_h).ok()?;
    let cr = cairo::Context::new(&surface).ok()?;

    let w = target_w as f64;
    let h = target_h as f64;
    let r = radius;
    let degrees = std::f64::consts::PI / 180.0;
    cr.new_sub_path();
    cr.arc(w - r, r, r, -90.0 * degrees, 0.0 * degrees);
    cr.arc(w - r, h - r, r, 0.0 * degrees, 90.0 * degrees);
    cr.arc(r, h - r, r, 90.0 * degrees, 180.0 * degrees);
    cr.arc(r, r, r, 180.0 * degrees, 270.0 * degrees);
    cr.close_path();
    cr.clip();

    let src_stride = orig_w * 4;
    let mut raw_buf = vec![0u8; (src_stride * orig_h) as usize];
    raw_tex.download(&mut raw_buf, src_stride as usize);

    let src_surf = cairo::ImageSurface::create_for_data(
        raw_buf,
        cairo::Format::ARgb32,
        orig_w,
        orig_h,
        src_stride,
    ).ok()?;

    cr.scale(w / (orig_w as f64), h / (orig_h as f64));
    cr.set_source_surface(&src_surf, 0.0, 0.0).ok()?;
    cr.paint().ok()?;
    drop(cr);

    surface.flush();
    let data = surface.take_data().ok()?;
    let glib_bytes = glib::Bytes::from(data.as_ref());
    let mem_tex = gdk::MemoryTexture::new(
        target_w,
        target_h,
        gdk::MemoryFormat::B8g8r8a8Premultiplied,
        &glib_bytes,
        dst_stride as usize,
    );
    Some(mem_tex.upcast())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_rounded_texture() {
        if gtk::init().is_err() {
            return;
        }
        let about_bytes = bundled_about_png("WawonaAbout.png").expect("WawonaAbout.png");
        let about_tex = create_rounded_texture(about_bytes, 64, 14.0);
        assert!(about_tex.is_some());
        let tex = about_tex.unwrap();
        assert_eq!(tex.width(), 64);
        assert_eq!(tex.height(), 64);

        let web_bytes = bundled_about_png("WawonaWebsite.png").expect("WawonaWebsite.png");
        let web_tex = create_rounded_texture(web_bytes, 28, 6.0);
        assert!(web_tex.is_some());
        let wtex = web_tex.unwrap();
        assert_eq!(wtex.width(), 28);
        assert_eq!(wtex.height(), 28);
    }
}
