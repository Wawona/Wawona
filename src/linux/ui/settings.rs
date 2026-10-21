//! Settings dialog with full parity to Apple and Android Global Settings.

use std::cell::RefCell;
use std::rc::Rc;

use adw::prelude::*;
use gtk::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

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
        icon: "video-display-symbolic",
        css_class: "wwn-icon-blue",
        a11y_id: "wwn.settings.display",
    },
    SettingsSectionMeta {
        name: "Input",
        icon: "input-keyboard-symbolic",
        css_class: "wwn-icon-purple",
        a11y_id: "wwn.settings.input",
    },
    SettingsSectionMeta {
        name: "Graphics",
        icon: "applications-graphics-symbolic",
        css_class: "wwn-icon-red",
        a11y_id: "wwn.settings.graphics",
    },
    SettingsSectionMeta {
        name: "Connection",
        icon: "network-wired-symbolic",
        css_class: "wwn-icon-orange",
        a11y_id: "wwn.settings.connection",
    },
    SettingsSectionMeta {
        name: "Env Vars",
        icon: "utilities-terminal-symbolic",
        css_class: "wwn-icon-teal",
        a11y_id: "wwn.settings.environment",
    },
    SettingsSectionMeta {
        name: "Local Shell",
        icon: "folder-symbolic",
        css_class: "wwn-icon-green",
        a11y_id: "wwn.settings.localshell",
    },
    SettingsSectionMeta {
        name: "Machines",
        icon: "computer-symbolic",
        css_class: "wwn-icon-indigo",
        a11y_id: "wwn.settings.machines",
    },
    SettingsSectionMeta {
        name: "Waypipe",
        icon: "network-wireless-symbolic",
        css_class: "wwn-icon-blue",
        a11y_id: "wwn.settings.waypipe",
    },
    SettingsSectionMeta {
        name: "SSH",
        icon: "channel-secure-symbolic",
        css_class: "wwn-icon-slate",
        a11y_id: "wwn.settings.ssh",
    },
    SettingsSectionMeta {
        name: "About",
        icon: "help-about-symbolic",
        css_class: "wwn-icon-purple",
        a11y_id: "wwn.settings.about",
    },
    SettingsSectionMeta {
        name: "Dependencies",
        icon: "package-x-generic-symbolic",
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
        icon: "utilities-system-monitor-symbolic",
        css_class: "wwn-icon-orange",
        a11y_id: "wwn.settings.diagnostics",
    },
];

pub fn show_settings(parent: &adw::ApplicationWindow, state: &SharedAppState, layout: LayoutMode) {
    wlog!("UI", "Settings dialog opened");
    ensure_settings_css();

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
    sidebar.set_width_request(200);
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

    // MARK: Display
    let display_page = adw::PreferencesPage::new();
    let display_group = adw::PreferencesGroup::new();
    display_group.set_title("Display");
    display_group.set_description(Some(
        "Nested compositor presentation, color management, and window decorations.",
    ));
    let color_ops = gtk::Switch::new();
    color_ops.set_active(settings.color_operations);
    add_switch_row(&display_group, "Color Operations / HDR", &color_ops);
    add_choice_row(
        &display_group,
        "Display Backend",
        &["auto", "wayland", "drm"],
        compositor_backend_value.clone(),
        open_choice.clone(),
    );
    let nested_compositors_switch = gtk::Switch::new();
    nested_compositors_switch.set_active(settings.nested_compositors);
    add_switch_row(
        &display_group,
        "Nested Compositors",
        &nested_compositors_switch,
    );
    let multiple_clients_switch = gtk::Switch::new();
    multiple_clients_switch.set_active(settings.multiple_clients);
    add_switch_row(
        &display_group,
        "Multiple Clients",
        &multiple_clients_switch,
    );
    let force_ssd_switch = gtk::Switch::new();
    force_ssd_switch.set_active(settings.force_ssd);
    add_switch_row(
        &display_group,
        "Force Server-Side Decorations",
        &force_ssd_switch,
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
        "Keyboard repeat rates, touch interaction, and clipboard synchronization.",
    ));
    let input_profile = gtk::Entry::new();
    input_profile.set_text(&settings.input_profile);
    let key_repeat = gtk::SpinButton::with_range(1.0, 60.0, 1.0);
    key_repeat.set_value(settings.key_repeat as f64);
    add_entry_row(&input_group, "Default Input Profile", &input_profile);
    add_row(&input_group, "Key Repeat", &key_repeat);
    let touch_pointer_switch = gtk::Switch::new();
    touch_pointer_switch.set_active(settings.touch_pointer_emulation);
    add_switch_row(
        &input_group,
        "Pointer Emulation for Touch",
        &touch_pointer_switch,
    );
    let virtual_cursor_switch = gtk::Switch::new();
    virtual_cursor_switch.set_active(settings.show_virtual_cursor);
    add_switch_row(&input_group, "Show Virtual Cursor", &virtual_cursor_switch);
    let universal_clipboard_switch = gtk::Switch::new();
    universal_clipboard_switch.set_active(settings.universal_clipboard);
    add_switch_row(
        &input_group,
        "Universal Clipboard",
        &universal_clipboard_switch,
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
        "Rendering subsystem, hardware acceleration drivers, and buffer formats.",
    ));
    add_choice_row(
        &graphics_group,
        "Renderer",
        &["vulkan", "software"],
        renderer_value.clone(),
        open_choice.clone(),
    );
    add_choice_row(
        &graphics_group,
        "Vulkan Driver",
        &["system", "swiftshader", "none"],
        vulkan_driver_value.clone(),
        open_choice.clone(),
    );
    add_choice_row(
        &graphics_group,
        "OpenGL Driver",
        &["system", "angle", "none"],
        opengl_driver_value.clone(),
        open_choice.clone(),
    );
    let dmabuf_switch = gtk::Switch::new();
    dmabuf_switch.set_active(settings.dmabuf_enabled);
    add_switch_row(&graphics_group, "Enable DMABUF", &dmabuf_switch);
    graphics_page.add(&graphics_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &graphics_page,
        crate::linux::ui::a11y::id::SETTINGS_GRAPHICS,
        Some("Graphics"),
    );
    stack.add_named(&graphics_page, Some("Graphics"));

    // MARK: Connection
    let connection_page = adw::PreferencesPage::new();
    let connection_group = adw::PreferencesGroup::new();
    connection_group.set_title("Connection");
    connection_group.set_description(Some(
        "Compositor socket endpoint and network listener settings.",
    ));
    let wayland_display = gtk::Entry::new();
    wayland_display.set_text(&settings.wayland_display);
    add_entry_row(&connection_group, "Wayland Display", &wayland_display);
    let tcp_port = gtk::SpinButton::with_range(1024.0, 65535.0, 1.0);
    tcp_port.set_value(settings.tcp_port as f64);
    add_row(&connection_group, "TCP Listener Port", &tcp_port);
    connection_page.add(&connection_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &connection_page,
        "wwn.settings.connection",
        Some("Connection"),
    );
    stack.add_named(&connection_page, Some("Connection"));

    // MARK: Environment Variables
    let env_page = adw::PreferencesPage::new();
    let env_group = adw::PreferencesGroup::new();
    env_group.set_title("Environment Variables");
    env_group.set_description(Some(
        "Global KEY=value overrides applied to launched clients (machine overrides win). \
         Lines starting with -NAME unset a variable. Matches Apple and Android Settings.",
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

    let env_actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    env_actions.set_margin_top(8);
    let reset_managed_btn = gtk::Button::with_label("Reset Wawona-managed");
    let clear_all_btn = gtk::Button::with_label("Clear All");
    env_actions.append(&reset_managed_btn);
    env_actions.append(&clear_all_btn);
    {
        let buffer = env_text.buffer();
        reset_managed_btn.connect_clicked(move |_| {
            buffer.set_text("XDG_CURRENT_DESKTOP=Wawona\nWAYLAND_DISPLAY=wawona-0\n");
        });
    }
    {
        let buffer = env_text.buffer();
        clear_all_btn.connect_clicked(move |_| {
            buffer.set_text("");
        });
    }
    env_group.add(&env_actions);
    env_page.add(&env_group);
    crate::linux::ui::a11y::set_wwn_a11y(
        &env_page,
        crate::linux::ui::a11y::id::SETTINGS_ENVIRONMENT,
        Some("Env Vars"),
    );
    stack.add_named(&env_page, Some("Env Vars"));

    // MARK: Local Shell
    let shell_page = adw::PreferencesPage::new();
    let shell_group = adw::PreferencesGroup::new();
    shell_group.set_title("Local Shell");
    shell_group.set_description(Some(
        "Linux uses your host login environment. Sandboxed rootfs reset does not apply.",
    ));
    let home = std::env::var("HOME").unwrap_or_else(|_| "(unset)".into());
    let user = std::env::var("USER").unwrap_or_else(|_| "user".into());
    let shell_prog = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
    add_info_row(&shell_group, "User", &user);
    add_info_row(&shell_group, "Shell", &shell_prog);
    add_info_row(&shell_group, "HOME Path", &home);
    let open_home = gtk::Button::with_label("Open HOME in File Manager");
    {
        let home_path = home.clone();
        open_home.connect_clicked(move |_| {
            let _ = std::process::Command::new("xdg-open")
                .arg(&home_path)
                .spawn();
        });
    }
    add_row(&shell_group, "Open HOME", &open_home);
    shell_page.add(&shell_group);
    stack.add_named(&shell_page, Some("Local Shell"));

    // MARK: Machines
    let machines_page = adw::PreferencesPage::new();
    let machines_group = adw::PreferencesGroup::new();
    machines_group.set_title("Machine Defaults");
    machines_group.set_description(Some(
        "Global options applied across sessions. Per-machine overrides live in Machine Configuration.",
    ));
    add_choice_row(
        &machines_group,
        "Default Renderer",
        &["vulkan", "software"],
        renderer_value.clone(),
        open_choice.clone(),
    );
    let thumbnails_switch = gtk::Switch::new();
    thumbnails_switch.set_active(settings.session_thumbnails);
    add_switch_row(
        &machines_group,
        "Session Thumbnails",
        &thumbnails_switch,
    );
    let shake_switch = gtk::Switch::new();
    shake_switch.set_active(settings.shake_to_close);
    add_switch_row(&machines_group, "Shake to Exit Machine", &shake_switch);
    let swipe_switch = gtk::Switch::new();
    swipe_switch.set_active(settings.swipe_back_to_close);
    add_switch_row(&machines_group, "Swipe Back to Exit Machine", &swipe_switch);
    machines_page.add(&machines_group);

    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machines");
    add_info_row(
        &vm_group,
        "Virtual Machine Engine",
        "Wawona Relay (KVM via cloud-hypervisor or crosvm). Fail closed without /dev/kvm.",
    );
    let vm_vsock_port = gtk::SpinButton::with_range(1024.0, 65535.0, 1.0);
    vm_vsock_port.set_value(settings.vm_vsock_port as f64);
    add_row(&vm_group, "VSock Port", &vm_vsock_port);
    machines_page.add(&vm_group);

    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Containers");
    add_info_row(
        &container_group,
        "Container Runtime",
        "OCI-in-VM. Containers unpack OCI images, then run on the same Relay KVM VM.",
    );
    let container_image_store = gtk::Entry::new();
    container_image_store.set_text(&settings.container_image_store);
    add_entry_row(&container_group, "Image Store", &container_image_store);
    machines_page.add(&container_group);
    stack.add_named(&machines_page, Some("Machines"));

    // MARK: Waypipe
    let waypipe_page = adw::PreferencesPage::new();
    let waypipe_group = adw::PreferencesGroup::new();
    waypipe_group.set_title("Waypipe Parameters");
    waypipe_group.set_description(Some(
        "Wayland protocol proxy configuration for remote streaming over SSH or unix sockets.",
    ));
    let wp_enabled = gtk::Switch::new();
    wp_enabled.set_active(settings.waypipe_enabled);
    add_switch_row(&waypipe_group, "Default Waypipe Enabled", &wp_enabled);
    let wp_display = gtk::SpinButton::with_range(0.0, 99.0, 1.0);
    wp_display.set_value(settings.waypipe_display as f64);
    add_row(&waypipe_group, "Display Number", &wp_display);
    let wp_socket = gtk::Entry::new();
    wp_socket.set_text(&settings.waypipe_socket);
    wp_socket.set_placeholder_text(Some("/tmp/waypipe.sock (leave blank for auto)"));
    add_entry_row(&waypipe_group, "Socket Path", &wp_socket);
    add_choice_row(
        &waypipe_group,
        "Compression",
        &["lz4", "zstd", "none"],
        wp_compress_value.clone(),
        open_choice.clone(),
    );
    let wp_compress_level = gtk::SpinButton::with_range(1.0, 22.0, 1.0);
    wp_compress_level.set_value(settings.waypipe_compress_level as f64);
    add_row(&waypipe_group, "Compression Level", &wp_compress_level);
    let wp_threads = gtk::SpinButton::with_range(0.0, 32.0, 1.0);
    wp_threads.set_value(settings.waypipe_threads as f64);
    add_row(&waypipe_group, "Worker Threads", &wp_threads);
    add_choice_row(
        &waypipe_group,
        "Video Compression",
        &["none", "h264", "vp9", "av1"],
        wp_video_value.clone(),
        open_choice.clone(),
    );
    add_choice_row(
        &waypipe_group,
        "Video Encoding",
        &["hw", "sw", "hwenc", "swenc"],
        wp_video_enc_value.clone(),
        open_choice.clone(),
    );
    add_choice_row(
        &waypipe_group,
        "Video Decoding",
        &["hw", "sw", "hwdec", "swdec"],
        wp_video_dec_value.clone(),
        open_choice.clone(),
    );
    let wp_video_bpf = gtk::Entry::new();
    wp_video_bpf.set_text(&settings.waypipe_video_bpf);
    wp_video_bpf.set_placeholder_text(Some("e.g. 5000000 (empty = auto)"));
    add_entry_row(&waypipe_group, "Bits Per Frame", &wp_video_bpf);
    let wp_remote_cmd = gtk::Entry::new();
    wp_remote_cmd.set_text(&settings.waypipe_remote_command);
    wp_remote_cmd.set_placeholder_text(Some("e.g. weston-terminal"));
    add_entry_row(&waypipe_group, "Remote Command", &wp_remote_cmd);
    let wp_title_prefix = gtk::Entry::new();
    wp_title_prefix.set_text(&settings.waypipe_title_prefix);
    wp_title_prefix.set_placeholder_text(Some("e.g. Remote:"));
    add_entry_row(&waypipe_group, "Title Prefix", &wp_title_prefix);
    let wp_no_gpu = gtk::Switch::new();
    wp_no_gpu.set_active(settings.waypipe_no_gpu);
    add_switch_row(&waypipe_group, "Disable GPU (Force SHM)", &wp_no_gpu);
    let wp_oneshot = gtk::Switch::new();
    wp_oneshot.set_active(settings.waypipe_oneshot);
    add_switch_row(&waypipe_group, "One-shot Exit", &wp_oneshot);
    let wp_unlink_socket = gtk::Switch::new();
    wp_unlink_socket.set_active(settings.waypipe_unlink_socket);
    add_switch_row(&waypipe_group, "Unlink Socket on Exit", &wp_unlink_socket);
    let wp_login_shell = gtk::Switch::new();
    wp_login_shell.set_active(settings.waypipe_login_shell);
    add_switch_row(&waypipe_group, "Login Shell", &wp_login_shell);
    let wp_debug = gtk::Switch::new();
    wp_debug.set_active(settings.waypipe_debug);
    add_switch_row(&waypipe_group, "Debug Mode", &wp_debug);
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
    let ssh_host = gtk::Entry::new();
    ssh_host.set_text(&settings.ssh_host);
    ssh_host.set_placeholder_text(Some("host.example.com"));
    let ssh_user = gtk::Entry::new();
    ssh_user.set_text(&settings.ssh_user);
    ssh_user.set_placeholder_text(Some("username"));
    let ssh_port = gtk::SpinButton::with_range(1.0, 65535.0, 1.0);
    ssh_port.set_value(settings.ssh_port as f64);
    let ssh_password = gtk::PasswordEntry::builder().show_peek_icon(true).build();
    ssh_password.set_text(&settings.ssh_password);
    add_entry_row(&ssh_group, "Host", &ssh_host);
    add_entry_row(&ssh_group, "User", &ssh_user);
    add_row(&ssh_group, "Port", &ssh_port);
    add_choice_row(
        &ssh_group,
        "Auth Method",
        &["public_key", "password"],
        ssh_auth_method_value.clone(),
        open_choice.clone(),
    );
    add_entry_row(&ssh_group, "Password", &ssh_password);
    let ssh_key_path = gtk::Entry::new();
    ssh_key_path.set_text(&settings.ssh_key_path);
    ssh_key_path.set_placeholder_text(Some("~/.ssh/id_ed25519"));
    add_entry_row(&ssh_group, "Key Path", &ssh_key_path);
    let ssh_key_passphrase = gtk::PasswordEntry::builder().show_peek_icon(true).build();
    ssh_key_passphrase.set_text(&settings.ssh_key_passphrase);
    add_entry_row(&ssh_group, "Key Passphrase", &ssh_key_passphrase);
    add_choice_row(
        &ssh_group,
        "Key Type",
        &["ed25519", "ecdsa", "rsa"],
        ssh_key_type_value.clone(),
        open_choice.clone(),
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
                let mut detail = String::new();
                if !version.is_empty() {
                    detail.push_str(version);
                }
                if !license.is_empty() {
                    if !detail.is_empty() {
                        detail.push_str(" · ");
                    }
                    detail.push_str(license);
                }
                if !role.is_empty() {
                    if !detail.is_empty() {
                        detail.push_str(". ");
                    }
                    detail.push_str(role);
                }
                if !url.is_empty() {
                    add_dependency_row(&deps_group, name, &detail, url);
                } else {
                    add_info_row(&deps_group, name, &detail);
                }
            }
        }
    }
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
    diag_page.add(&diag_group);
    stack.add_named(&diag_page, Some("Diagnostics"));

    // MARK: About
    let about_page = adw::PreferencesPage::new();

    let banner = adw::PreferencesGroup::new();
    let mark = adw::ActionRow::new();
    mark.set_title("Wawona");
    mark.set_subtitle(&format!("v{}", version()));
    let icon = gtk::Image::from_icon_name("wawona");
    icon.set_pixel_size(64);
    mark.add_prefix(&icon);
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
    add_choice_row(
        &facts,
        "Log Level",
        &["debug", "info", "warn", "error"],
        log_level_value.clone(),
        open_choice.clone(),
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
                if idx < SETTINGS_SECTIONS.len() {
                    stack.set_visible_child_name(SETTINGS_SECTIONS[idx].name);
                }
            }
        });
    }
    if let Some(first_row) = sidebar.row_at_index(0) {
        sidebar.select_row(Some(&first_row));
    }

    let split = gtk::Paned::new(gtk::Orientation::Horizontal);
    split.set_position(210);
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
        app.settings.compositor_backend = compositor_backend_value.borrow().clone();
        app.settings.nested_compositors = nested_compositors_switch.is_active();
        app.settings.multiple_clients = multiple_clients_switch.is_active();
        app.settings.input_profile = input_profile.text().to_string();
        app.settings.key_repeat = key_repeat.value() as u32;
        app.settings.touch_pointer_emulation = touch_pointer_switch.is_active();
        app.settings.show_virtual_cursor = virtual_cursor_switch.is_active();
        app.settings.universal_clipboard = universal_clipboard_switch.is_active();
        app.settings.renderer = renderer_value.borrow().clone();
        app.settings.force_ssd = force_ssd_switch.is_active();
        app.settings.color_operations = color_ops.is_active();
        app.settings.vulkan_driver = vulkan_driver_value.borrow().clone();
        app.settings.opengl_driver = opengl_driver_value.borrow().clone();
        app.settings.dmabuf_enabled = dmabuf_switch.is_active();
        app.settings.tcp_port = tcp_port.value() as u16;
        app.settings.ssh_host = ssh_host.text().to_string();
        app.settings.ssh_user = ssh_user.text().to_string();
        app.settings.ssh_port = ssh_port.value() as u16;
        app.settings.ssh_password = ssh_password.text().to_string();
        app.settings.ssh_auth_method = ssh_auth_method_value.borrow().clone();
        app.settings.ssh_key_path = ssh_key_path.text().to_string();
        app.settings.ssh_key_passphrase = ssh_key_passphrase.text().to_string();
        app.settings.ssh_key_type = ssh_key_type_value.borrow().clone();
        app.settings.session_thumbnails = thumbnails_switch.is_active();
        app.settings.shake_to_close = shake_switch.is_active();
        app.settings.swipe_back_to_close = swipe_switch.is_active();
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
    linux_open_url(&url);
}

fn linux_open_url(url: &str) {
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn linux_generate_ssh_key(key_type: &str, path: &str, passphrase: &str) -> Result<String, String> {
    let expanded_path = if let Some(stripped) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            format!("{home}/{stripped}")
        } else {
            path.to_string()
        }
    } else {
        path.to_string()
    };
    if let Some(parent) = std::path::Path::new(&expanded_path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let status = std::process::Command::new("ssh-keygen")
        .args(["-t", key_type, "-f", &expanded_path, "-N", passphrase, "-q"])
        .status();
    match status {
        Ok(s) if s.success() => Ok(format!("Key created at {path}")),
        Ok(s) => Err(format!("ssh-keygen exited with code {}", s.code().unwrap_or(-1))),
        Err(e) => Err(format!("Failed to run ssh-keygen: {e}")),
    }
}

fn linux_test_ssh_connection(host: &str, user: &str, port: u16) -> Result<String, String> {
    if host.trim().is_empty() {
        return Err("Host cannot be empty".to_string());
    }
    let target = if user.trim().is_empty() {
        host.trim().to_string()
    } else {
        format!("{}@{}", user.trim(), host.trim())
    };
    let status = std::process::Command::new("ssh")
        .args([
            "-p",
            &port.to_string(),
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            &target,
            "true",
        ])
        .status();
    match status {
        Ok(s) if s.success() => Ok(format!("Connection to {target} succeeded")),
        Ok(s) => Err(format!("SSH exited with code {}", s.code().unwrap_or(-1))),
        Err(e) => Err(format!("Failed to run ssh: {e}")),
    }
}

/// Same order and subtitles as `WawonaAboutLinks` in SettingsContracts.swift.
const WAWN_ABOUT_LINKS: &[(&str, &str, &str, &str)] = &[
    (
        "Website",
        "Wawona.io",
        "https://wawona.io",
        "https://wawona.io/favicon.ico",
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
    let image = gtk::Image::new();
    image.set_pixel_size(28);
    image.set_overflow(gtk::Overflow::Hidden);
    image.add_css_class("wwn-favicon");
    row.add_prefix(&image);
    load_about_favicon(&image, icon);
    let open_url = url.to_string();
    row.connect_activated(move |_| {
        linux_open_url(&open_url);
    });
    group.add(&row);
}

fn ensure_settings_css() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            ".wwn-favicon { border-radius: 6px; }\n\
             .wwn-icon-blue { color: #3584e4; }\n\
             .wwn-icon-purple { color: #9141ac; }\n\
             .wwn-icon-red { color: #e01b24; }\n\
             .wwn-icon-orange { color: #ff7800; }\n\
             .wwn-icon-teal { color: #00bfa5; }\n\
             .wwn-icon-green { color: #2ec27e; }\n\
             .wwn-icon-indigo { color: #7851a9; }\n\
             .wwn-icon-slate { color: #5f6368; }\n\
             .wwn-icon-brown { color: #986a44; }\n",
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

fn load_about_favicon(image: &gtk::Image, icon: &str) {
    if let Some(name) = icon.strip_prefix("bundle:") {
        if let Some(bytes) = bundled_about_png(name) {
            set_favicon_bytes(image, bytes);
        }
        return;
    }
    let url = icon.to_string();
    let cache = favicon_cache_file(&url);
    if let Ok(bytes) = std::fs::read(&cache) {
        set_favicon_bytes(image, &bytes);
    }
    let (sender, receiver) = std::sync::mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        let Some(fetched) = fetch_favicon_bytes(&url) else {
            return;
        };
        let changed = std::fs::read(&cache).ok().as_deref() != Some(fetched.as_slice());
        if !changed {
            return;
        }
        if let Some(parent) = cache.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if std::fs::write(&cache, &fetched).is_ok() {
            let _ = sender.send(fetched);
        }
    });
    let image = image.clone();
    glib::timeout_add_local(std::time::Duration::from_millis(200), move || {
        match receiver.try_recv() {
            Ok(bytes) => {
                set_favicon_bytes(&image, &bytes);
                glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
        }
    });
}

fn set_favicon_bytes(image: &gtk::Image, bytes: &[u8]) {
    let gbytes = glib::Bytes::from(bytes);
    if let Ok(texture) = gtk::gdk::Texture::from_bytes(&gbytes) {
        image.set_paintable(Some(&texture));
    }
}

fn bundled_about_png(name: &str) -> Option<&'static [u8]> {
    match name {
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
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(".cache"))
        })
        .unwrap_or_else(|| std::path::PathBuf::from("/tmp"));
    base.join("wawona")
        .join("favicons")
        .join(format!("{:x}", fnv64(url.as_bytes())))
}

fn fetch_favicon_bytes(url: &str) -> Option<Vec<u8>> {
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

fn add_dependency_row(group: &adw::PreferencesGroup, title: &str, subtitle: &str, url: &str) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_subtitle(subtitle);
    row.set_subtitle_lines(0);
    row.set_activatable(true);
    let chevron = gtk::Image::from_icon_name("go-next-symbolic");
    row.add_suffix(&chevron);
    let open_url = url.to_string();
    row.connect_activated(move |_| {
        linux_open_url(&open_url);
    });
    group.add(&row);
}

fn add_switch_row(group: &adw::PreferencesGroup, title: &str, switch: &gtk::Switch) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    switch.set_valign(gtk::Align::Center);
    row.add_suffix(switch);
    row.set_activatable_widget(Some(switch));
    group.add(&row);
}

fn add_entry_row(group: &adw::PreferencesGroup, title: &str, entry: &impl IsA<gtk::Widget>) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    entry.set_valign(gtk::Align::Center);
    row.add_suffix(entry);
    row.set_activatable(false);
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

fn add_info_row(group: &adw::PreferencesGroup, title: &str, value: &str) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_subtitle(value);
    row.set_subtitle_lines(0);
    group.add(&row);
}

fn add_choice_row(
    group: &adw::PreferencesGroup,
    title: &str,
    choices: &[&str],
    value: Rc<RefCell<String>>,
    open_choice: Rc<dyn Fn(String, Vec<String>, Rc<RefCell<String>>, gtk::Label)>,
) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.set_activatable(true);
    let val_label = gtk::Label::new(Some(&value.borrow()));
    val_label.add_css_class("dim-label");
    row.add_suffix(&val_label);
    let chevron = gtk::Image::from_icon_name("go-next-symbolic");
    row.add_suffix(&chevron);
    let title_s = title.to_string();
    let choices_v: Vec<String> = choices.iter().map(|s| s.to_string()).collect();
    row.connect_activated(move |_| {
        open_choice(
            title_s.clone(),
            choices_v.clone(),
            value.clone(),
            val_label.clone(),
        );
    });
    group.add(&row);
}
