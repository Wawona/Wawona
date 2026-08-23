//! Settings dialog with section parity to Android `SettingsDialog`.

use std::cell::RefCell;
use std::rc::Rc;

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;
use gtk::prelude::*;

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
    crate::linux::ui::a11y::set_wwn_a11y(
        &done_btn,
        crate::linux::ui::a11y::id::SETTINGS_DONE,
        Some("Done"),
    );
    header.pack_end(&done_btn);
    let back_btn = gtk::Button::from_icon_name("go-previous-symbolic");
    back_btn.set_tooltip_text(Some("Back"));
    back_btn.set_visible(false);
    header.pack_start(&back_btn);

    let sidebar = gtk::ListBox::new();
    sidebar.set_selection_mode(gtk::SelectionMode::Single);
    sidebar.add_css_class("navigation-sidebar");
    sidebar.set_width_request(180);
    crate::linux::ui::a11y::set_wwn_a11y(
        &sidebar,
        crate::linux::ui::a11y::id::SETTINGS_ROOT,
        Some("Settings"),
    );

    let sections = [
        "Machines",
        "Display",
        "Input",
        "Graphics",
        "Env Vars",
        "Local Shell",
        "SSH and Waypipe",
        "Dependencies",
        "Advanced",
        "Launch Agent",
        "Diagnostics",
        "About",
    ];
    for name in &sections {
        let row = gtk::ListBoxRow::new();
        let label = gtk::Label::new(Some(name));
        label.set_xalign(0.0);
        label.set_margin_start(8);
        label.set_margin_end(8);
        label.set_margin_top(4);
        label.set_margin_bottom(4);
        row.set_child(Some(&label));
        let id = crate::linux::ui::a11y::settings_section_id(name);
        crate::linux::ui::a11y::set_wwn_a11y(&row, &id, Some(name));
        sidebar.append(&row);
    }

    let stack = gtk::Stack::new();
    stack.set_hexpand(true);
    stack.set_vexpand(true);

    let cfg = state.borrow();
    let settings = &cfg.settings;
    let renderer_value = Rc::new(RefCell::new(settings.renderer.clone()));
    let log_level_value = Rc::new(RefCell::new(settings.log_level.clone()));

    let detail_stack = gtk::Stack::new();
    detail_stack.set_hexpand(true);
    detail_stack.set_vexpand(true);
    let choice_title = gtk::Label::new(None);
    choice_title.add_css_class("title-2");
    choice_title.set_xalign(0.0);
    choice_title.set_margin_start(16);
    choice_title.set_margin_end(16);
    choice_title.set_margin_top(16);
    choice_title.set_margin_bottom(8);
    let choice_list = gtk::ListBox::new();
    choice_list.set_selection_mode(gtk::SelectionMode::None);
    choice_list.add_css_class("boxed-list");
    choice_list.set_margin_start(16);
    choice_list.set_margin_end(16);
    choice_list.set_margin_bottom(16);
    let choice_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    choice_box.append(&choice_title);
    let choice_scroll = gtk::ScrolledWindow::new();
    choice_scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
    choice_scroll.set_vexpand(true);
    choice_scroll.set_child(Some(&choice_list));
    choice_box.append(&choice_scroll);
    detail_stack.add_named(&choice_box, Some("choice"));

    let open_choice: Rc<dyn Fn(String, Vec<String>, Rc<RefCell<String>>, gtk::Label)> = {
        let detail_stack = detail_stack.clone();
        let choice_list = choice_list.clone();
        let choice_title = choice_title.clone();
        let back_btn = back_btn.clone();
        Rc::new(move |title, choices, selected, value_label| {
            while let Some(row) = choice_list.row_at_index(0) {
                row.unparent();
            }
            choice_title.set_text(&title);
            let current = selected.borrow().clone();
            for choice in choices {
                let row = adw::ActionRow::new();
                row.set_title(&choice);
                row.set_activatable(true);
                if choice == current {
                    row.add_suffix(&gtk::Image::from_icon_name("object-select-symbolic"));
                }
                let selected_c = selected.clone();
                let label_c = value_label.clone();
                let choice_c = choice.clone();
                let detail_stack_c = detail_stack.clone();
                let back_c = back_btn.clone();
                row.connect_activated(move |_| {
                    *selected_c.borrow_mut() = choice_c.clone();
                    label_c.set_text(&choice_c);
                    detail_stack_c.set_visible_child_name("section");
                    back_c.set_visible(false);
                });
                choice_list.append(&row);
            }
            detail_stack.set_visible_child_name("choice");
            back_btn.set_visible(true);
        })
    };
    {
        let detail_stack = detail_stack.clone();
        let back_btn = back_btn.clone();
        back_btn.connect_clicked(move |btn| {
            detail_stack.set_visible_child_name("section");
            btn.set_visible(false);
        });
    }

    // Machines (global defaults for new profiles)
    let machines_page = adw::PreferencesPage::new();
    let machines_group = adw::PreferencesGroup::new();
    machines_group.set_title("Machine Defaults");
    machines_group.set_description(Some(
        "Defaults applied when creating new machine profiles. Per-machine overrides live in the editor.",
    ));
    add_choice_row(
        &machines_group,
        "Default Renderer",
        &["vulkan", "software"],
        renderer_value.clone(),
        open_choice.clone(),
    );
    machines_page.add(&machines_group);
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machines");
    add_info_row(
        &vm_group,
        "UTM SE integration",
        "VM launch is a stub. Future support will come from Wawona's UTM SE fork.",
    );
    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Containers");
    add_info_row(
        &container_group,
        "Container runtime",
        "Container launch is a stub (integration pending).",
    );
    machines_page.add(&vm_group);
    machines_page.add(&container_group);
    stack.add_named(&machines_page, Some("Machines"));

    // Display
    let display_page = adw::PreferencesPage::new();
    let display_group = adw::PreferencesGroup::new();
    display_group.set_title("Display");
    let wayland_display = gtk::Entry::new();
    wayland_display.set_text(&settings.wayland_display);
    let color_ops = gtk::Switch::new();
    color_ops.set_active(settings.color_operations);
    add_row(&display_group, "Enable HDR", &color_ops);
    add_row(&display_group, "Wayland Display", &wayland_display);
    display_page.add(&display_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &display_page,
        crate::linux::ui::a11y::id::SETTINGS_DISPLAY,
        Some("Display"),
    );
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
    add_choice_row(
        &graphics_group,
        "Renderer",
        &["vulkan", "software"],
        renderer_value.clone(),
        open_choice.clone(),
    );
    graphics_page.add(&graphics_group);
    stack.add_named(&graphics_page, Some("Graphics"));

    // Environment (#157 / #161)
    let env_page = adw::PreferencesPage::new();
    let env_group = adw::PreferencesGroup::new();
    env_group.set_title("Environment Variables");
    env_group.set_description(Some(
        "Global KEY=value overrides applied to launched clients (machine overrides win). \
         Lines starting with -NAME unset a variable. Same catalog as Apple/Android Settings → Environment.",
    ));
    let env_text = gtk::TextView::new();
    env_text.set_monospace(true);
    env_text.set_wrap_mode(gtk::WrapMode::WordChar);
    env_text.set_vexpand(true);
    env_text.set_hexpand(true);
    {
        let mut buf = String::new();
        for (k, v) in &settings.environment_overrides {
            buf.push_str(k);
            buf.push('=');
            buf.push_str(v);
            buf.push('\n');
        }
        for name in &settings.environment_unsets {
            buf.push('-');
            buf.push_str(name);
            buf.push('\n');
        }
        env_text.buffer().set_text(&buf);
    }
    let env_scroll = gtk::ScrolledWindow::new();
    env_scroll.set_min_content_height(220);
    env_scroll.set_child(Some(&env_text));
    env_group.add(&env_scroll);
    env_page.add(&env_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &env_page,
        crate::linux::ui::a11y::id::SETTINGS_ENVIRONMENT,
        Some("Env Vars"),
    );
    stack.add_named(&env_page, Some("Env Vars"));

    // Local Shell (host environment. Mirrors WWNRootfsProvider host snapshot)
    let shell_page = adw::PreferencesPage::new();
    let shell_group = adw::PreferencesGroup::new();
    shell_group.set_title("Local Shell");
    shell_group.set_description(Some(
        "Linux uses your login environment, not a sandbox rootfs. Reset System Tree and bundled HOME import do not apply.",
    ));
    let home = std::env::var("HOME").unwrap_or_else(|_| "(unset)".into());
    let open_home = gtk::Button::with_label("Open HOME");
    {
        let home_path = home.clone();
        open_home.connect_clicked(move |_| {
            let _ = std::process::Command::new("xdg-open").arg(&home_path).spawn();
        });
    }
    add_row(&shell_group, "Open HOME", &open_home);
    shell_page.add(&shell_group);
    stack.add_named(&shell_page, Some("Local Shell"));

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
        "Packages linked into this Linux UI build. Not another platform's list.",
    ));
    let deps_json = include_str!("settings_dependencies.json");
    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(deps_json) {
        if let Some(packages) = parsed.get("packages").and_then(|p| p.as_array()) {
            for pkg in packages {
                let name = pkg.get("name").and_then(|v| v.as_str()).unwrap_or("Package");
                let version = pkg.get("version").and_then(|v| v.as_str()).unwrap_or("");
                let role = pkg.get("role").and_then(|v| v.as_str()).unwrap_or("");
                add_info_row(
                    &deps_group,
                    name,
                    &format!("{version}. {role}").trim_end_matches(". ").to_string(),
                );
            }
        }
    }
    deps_page.add(&deps_group);
    stack.add_named(&deps_page, Some("Dependencies"));

    // Advanced
    let advanced_page = adw::PreferencesPage::new();
    let advanced_group = adw::PreferencesGroup::new();
    advanced_group.set_title("Advanced");
    add_choice_row(
        &advanced_group,
        "Log Level",
        &["debug", "info", "warn", "error"],
        log_level_value.clone(),
        open_choice.clone(),
    );
    advanced_page.add(&advanced_group);
    stack.add_named(&advanced_page, Some("Advanced"));

    // Launch Agent
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

    // Diagnostics
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
    diag_page.add(&diag_group);
    stack.add_named(&diag_page, Some("Diagnostics"));

    // About
    let about_page = adw::PreferencesPage::new();
    let about_group = adw::PreferencesGroup::new();
    about_group.set_title("Wawona");
    add_info_row(
        &about_group,
        "Version",
        &format!("{} ({})", version(), build_info()),
    );
    add_info_row(&about_group, "Platform", "Linux");
    add_info_row(
        &about_group,
        "Description",
        "Multi-platform compositor control plane.",
    );
    let copy_logs = gtk::Button::with_label("Copy Recent Logs");
    crate::linux::ui::a11y::set_wwn_a11y(
        &copy_logs,
        crate::linux::ui::a11y::id::SETTINGS_COPY_LOGS,
        Some("Copy Recent Logs"),
    );
    let report_bug = gtk::Button::with_label("Report a Bug on GitHub");
    report_bug.add_css_class("suggested-action");
    crate::linux::ui::a11y::set_wwn_a11y(
        &report_bug,
        crate::linux::ui::a11y::id::SETTINGS_REPORT_BUG,
        Some("Report a Bug on GitHub"),
    );
    add_link_row(&about_group, "Wawona.io", "https://wawona.io");
    add_row(&about_group, "Diagnostics", &copy_logs);
    add_row(&about_group, "GitHub", &report_bug);
    add_link_row(
        &about_group,
        "Author",
        "https://aspauldingcode.com",
    );
    copy_logs.connect_clicked(|_| {
        linux_copy_bug_diagnostics();
    });
    report_bug.connect_clicked(|_| {
        linux_open_github_bug_report();
    });
    about_page.add(&about_group);
    stack.add_named(&about_page, Some("About"));

    drop(cfg);

    {
        let stack = stack.clone();
        let detail_stack = detail_stack.clone();
        let back_btn = back_btn.clone();
        sidebar.connect_row_selected(move |_, row| {
            detail_stack.set_visible_child_name("section");
            back_btn.set_visible(false);
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

    let section_scroll = gtk::ScrolledWindow::new();
    section_scroll.set_hscrollbar_policy(gtk::PolicyType::Never);
    section_scroll.set_child(Some(&stack));
    detail_stack.add_named(&section_scroll, Some("section"));
    detail_stack.set_visible_child_name("section");

    split.set_start_child(Some(&sidebar_scroll));
    split.set_end_child(Some(&detail_stack));

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.append(&header);
    body.append(&split);

    let dialog = present_sheet(parent, "Settings", &body, layout);

    let st = state.clone();
    let d = dialog.clone();
    done_btn.connect_clicked(move |_| {
        let mut app = st.borrow_mut();
        app.settings.wayland_display = wayland_display.text().to_string();
        app.settings.auto_scale = true;
        app.settings.input_profile = input_profile.text().to_string();
        app.settings.key_repeat = key_repeat.value() as u32;
        app.settings.renderer = renderer_value.borrow().clone();
        app.settings.force_ssd = true;
        app.settings.color_operations = color_ops.is_active();
        app.settings.ssh_host = ssh_host.text().to_string();
        app.settings.ssh_user = ssh_user.text().to_string();
        app.settings.ssh_port = ssh_port.text().parse().unwrap_or(22);
        app.settings.ssh_password = ssh_password.text().to_string();
        app.settings.waypipe_compression = wp_compress.text().to_string();
        app.settings.waypipe_video = wp_video.text().to_string();
        app.settings.waypipe_debug = wp_debug.is_active();
        app.settings.waypipe_enabled = wp_enabled.is_active();
        app.settings.log_level = log_level_value.borrow().clone();
        {
            let buffer = env_text.buffer();
            let start = buffer.start_iter();
            let end = buffer.end_iter();
            let text = buffer.text(&start, &end, false);
            let mut overrides = std::collections::BTreeMap::new();
            let mut unsets = Vec::new();
            for line in text.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                if let Some(name) = line.strip_prefix('-') {
                    let name = name.trim();
                    if !name.is_empty() {
                        unsets.push(name.to_string());
                    }
                    continue;
                }
                if let Some((k, v)) = line.split_once('=') {
                    let k = k.trim();
                    if !k.is_empty() {
                        overrides.insert(k.to_string(), v.to_string());
                    }
                }
            }
            app.settings.environment_overrides = overrides;
            app.settings.environment_unsets = unsets;
        }
        app.persist_settings();
        wlog!("UI", "Settings saved");
        d.close();
    });
}

fn linux_host_os() -> String {
    let pretty = std::fs::read_to_string("/etc/os-release")
        .ok()
        .and_then(|s| {
            s.lines().find_map(|line| {
                line.strip_prefix("PRETTY_NAME=")
                    .map(|v| v.trim_matches('"').to_string())
            })
        })
        .unwrap_or_else(|| "Linux".to_string());
    format!("{pretty} ({})", std::env::consts::ARCH)
}

fn linux_install_channel() -> &'static str {
    if std::env::var_os("APPIMAGE").is_some() {
        "Other"
    } else {
        "nix / local build (not a prebuilt installation)"
    }
}

fn linux_bug_diagnostics() -> String {
    let ver = version();
    format!(
        "### Wawona diagnostics\nWawona: v{ver}\nHost: {}\nInstall: {}\n\n### Logs\n```\n{}\n```\n",
        linux_host_os(),
        linux_install_channel(),
        crate::util::logging::dump_ring(None),
    )
}

fn linux_copy_bug_diagnostics() {
    let report = linux_bug_diagnostics();
    if let Some(display) = gtk::gdk::Display::default() {
        display.clipboard().set_text(&report);
    }
}

fn linux_open_github_bug_report() {
    let report = linux_bug_diagnostics();
    linux_copy_bug_diagnostics();
    let ver = version();
    let url = crate::util::bug_report::github_bug_form_url(
        "Linux",
        linux_install_channel(),
        &ver,
        &linux_host_os(),
        &report,
    );
    let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
}

fn linux_open_url(url: &str) {
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn settings_one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn add_link_row(group: &adw::PreferencesGroup, title: &str, url: &str) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    let label = url
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://");
    row.set_subtitle(&settings_one_line(label));
    row.set_subtitle_lines(1);
    row.set_activatable(true);
    let open_url = url.to_string();
    row.connect_activated(move |_| {
        linux_open_url(&open_url);
    });
    group.add(&row);
}

fn add_info_row(group: &adw::PreferencesGroup, title: &str, detail: &str) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_subtitle(&settings_one_line(detail));
    // 0 disables ellipsis; the real value wraps in the row.
    row.set_subtitle_lines(0);
    row.set_activatable(true);
    let title_owned = title.to_string();
    let detail = detail.to_string();
    row.connect_activated(move |row| {
        let parent = row.root().and_downcast::<gtk::Window>();
        let dlg = gtk::MessageDialog::new(
            parent.as_ref(),
            gtk::DialogFlags::MODAL,
            gtk::MessageType::Info,
            gtk::ButtonsType::Ok,
            &detail,
        );
        dlg.set_title(Some(&title_owned));
        dlg.connect_response(|d, _| d.close());
        dlg.present();
    });
    group.add(&row);
}

fn add_choice_row(
    group: &adw::PreferencesGroup,
    title: &str,
    choices: &[&str],
    selected: Rc<RefCell<String>>,
    open_choice: Rc<dyn Fn(String, Vec<String>, Rc<RefCell<String>>, gtk::Label)>,
) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_activatable(true);
    let value = gtk::Label::new(Some(selected.borrow().as_str()));
    value.add_css_class("dim-label");
    row.add_suffix(&value);
    row.add_suffix(&gtk::Image::from_icon_name("go-next-symbolic"));
    let title_owned = title.to_string();
    let choices_owned: Vec<String> = choices.iter().map(|choice| (*choice).to_string()).collect();
    let selected_c = selected.clone();
    let value_c = value.clone();
    row.connect_activated(move |_| {
        open_choice(
            title_owned.clone(),
            choices_owned.clone(),
            selected_c.clone(),
            value_c.clone(),
        );
    });
    group.add(&row);
}

fn add_row(group: &adw::PreferencesGroup, title: &str, widget: &impl IsA<gtk::Widget>) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.add_suffix(widget);
    row.set_activatable(false);
    group.add(&row);
}
