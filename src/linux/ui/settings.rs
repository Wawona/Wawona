//! Settings dialog with section parity to Android `SettingsDialog`.

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

use crate::ffi::api::{build_info, version};
use crate::linux::runtime;
use crate::linux::service;
use crate::linux::ui::modal_sheet::present_sheet;
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;
use crate::wlog;

pub fn show_settings(
    parent: &adw::ApplicationWindow,
    state: &SharedAppState,
    layout: LayoutMode,
) {
    wlog!("UI", "Settings dialog opened");

    let header = adw::HeaderBar::new();
    let done_btn = gtk::Button::with_label("Done");
    done_btn.add_css_class("suggested-action");
    header.pack_end(&done_btn);

    let sidebar = gtk::ListBox::new();
    sidebar.set_selection_mode(gtk::SelectionMode::Single);
    sidebar.add_css_class("navigation-sidebar");
    sidebar.set_width_request(180);

    let sections = [
        "Machines",
        "Display",
        "Input",
        "Graphics",
        "SSH and Waypipe",
        "Dependencies",
        "VM and Container",
        "Advanced",
        "Launch Agent",
        "Diagnostics",
        "About",
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
    let settings = &cfg.settings;

    // Machines (global defaults for new profiles)
    let machines_page = adw::PreferencesPage::new();
    let machines_group = adw::PreferencesGroup::new();
    machines_group.set_title("Machine Defaults");
    machines_group.set_description(Some(
        "Defaults applied when creating new machine profiles. Per-machine overrides live in the editor.",
    ));
    let default_renderer = gtk::ComboBoxText::new();
    for r in ["vulkan", "software"] {
        default_renderer.append(Some(r), r);
    }
    default_renderer.set_active_id(Some(&settings.renderer));
    add_row(&machines_group, "Default Renderer", &default_renderer);
    machines_page.add(&machines_group);
    stack.add_named(&machines_page, Some("Machines"));

    // Display
    let display_page = adw::PreferencesPage::new();
    let display_group = adw::PreferencesGroup::new();
    display_group.set_title("Display");
    let auto_scale = gtk::Switch::new();
    auto_scale.set_active(settings.auto_scale);
    let wayland_display = gtk::Entry::new();
    wayland_display.set_text(&settings.wayland_display);
    add_row(&display_group, "Auto Scale", &auto_scale);
    add_row(&display_group, "Wayland Display", &wayland_display);
    display_page.add(&display_group);
    stack.add_named(&display_page, Some("Display"));

    // Input
    let input_page = adw::PreferencesPage::new();
    let input_group = adw::PreferencesGroup::new();
    input_group.set_title("Input");
    let input_profile = gtk::Entry::new();
    input_profile.set_text(&settings.input_profile);
    let key_repeat = gtk::SpinButton::with_range(1.0, 60.0, 1.0);
    key_repeat.set_value(settings.key_repeat as f64);
    add_row(&input_group, "Default Input Profile", &input_profile);
    add_row(&input_group, "Key Repeat", &key_repeat);
    input_page.add(&input_group);
    stack.add_named(&input_page, Some("Input"));

    // Graphics
    let graphics_page = adw::PreferencesPage::new();
    let graphics_group = adw::PreferencesGroup::new();
    graphics_group.set_title("Graphics");
    let renderer = gtk::ComboBoxText::new();
    for r in ["vulkan", "software"] {
        renderer.append(Some(r), r);
    }
    renderer.set_active_id(Some(&settings.renderer));
    let force_ssd = gtk::Switch::new();
    force_ssd.set_active(settings.force_ssd);
    let color_ops = gtk::Switch::new();
    color_ops.set_active(settings.color_operations);
    add_row(&graphics_group, "Renderer", &renderer);
    add_row(&graphics_group, "Force Server-Side Decorations", &force_ssd);
    add_row(&graphics_group, "HDR / Color Operations", &color_ops);
    graphics_page.add(&graphics_group);
    stack.add_named(&graphics_page, Some("Graphics"));

    // SSH and Waypipe
    let ssh_page = adw::PreferencesPage::new();
    let ssh_group = adw::PreferencesGroup::new();
    ssh_group.set_title("SSH");
    let ssh_host = gtk::Entry::new();
    ssh_host.set_text(&settings.ssh_host);
    let ssh_user = gtk::Entry::new();
    ssh_user.set_text(&settings.ssh_user);
    let ssh_password = gtk::PasswordEntry::builder().show_peek_icon(true).build();
    ssh_password.set_text(&settings.ssh_password);
    let ssh_port = gtk::Entry::new();
    ssh_port.set_text(&settings.ssh_port.to_string());
    add_row(&ssh_group, "Host", &ssh_host);
    add_row(&ssh_group, "User", &ssh_user);
    add_row(&ssh_group, "Password", &ssh_password);
    add_row(&ssh_group, "Port", &ssh_port);
    let waypipe_group = adw::PreferencesGroup::new();
    waypipe_group.set_title("Waypipe");
    let wp_compress = gtk::Entry::new();
    wp_compress.set_text(&settings.waypipe_compression);
    let wp_video = gtk::Entry::new();
    wp_video.set_text(&settings.waypipe_video);
    let wp_debug = gtk::Switch::new();
    wp_debug.set_active(settings.waypipe_debug);
    let wp_enabled = gtk::Switch::new();
    wp_enabled.set_active(settings.waypipe_enabled);
    add_row(&waypipe_group, "Compression", &wp_compress);
    add_row(&waypipe_group, "Video", &wp_video);
    add_row(&waypipe_group, "Debug", &wp_debug);
    add_row(&waypipe_group, "Default Waypipe Enabled", &wp_enabled);
    ssh_page.add(&ssh_group);
    ssh_page.add(&waypipe_group);
    stack.add_named(&ssh_page, Some("SSH and Waypipe"));

    // Dependencies
    let deps_page = adw::PreferencesPage::new();
    let deps_group = adw::PreferencesGroup::new();
    deps_group.set_title("Bundled Dependencies");
    deps_group.set_description(Some(
        "Runtime tools shipped with the Linux app (weston clients, foot, kmscube, zsh, fastfetch, neovim, waypipe).",
    ));
    for dep in [
        "Weston + demo clients",
        "Foot terminal",
        "kmscube (ANGLE/Vulkan)",
        "waypipe",
        "OpenSSH",
        "zsh",
        "fastfetch",
        "neovim",
    ] {
        let row = adw::ActionRow::new();
        row.set_title(dep);
        deps_group.add(&row);
    }
    deps_page.add(&deps_group);
    stack.add_named(&deps_page, Some("Dependencies"));

    // VM and Container
    let vm_page = adw::PreferencesPage::new();
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machines");
    let vm_info = adw::ActionRow::new();
    vm_info.set_title("UTM SE integration");
    vm_info.set_subtitle("VM launch is a stub. Future support will come from Wawona's UTM SE fork.");
    vm_group.add(&vm_info);
    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Containers");
    let container_info = adw::ActionRow::new();
    container_info.set_title("Container runtime");
    container_info.set_subtitle("Container launch is a stub (integration pending).");
    container_group.add(&container_info);
    vm_page.add(&vm_group);
    vm_page.add(&container_group);
    stack.add_named(&vm_page, Some("VM and Container"));

    // Advanced
    let advanced_page = adw::PreferencesPage::new();
    let advanced_group = adw::PreferencesGroup::new();
    advanced_group.set_title("Advanced");
    let log_level = gtk::ComboBoxText::new();
    for l in ["debug", "info", "warn", "error"] {
        log_level.append(Some(l), l);
    }
    log_level.set_active_id(Some(&settings.log_level));
    add_row(&advanced_group, "Log Level", &log_level);
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
    for (t, b) in [
        ("Install", &install_btn),
        ("Host Start", &start_host_btn),
        ("Host Restart", &restart_host_btn),
        ("Host Stop", &stop_host_btn),
        ("Tray", &start_tray_btn),
    ] {
        add_row(&agent_group, t, b);
    }
    install_btn.connect_clicked(|_| {
        let _ = service::install_user_units();
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
    agent_page.add(&agent_group);
    stack.add_named(&agent_page, Some("Launch Agent"));

    // Diagnostics
    let diag_page = adw::PreferencesPage::new();
    let diag_group = adw::PreferencesGroup::new();
    diag_group.set_title("Runtime Diagnostics");
    let state_row = adw::ActionRow::new();
    state_row.set_title("Runtime State");
    state_row.set_subtitle(&match runtime::read_runtime_state() {
        Ok(rt) => format!(
            "healthy={} display={} socket={}",
            rt.healthy, rt.wayland_display, rt.socket_path
        ),
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
    about_page.add(&about_group);
    stack.add_named(&about_page, Some("About"));

    drop(cfg);

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

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.append(&header);
    body.append(&split);

    let dialog = present_sheet(parent, "Settings", &body, layout);

    let st = state.clone();
    let d = dialog.clone();
    done_btn.connect_clicked(move |_| {
        let mut app = st.borrow_mut();
        app.settings.wayland_display = wayland_display.text().to_string();
        app.settings.auto_scale = auto_scale.is_active();
        app.settings.input_profile = input_profile.text().to_string();
        app.settings.key_repeat = key_repeat.value() as u32;
        app.settings.renderer = renderer
            .active_id()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "vulkan".into());
        app.settings.force_ssd = force_ssd.is_active();
        app.settings.color_operations = color_ops.is_active();
        app.settings.ssh_host = ssh_host.text().to_string();
        app.settings.ssh_user = ssh_user.text().to_string();
        app.settings.ssh_port = ssh_port.text().parse().unwrap_or(22);
        app.settings.ssh_password = ssh_password.text().to_string();
        app.settings.waypipe_compression = wp_compress.text().to_string();
        app.settings.waypipe_video = wp_video.text().to_string();
        app.settings.waypipe_debug = wp_debug.is_active();
        app.settings.waypipe_enabled = wp_enabled.is_active();
        app.settings.log_level = log_level
            .active_id()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "info".into());
        app.persist_settings();
        wlog!("UI", "Settings saved");
        d.close();
    });
}

fn add_row(group: &adw::PreferencesGroup, title: &str, widget: &impl IsA<gtk::Widget>) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.add_suffix(widget);
    row.set_activatable(false);
    group.add(&row);
}
