//! In-app per-machine profile configuration view.
//!
//! Uses native Libadwaita PreferencesPage, EntryRow, SwitchRow, ComboRow, and
//! SpinRow widgets for modern, responsive HIG styling.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use gtk4 as gtk;
use gtk4::{gio, glib};
use libadwaita as adw;

use adw::prelude::*;
use gtk::prelude::*;

use crate::domain::machine_profile::{
    ContainerMachineSettings, DomainEnvironmentOverride, MachineProfile, MachineType,
    VirtualMachineSettings,
};
use crate::linux::ui::home::{rebuild_home, HomeShell, MachineSessions, RebuildHome};
use crate::linux::ui::modal_sheet::present_sheet;
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;
use crate::wlog;

pub fn build_editor_view(
    state: &SharedAppState,
    existing: Option<MachineProfile>,
    default_type: MachineType,
    _sessions: MachineSessions,
    on_close: Rc<dyn Fn(bool)>,
) -> gtk::Box {
    let is_new = existing.is_none();
    let title = if is_new {
        "Add Machine Profile"
    } else {
        "Edit Machine Profile"
    };

    let mut profile = existing.unwrap_or_else(|| MachineProfile {
        id: crate::domain::machine_profile::new_uuid(),
        ..MachineProfile::default()
    });
    if is_new {
        profile.machine_type = default_type;
    }
    let baseline = profile.clone();

    // Toolbar: Cancel leading, Save trailing.
    let header = adw::HeaderBar::new();
    header.set_show_end_title_buttons(false);
    header.set_show_start_title_buttons(false);
    let cancel_btn = gtk::Button::with_label("Cancel");
    let save_btn = gtk::Button::with_label("Save");
    save_btn.add_css_class("suggested-action");
    header.pack_start(&cancel_btn);
    header.pack_end(&save_btn);
    let title_lbl = gtk::Label::new(Some(title));
    title_lbl.add_css_class("title");
    header.set_title_widget(Some(&title_lbl));

    // MARK: Connection Profile
    let profile_group = adw::PreferencesGroup::new();
    profile_group.set_title("Connection Profile");
    profile_group.set_description(Some("Name, type, and favorite status for this machine profile."));

    let name_row = adw::EntryRow::new();
    name_row.set_title("Display Name");
    name_row.set_text(&profile.name);
    profile_group.add(&name_row);

    let mt_items: Vec<(&str, &str)> = vec![
        ("native", "Native Shell"),
        ("wasm", "Relay Wasm"),
        ("ssh_waypipe", "SSH + Waypipe"),
        ("ssh_terminal", "SSH Terminal"),
        ("virtual_machine", "Virtual Machine (Linux)"),
        ("container", "Container (OCI)"),
    ];
    let ui_type = match profile.machine_type {
        MachineType::Wasm | MachineType::SshWaypipe | MachineType::SshTerminal => {
            MachineType::Native
        }
        other => other,
    };
    let (type_row, type_ids) = make_combo_row("Type", &mt_items, &mt_id(ui_type));
    profile_group.add(&type_row);

    let favorite_row = adw::SwitchRow::new();
    favorite_row.set_title("Favorite Machine");
    favorite_row.set_active(profile.favorite);
    profile_group.add(&favorite_row);

    let (initial_session, initial_use_ssh) = native_shell_session_from(&profile);
    let session_group = adw::PreferencesGroup::new();
    session_group.set_title("Native Shell Session");
    session_group.set_description(Some(
        "Terminal is Wawona Terminal (local or SSH). Wasm runs Relay packages. Waypipe streams with optional SSH.",
    ));

    let session_items = [
        ("terminal", "Terminal"),
        ("wasm", "Wasm"),
        ("waypipe", "Waypipe"),
    ];
    let session_id = if initial_session == "wayland" {
        "terminal"
    } else {
        initial_session
    };
    let (session_row, session_ids) = make_combo_row("Session", &session_items, session_id);
    session_group.add(&session_row);

    let use_ssh_row = adw::SwitchRow::new();
    use_ssh_row.set_title("Use SSH");
    use_ssh_row.set_active(initial_use_ssh);
    session_group.add(&use_ssh_row);

    let terminal_custom_row = adw::EntryRow::new();
    terminal_custom_row.set_title("Custom Command");
    terminal_custom_row.set_text(&profile.remote_command);
    session_group.add(&terminal_custom_row);

    let wasm_group = adw::PreferencesGroup::new();
    wasm_group.set_title("Wasm");
    wasm_group.set_description(Some(
        "Same as native shell: wasm hello-wasi-gui. Local file, package name, or typed command.",
    ));

    let wasm_cmd_row = adw::EntryRow::new();
    wasm_cmd_row.set_title("Command");
    wasm_cmd_row.set_text(
        profile
            .runtime_overrides
            .wasm_command
            .as_deref()
            .unwrap_or("wasm hello-wasi-gui"),
    );
    wasm_group.add(&wasm_cmd_row);

    let wasm_pkg_row = adw::EntryRow::new();
    wasm_pkg_row.set_title("Package");
    wasm_pkg_row.set_text(
        profile
            .runtime_overrides
            .wasm_package
            .as_deref()
            .unwrap_or(""),
    );
    wasm_group.add(&wasm_pkg_row);

    let wasm_path_row = adw::EntryRow::new();
    wasm_path_row.set_title("Local .wasm Path");
    wasm_path_row.set_text(
        profile
            .runtime_overrides
            .wasm_module_path
            .as_deref()
            .unwrap_or(""),
    );
    let wasm_pick = gtk::Button::with_label("Browse…");
    wasm_path_row.add_suffix(&wasm_pick);
    wasm_group.add(&wasm_path_row);

    let wasm_search_row = adw::ActionRow::new();
    wasm_search_row.set_title("Catalog Repository");
    wasm_search_row.set_subtitle("Search catalog packages on repo.wawona.io");
    let wasm_search = gtk::Button::with_label("Search");
    wasm_search_row.add_suffix(&wasm_search);
    wasm_group.add(&wasm_search_row);

    let wasm_note = gtk::Label::new(None);
    wasm_note.set_wrap(true);
    wasm_note.set_xalign(0.0);
    wasm_note.add_css_class("dim-label");
    wasm_group.add(&wasm_note);

    let wasm_results = gtk::ListBox::new();
    wasm_results.set_selection_mode(gtk::SelectionMode::None);
    wasm_group.add(&wasm_results);

    for local in crate::linux::wasm_launch::list_local_modules() {
        let row = adw::ActionRow::new();
        row.set_title(
            local
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| local.display().to_string())
                .as_str(),
        );
        row.set_subtitle(&local.display().to_string());
        row.set_activatable(true);
        let wasm_path_c = wasm_path_row.clone();
        let wasm_cmd_c = wasm_cmd_row.clone();
        let path_s = local.display().to_string();
        let gesture = gtk::GestureClick::new();
        gesture.connect_released(move |_, _, _, _| {
            wasm_path_c.set_text(&path_s);
            wasm_cmd_c.set_text(&format!("wasm {path_s}"));
        });
        row.add_controller(gesture);
        wasm_group.add(&row);
    }

    {
        let wasm_pick_btn = wasm_pick.clone();
        let wasm_path_c = wasm_path_row.clone();
        wasm_pick.connect_clicked(move |_| {
            let dialog = gtk::FileDialog::builder()
                .title("Select .wasm module")
                .modal(true)
                .build();
            let filter = gtk::FileFilter::new();
            filter.set_name(Some("WebAssembly module (*.wasm)"));
            filter.add_pattern("*.wasm");
            let filters = gio::ListStore::new::<gtk::FileFilter>();
            filters.append(&filter);
            dialog.set_filters(Some(&filters));
            let wasm_path_c = wasm_path_c.clone();
            let win = wasm_pick_btn.root().and_then(|r| r.downcast::<gtk::Window>().ok());
            dialog.open(win.as_ref(), None::<&gio::Cancellable>, move |result| {
                if let Ok(file) = result {
                    if let Some(path) = file.path() {
                        wasm_path_c.set_text(&path.to_string_lossy());
                    }
                }
            });
        });
    }

    {
        let wasm_results_c = wasm_results.clone();
        let wasm_path_c = wasm_path_row.clone();
        let wasm_cmd_c = wasm_cmd_row.clone();
        let wasm_pkg_c = wasm_pkg_row.clone();
        let wasm_note_c = wasm_note.clone();
        wasm_search.connect_clicked(move |_| {
            let q = wasm_pkg_c.text().trim().to_string();
            let results_list = wasm_results_c.clone();
            let path_entry = wasm_path_c.clone();
            let cmd_entry = wasm_cmd_c.clone();
            let note = wasm_note_c.clone();
            note.set_text("Searching catalog…");
            while let Some(child) = results_list.first_child() {
                results_list.remove(&child);
            }
            let (tx, rx) = std::sync::mpsc::channel::<Result<Vec<crate::linux::wasm_launch::CatalogPackage>, String>>();
            let note_poll = note.clone();
            let results_poll = results_list.clone();
            let path_poll = path_entry.clone();
            let cmd_poll = cmd_entry.clone();
            glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                match rx.try_recv() {
                    Ok(items) => {
                        note_poll.set_text("");
                        match items {
                            Ok(found) => {
                                if found.is_empty() {
                                    note_poll.set_text("No catalog matches found.");
                                }
                                for item in found {
                                    let row = adw::ActionRow::new();
                                    row.set_title(&item.name);
                                    let sub = format!(
                                        "{} • v{}",
                                        item.summary,
                                        item.version,
                                    );
                                    row.set_subtitle(&sub);
                                    row.set_activatable(true);
                                    let name = item.name.clone();
                                    let pe = path_poll.clone();
                                    let ce = cmd_poll.clone();
                                    let pte = path_poll.clone();
                                    let nte = note_poll.clone();
                                    let gesture = gtk::GestureClick::new();
                                    gesture.connect_released(move |_, _, _, _| {
                                        pe.set_text(&name);
                                        ce.set_text(&format!("wasm {name}"));
                                        nte.set_text("Downloading…");
                                        let name_c = name.clone();
                                        let (tx_dl, rx_dl) = std::sync::mpsc::channel::<Option<std::path::PathBuf>>();
                                        let pte_c = pte.clone();
                                        let nte_c = nte.clone();
                                        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
                                            match rx_dl.try_recv() {
                                                Ok(Some(p)) => {
                                                    pte_c.set_text(&p.display().to_string());
                                                    nte_c.set_text("Ready");
                                                    glib::ControlFlow::Break
                                                }
                                                Ok(None) => {
                                                    nte_c.set_text("Download failed");
                                                    glib::ControlFlow::Break
                                                }
                                                Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                                                Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                                            }
                                        });
                                        std::thread::spawn(move || {
                                            let res = crate::linux::wasm_launch::ensure_package_file(&name_c);
                                            let _ = tx_dl.send(res);
                                        });
                                    });
                                    row.add_controller(gesture);
                                    results_poll.append(&row);
                                }
                            }
                            Err(e) => note_poll.set_text(&e),
                        }
                        glib::ControlFlow::Break
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => glib::ControlFlow::Continue,
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => glib::ControlFlow::Break,
                }
            });
            std::thread::spawn(move || {
                let found = crate::linux::wasm_launch::search_catalog(&q);
                let _ = tx.send(found);
            });
        });
    }

    // MARK: SSH + Waypipe / SSH Connection (Remote)
    let remote_group = adw::PreferencesGroup::new();
    let host_row = adw::EntryRow::new();
    host_row.set_title("Host");
    host_row.set_text(&profile.ssh_host);
    remote_group.add(&host_row);

    let user_row = adw::EntryRow::new();
    user_row.set_title("User");
    user_row.set_text(&profile.ssh_user);
    remote_group.add(&user_row);

    let port_row = adw::EntryRow::new();
    port_row.set_title("Port");
    port_row.set_text(&profile.ssh_port.to_string());
    remote_group.add(&port_row);

    let auth_items = [("0", "Password"), ("1", "Public Key")];
    let (auth_method_row, auth_ids) = make_combo_row(
        "Authentication Method",
        &auth_items,
        if profile.ssh_auth_method == 1 { "1" } else { "0" },
    );
    remote_group.add(&auth_method_row);

    let password_row = adw::PasswordEntryRow::new();
    password_row.set_title("Password");
    password_row.set_text(&profile.ssh_password);
    remote_group.add(&password_row);

    let key_path_row = adw::EntryRow::new();
    key_path_row.set_title("Key Path");
    key_path_row.set_text(&profile.ssh_key_path);
    remote_group.add(&key_path_row);

    let key_passphrase_row = adw::PasswordEntryRow::new();
    key_passphrase_row.set_title("Key Passphrase");
    key_passphrase_row.set_text(&profile.ssh_key_passphrase);
    remote_group.add(&key_passphrase_row);

    let cmd_row = adw::EntryRow::new();
    cmd_row.set_title("Remote Command");
    cmd_row.set_text(&profile.remote_command);
    remote_group.add(&cmd_row);

    // MARK: Command Preview (Remote)
    let preview_group = adw::PreferencesGroup::new();
    preview_group.set_title("Command Preview");
    preview_group.set_description(Some("Effective launch command for this machine profile."));
    let preview_lbl = gtk::Label::new(None);
    preview_lbl.set_xalign(0.0);
    preview_lbl.set_wrap(true);
    preview_lbl.set_selectable(true);
    preview_lbl.add_css_class("dim-label");
    preview_lbl.add_css_class("monospace");
    preview_lbl.set_margin_top(6);
    preview_lbl.set_margin_bottom(6);
    preview_lbl.set_margin_start(10);
    preview_lbl.set_margin_end(10);
    let preview_frame = gtk::Frame::new(None);
    preview_frame.add_css_class("card");
    preview_frame.set_child(Some(&preview_lbl));
    preview_group.add(&preview_frame);

    // MARK: Display / Input / Graphics
    let dig_group = adw::PreferencesGroup::new();
    dig_group.set_title("Display / Input / Graphics");
    dig_group.set_description(Some(
        "Per-machine overrides for global Display, Input, Graphics, and HDR settings.",
    ));

    let backend_items = [
        ("auto", "Auto"),
        ("wayland", "Wayland (nested)"),
        ("drm", "DRM/KMS (iLand)"),
    ];
    let (compositor_backend_row, backend_ids) = make_combo_row(
        "Display Backend",
        &backend_items,
        profile
            .runtime_overrides
            .compositor_backend
            .as_deref()
            .unwrap_or("auto"),
    );
    dig_group.add(&compositor_backend_row);

    let vulkan_items = [
        ("system", "System"),
        ("swiftshader", "SwiftShader"),
        ("none", "None"),
    ];
    let (vulkan_driver_row, vulkan_ids) = make_combo_row(
        "Vulkan Driver",
        &vulkan_items,
        profile
            .runtime_overrides
            .vulkan_driver
            .as_deref()
            .unwrap_or("system"),
    );
    dig_group.add(&vulkan_driver_row);

    let opengl_items = [("system", "System"), ("angle", "ANGLE"), ("none", "None")];
    let (opengl_driver_row, opengl_ids) = make_combo_row(
        "OpenGL Driver",
        &opengl_items,
        profile
            .runtime_overrides
            .open_gl_driver
            .as_deref()
            .unwrap_or("system"),
    );
    dig_group.add(&opengl_driver_row);

    let color_ops_row = adw::SwitchRow::new();
    color_ops_row.set_title("Color Operations / HDR");
    color_ops_row.set_active(profile.runtime_overrides.color_operations.unwrap_or(false));
    dig_group.add(&color_ops_row);

    let input_profile_row = adw::EntryRow::new();
    input_profile_row.set_title("Input Profile");
    input_profile_row.set_text(
        profile
            .runtime_overrides
            .input_profile
            .as_deref()
            .unwrap_or(""),
    );
    dig_group.add(&input_profile_row);

    // MARK: Virtual Machine
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machine");
    vm_group.set_description(Some(
        "KVM hypervisor and guest system parameters. Fail closed without /dev/kvm.",
    ));

    let vm_variant_items = [
        ("nixos-guest-4k", "NixOS Guest 4K"),
        ("standard", "Standard Linux"),
    ];
    let current_variant = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.guest_variant.as_deref())
        .unwrap_or("nixos-guest-4k");
    let (vm_variant_row, vm_variant_ids) =
        make_combo_row("Guest Variant", &vm_variant_items, current_variant);
    vm_group.add(&vm_variant_row);

    let current_mem = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.memory_mb)
        .unwrap_or(2048);
    let vm_memory_row = make_spin_row("Memory (MB)", current_mem as f64, 512.0, 32768.0, 512.0);
    vm_group.add(&vm_memory_row);

    let current_disk = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.disk_gib)
        .unwrap_or(20);
    let vm_disk_row = make_spin_row("Disk Size (GiB)", current_disk as f64, 4.0, 1024.0, 4.0);
    vm_group.add(&vm_disk_row);

    let current_vsock = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.vsock_port.as_deref())
        .and_then(|p| p.parse::<f64>().ok())
        .unwrap_or(1024.0);
    let vm_vsock_row = make_spin_row("VSock Port", current_vsock, 1024.0, 65535.0, 1.0);
    vm_group.add(&vm_vsock_row);

    let current_notes = profile
        .vm_settings
        .as_ref()
        .and_then(|s| s.notes.as_deref())
        .unwrap_or("");
    let vm_notes_row = adw::EntryRow::new();
    vm_notes_row.set_title("Notes");
    vm_notes_row.set_text(current_notes);
    vm_group.add(&vm_notes_row);

    let vm_note = gtk::Label::new(Some(
        "Linux guests use KVM via cloud-hypervisor or crosvm. Fail closed without /dev/kvm. No QEMU.",
    ));
    vm_note.set_xalign(0.0);
    vm_note.set_wrap(true);
    vm_note.add_css_class("dim-label");
    vm_note.add_css_class("caption");
    vm_group.add(&vm_note);

    // MARK: Container
    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Container");
    container_group.set_description(Some(
        "OCI runtime configuration. Containers unpack OCI images and run on the Relay VM.",
    ));

    let current_ref = profile
        .container_settings
        .as_ref()
        .and_then(|s| s.container_ref.as_deref())
        .unwrap_or("");
    let container_ref_row = adw::EntryRow::new();
    container_ref_row.set_title("Image Reference");
    container_ref_row.set_text(current_ref);
    container_group.add(&container_ref_row);

    let current_container_cmd = profile
        .container_settings
        .as_ref()
        .and_then(|s| s.entry_command.as_deref())
        .unwrap_or(&profile.remote_command);
    let container_cmd_row = adw::EntryRow::new();
    container_cmd_row.set_title("Startup Command");
    container_cmd_row.set_text(current_container_cmd);
    container_group.add(&container_cmd_row);

    let current_container_mem = profile
        .container_settings
        .as_ref()
        .and_then(|s| s.memory.as_deref())
        .unwrap_or("");
    let container_memory_row = adw::EntryRow::new();
    container_memory_row.set_title("Memory Limit");
    container_memory_row.set_text(current_container_mem);
    container_group.add(&container_memory_row);

    let current_desktop = profile
        .container_settings
        .as_ref()
        .and_then(|s| s.desktop_session)
        .unwrap_or(false);
    let container_desktop_row = adw::SwitchRow::new();
    container_desktop_row.set_title("Desktop Session");
    container_desktop_row.set_active(current_desktop);
    container_group.add(&container_desktop_row);

    let container_note = gtk::Label::new(Some(
        "Containers unpack OCI, then run on the same KVM VM as virtual_machine. Not host Docker.",
    ));
    container_note.set_xalign(0.0);
    container_note.set_wrap(true);
    container_note.add_css_class("dim-label");
    container_note.add_css_class("caption");
    container_group.add(&container_note);

    // MARK: Environment Variables
    let env_group = adw::PreferencesGroup::new();
    env_group.set_title("Environment Variables");
    env_group.set_description(Some(
        "Per-machine KEY=value overrides applied to launched clients (overrides global env vars). Lines starting with -NAME unset a variable.",
    ));

    let env_text = gtk::TextView::new();
    env_text.set_monospace(true);
    env_text.set_wrap_mode(gtk::WrapMode::WordChar);
    env_text.set_vexpand(true);
    env_text.set_hexpand(true);
    {
        let mut buf = String::new();
        if let Some(env_map) = &profile.runtime_overrides.environment {
            for (k, v) in env_map {
                if v.action == "unset" {
                    buf.push('-');
                    buf.push_str(k);
                    buf.push('\n');
                } else if let Some(val) = &v.value {
                    buf.push_str(k);
                    buf.push('=');
                    buf.push_str(val);
                    buf.push('\n');
                }
            }
        }
        env_text.buffer().set_text(&buf);
    }
    let env_scroll = gtk::ScrolledWindow::new();
    env_scroll.set_min_content_height(140);
    env_scroll.set_child(Some(&env_text));
    env_group.add(&env_scroll);

    // Command preview text mirrors WWNMachineEditorView.previewCommand.
    let update_preview = {
        let host = host_row.clone();
        let user = user_row.clone();
        let port = port_row.clone();
        let cmd = cmd_row.clone();
        let terminal_cmd = terminal_custom_row.clone();
        let session = session_row.clone();
        let session_ids = session_ids.clone();
        let lbl = preview_lbl.clone();
        let settings = state.borrow().settings.clone();
        Rc::new(move || {
            let kind = get_combo_id(&session, &session_ids);
            let is_waypipe = kind == "waypipe";
            let host = host.text().trim().to_string();
            if host.is_empty() {
                lbl.set_text("Preview unavailable: SSH host is empty");
                return;
            }
            let user = user.text().trim().to_string();
            let port_str = port.text().trim().to_string();
            let port = port_str.parse::<u16>().unwrap_or(22);
            let remote_command = if is_waypipe {
                cmd.text().trim().to_string()
            } else {
                terminal_cmd.text().trim().to_string()
            };
            let remote_command = if remote_command.is_empty() {
                if is_waypipe {
                    "weston-simple-shm".to_string()
                } else {
                    String::new()
                }
            } else {
                remote_command
            };
            let mut parts: Vec<String> = Vec::new();
            if is_waypipe {
                parts.push("waypipe".into());
                let sock = settings.waypipe_socket.trim();
                if !sock.is_empty() {
                    parts.push(format!("--socket={sock}"));
                }
                if settings.waypipe_display > 0 {
                    parts.push(format!("--display=wayland-{}", settings.waypipe_display));
                }
                let comp = settings.waypipe_compression.trim();
                if !comp.is_empty() && comp != "none" {
                    parts.push(format!("--compress={comp}"));
                    if settings.waypipe_compress_level > 0 {
                        parts.push(format!(
                            "--compress-level={}",
                            settings.waypipe_compress_level
                        ));
                    }
                }
                if settings.waypipe_threads > 0 {
                    parts.push(format!("--threads={}", settings.waypipe_threads));
                }
                let video = settings.waypipe_video.trim();
                if !video.is_empty() && video != "none" {
                    parts.push(format!("--video={video}"));
                    let bpf = settings.waypipe_video_bpf.trim();
                    if !bpf.is_empty() {
                        parts.push(format!("--video-bpf={bpf}"));
                    }
                }
                parts.push("ssh".into());
            } else {
                parts.push("ssh".into());
            }
            if port != 22 {
                parts.push(format!("-p {port}"));
            }
            if !user.is_empty() {
                parts.push(format!("{user}@{host}"));
            } else {
                parts.push(host);
            }
            if !remote_command.is_empty() {
                parts.push(remote_command);
            }
            lbl.set_text(&parts.join(" "));
        })
    };

    let update_sections = {
        let preview = update_preview.clone();
        let sg = session_group.clone();
        let wg = wasm_group.clone();
        let rg = remote_group.clone();
        let pg = preview_group.clone();
        let vg = vm_group.clone();
        let ctg = container_group.clone();
        let session = session_row.clone();
        let session_ids = session_ids.clone();
        let use_ssh = use_ssh_row.clone();
        let terminal_custom_row = terminal_custom_row.clone();
        let cmd_row = cmd_row.clone();
        move |type_id: &str| {
            let is_native = type_id == "native";
            let kind = get_combo_id(&session, &session_ids);
            let ssh_on = use_ssh.is_active();
            sg.set_visible(is_native);
            wg.set_visible(is_native && kind == "wasm");
            rg.set_visible(is_native && ssh_on);
            pg.set_visible(is_native && ssh_on);
            vg.set_visible(type_id == "virtual_machine");
            ctg.set_visible(type_id == "container");
            use_ssh.set_sensitive(kind == "terminal" || kind == "waypipe");
            terminal_custom_row.set_visible(is_native && kind == "terminal");
            cmd_row.set_visible(kind == "waypipe" && ssh_on);
            if kind == "waypipe" && ssh_on {
                rg.set_title("SSH + Waypipe");
                rg.set_description(Some(
                    "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe.",
                ));
                cmd_row.set_title("Remote Command");
            } else if kind == "terminal" && ssh_on {
                rg.set_title("SSH Connection");
                rg.set_description(Some(
                    "Connects to a remote host via SSH and opens a terminal session.",
                ));
            }
            preview();
        }
    };

    update_sections(&mt_id(ui_type));

    {
        let u = update_sections.clone();
        let type_row = type_row.clone();
        let type_ids = type_ids.clone();
        type_row.connect_selected_notify(move |c| {
            let id = get_combo_id(c, &type_ids);
            u(&id);
        });
    }
    {
        let u = update_sections.clone();
        let type_row = type_row.clone();
        let type_ids = type_ids.clone();
        session_row.connect_selected_notify(move |_| {
            let id = get_combo_id(&type_row, &type_ids);
            u(&id);
        });
    }
    {
        let u = update_sections.clone();
        let type_row = type_row.clone();
        let type_ids = type_ids.clone();
        use_ssh_row.connect_active_notify(move |_| {
            let id = get_combo_id(&type_row, &type_ids);
            u(&id);
        });
    }

    for entry in [
        &host_row,
        &user_row,
        &port_row,
        &cmd_row,
        &terminal_custom_row,
    ] {
        let preview = update_preview.clone();
        entry.connect_changed(move |_| preview());
    }

    let form = adw::PreferencesPage::new();
    form.set_vexpand(true);
    form.add(&profile_group);
    form.add(&session_group);
    form.add(&wasm_group);
    form.add(&remote_group);
    form.add(&preview_group);
    form.add(&dig_group);
    form.add(&vm_group);
    form.add(&container_group);
    form.add(&env_group);

    let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
    content.append(&header);
    content.append(&form);

    let on_close_c = on_close.clone();
    cancel_btn.connect_clicked(move |_| on_close_c(false));

    let st = state.clone();
    let pid = profile.id.clone();
    let on_close_s = on_close.clone();
    save_btn.connect_clicked(move |_| {
        let tid = get_combo_id(&type_row, &type_ids);
        let kind = get_combo_id(&session_row, &session_ids);
        let use_ssh = use_ssh_row.is_active() && (kind == "terminal" || kind == "waypipe");
        let mt = if tid == "native" {
            storage_type_for_native_shell(&kind, use_ssh)
        } else {
            parse_mt(&tid)
        };
        let remote_command = if mt == MachineType::Container {
            container_cmd_row.text().trim().to_string()
        } else if kind == "terminal" {
            terminal_custom_row.text().trim().to_string()
        } else {
            cmd_row.text().trim().to_string()
        };
        let auth_method = get_combo_id(&auth_method_row, &auth_ids)
            .parse::<i32>()
            .unwrap_or(0);

        let mut updated = MachineProfile {
            id: pid.clone(),
            name: {
                let nm = name_row.text().trim().to_string();
                if nm.is_empty() {
                    "Unnamed Machine".to_string()
                } else {
                    nm
                }
            },
            machine_type: mt,
            ssh_host: if use_ssh {
                host_row.text().trim().to_string()
            } else {
                String::new()
            },
            ssh_user: if use_ssh {
                user_row.text().trim().to_string()
            } else {
                String::new()
            },
            ssh_port: if use_ssh {
                port_row.text().trim().parse::<i32>().unwrap_or(22)
            } else {
                22
            },
            ssh_password: if use_ssh {
                password_row.text().to_string()
            } else {
                String::new()
            },
            ssh_auth_method: auth_method,
            ssh_key_path: if use_ssh {
                key_path_row.text().trim().to_string()
            } else {
                String::new()
            },
            ssh_key_passphrase: if use_ssh {
                key_passphrase_row.text().to_string()
            } else {
                String::new()
            },
            remote_command,
            favorite: favorite_row.is_active(),
            launchers: baseline.launchers.clone(),
            runtime_overrides: baseline.runtime_overrides.clone(),
            container_settings: if mt == MachineType::Container {
                Some(ContainerMachineSettings {
                    runtime: Some("OCI-in-VM".to_string()),
                    container_ref: {
                        let r = container_ref_row.text().trim().to_string();
                        if r.is_empty() { None } else { Some(r) }
                    },
                    entry_command: {
                        let c = container_cmd_row.text().trim().to_string();
                        if c.is_empty() { None } else { Some(c) }
                    },
                    memory: {
                        let m = container_memory_row.text().trim().to_string();
                        if m.is_empty() { None } else { Some(m) }
                    },
                    desktop_session: Some(container_desktop_row.is_active()),
                    ..baseline.container_settings.clone().unwrap_or_default()
                })
            } else {
                baseline.container_settings.clone()
            },
            vm_settings: if mt == MachineType::VirtualMachine {
                Some(VirtualMachineSettings {
                    guest_variant: Some(get_combo_id(&vm_variant_row, &vm_variant_ids)),
                    memory_mb: Some(vm_memory_row.value() as i32),
                    disk_gib: Some(vm_disk_row.value() as i32),
                    vsock_port: Some(format!("{}", vm_vsock_row.value() as u32)),
                    notes: {
                        let n = vm_notes_row.text().trim().to_string();
                        if n.is_empty() { None } else { Some(n) }
                    },
                    ..baseline.vm_settings.clone().unwrap_or_default()
                })
            } else {
                baseline.vm_settings.clone()
            },
            ..baseline.clone()
        };

        if tid == "native" && (kind == "terminal" || kind == "wayland") && !use_ssh {
            updated.runtime_overrides.bundled_app_id = Some("wawona-shell".into());
        } else if tid == "native" && kind == "wasm" {
            updated.runtime_overrides.bundled_app_id = Some("wawona-wasm".into());
            let cmd = wasm_cmd_row.text().trim().to_string();
            updated.runtime_overrides.wasm_command = Some(if cmd.is_empty() {
                "wasm hello-wasi-gui".into()
            } else {
                cmd
            });
            let pkg = wasm_pkg_row.text().trim().to_string();
            let path = wasm_path_row.text().trim().to_string();
            updated.runtime_overrides.wasm_launch_mode = Some(
                if !path.is_empty() {
                    "file"
                } else if !pkg.is_empty() {
                    "repo"
                } else {
                    "command"
                }
                .into(),
            );
            updated.runtime_overrides.wasm_package = if pkg.is_empty() { None } else { Some(pkg) };
            updated.runtime_overrides.wasm_module_path =
                if path.is_empty() { None } else { Some(path) };
        } else if tid == "native" && kind == "waypipe" {
            updated.runtime_overrides.bundled_app_id = None;
        }

        updated.runtime_overrides.waypipe_enabled =
            Some(kind == "waypipe" || (kind == "terminal" && use_ssh));
        updated.runtime_overrides.force_ssd = Some(true);
        updated.runtime_overrides.auto_scale = Some(true);
        updated.runtime_overrides.compositor_backend =
            Some(get_combo_id(&compositor_backend_row, &backend_ids));
        updated.runtime_overrides.vulkan_driver =
            Some(get_combo_id(&vulkan_driver_row, &vulkan_ids));
        updated.runtime_overrides.open_gl_driver =
            Some(get_combo_id(&opengl_driver_row, &opengl_ids));
        updated.runtime_overrides.dmabuf_enabled = Some(true);
        updated.runtime_overrides.color_operations = Some(color_ops_row.is_active());
        {
            let inp = input_profile_row.text().trim().to_string();
            updated.runtime_overrides.input_profile = if inp.is_empty() { None } else { Some(inp) };
        }
        {
            let buffer = env_text.buffer();
            let start = buffer.start_iter();
            let end = buffer.end_iter();
            let text = buffer.text(&start, &end, false);
            let mut env_map: HashMap<String, DomainEnvironmentOverride> = HashMap::new();
            for line in text.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some(name) = trimmed.strip_prefix('-') {
                    let name = name.trim();
                    if !name.is_empty() {
                        env_map.insert(
                            name.to_string(),
                            DomainEnvironmentOverride {
                                action: "unset".into(),
                                value: None,
                            },
                        );
                    }
                } else if let Some((k, v)) = trimmed.split_once('=') {
                    let k = k.trim();
                    let v = v.trim();
                    if !k.is_empty() {
                        env_map.insert(
                            k.to_string(),
                            DomainEnvironmentOverride {
                                action: "set".into(),
                                value: Some(v.to_string()),
                            },
                        );
                    }
                }
            }
            updated.runtime_overrides.environment = if env_map.is_empty() {
                None
            } else {
                Some(env_map)
            };
        }

        let mut app = st.borrow_mut();
        let _ = app.store.upsert(updated);
        let _ = app.store.save();
        drop(app);

        wlog!("UI", "Machine saved id={} type={}", pid, tid);
        on_close_s(true);
    });

    content
}

pub fn show_editor(
    parent: &adw::ApplicationWindow,
    state: &SharedAppState,
    existing: Option<MachineProfile>,
    default_type: MachineType,
    shell: &HomeShell,
    sessions: MachineSessions,
    layout: LayoutMode,
) {
    let dialog_holder: Rc<RefCell<Option<adw::Window>>> = Rc::new(RefCell::new(None));
    let dh = dialog_holder.clone();
    let shell_c = shell.clone();
    let state_c = state.clone();
    let parent_c = parent.clone();
    let sessions_c = sessions.clone();
    let content = build_editor_view(
        state,
        existing,
        default_type,
        sessions,
        Rc::new(move |saved| {
            if saved {
                rebuild_home(RebuildHome {
                    shell: &shell_c,
                    state: &state_c,
                    parent: &parent_c,
                    sessions: sessions_c.clone(),
                    layout,
                    on_edit: None,
                    on_open_terminal: None,
                });
            }
            if let Some(d) = dh.borrow().as_ref() {
                d.close();
            }
        }),
    );
    let title = "Machine Profile";
    let dialog = present_sheet(parent, title, &content, layout);
    *dialog_holder.borrow_mut() = Some(dialog);
}

fn make_combo_row(
    title: &str,
    items: &[(&str, &str)],
    active_id: &str,
) -> (adw::ComboRow, Vec<String>) {
    let row = adw::ComboRow::new();
    row.set_title(title);
    let ids: Vec<String> = items.iter().map(|(id, _)| id.to_string()).collect();
    let labels: Vec<&str> = items.iter().map(|(_, label)| *label).collect();
    let model = gtk::StringList::new(&labels);
    row.set_model(Some(&model));
    if let Some(idx) = items.iter().position(|(id, _)| *id == active_id) {
        row.set_selected(idx as u32);
    }
    (row, ids)
}

fn get_combo_id(row: &adw::ComboRow, ids: &[String]) -> String {
    let idx = row.selected() as usize;
    ids.get(idx)
        .cloned()
        .unwrap_or_else(|| ids.first().cloned().unwrap_or_default())
}

fn make_spin_row(title: &str, val: f64, min: f64, max: f64, step: f64) -> adw::SpinRow {
    let adj = gtk::Adjustment::new(val, min, max, step, step * 2.0, 0.0);
    let row = adw::SpinRow::new(Some(&adj), 1.0, 0);
    row.set_title(title);
    row
}

fn mt_id(mt: MachineType) -> String {
    match mt {
        MachineType::Native => "native".into(),
        MachineType::Wasm => "wasm".into(),
        MachineType::SshWaypipe => "ssh_waypipe".into(),
        MachineType::SshTerminal => "ssh_terminal".into(),
        MachineType::VirtualMachine => "virtual_machine".into(),
        MachineType::Container => "container".into(),
    }
}

fn parse_mt(id: &str) -> MachineType {
    match id {
        "wasm" => MachineType::Wasm,
        "ssh_waypipe" => MachineType::SshWaypipe,
        "ssh_terminal" => MachineType::SshTerminal,
        "virtual_machine" => MachineType::VirtualMachine,
        "container" => MachineType::Container,
        _ => MachineType::Native,
    }
}

fn storage_type_for_native_shell(kind: &str, use_ssh: bool) -> MachineType {
    match kind {
        "wasm" => MachineType::Wasm,
        "terminal" if use_ssh => MachineType::SshTerminal,
        "waypipe" if use_ssh => MachineType::SshWaypipe,
        _ => MachineType::Native,
    }
}

fn native_shell_session_from(profile: &MachineProfile) -> (&'static str, bool) {
    match profile.machine_type {
        MachineType::Wasm => ("wasm", false),
        MachineType::SshTerminal => ("terminal", true),
        MachineType::SshWaypipe => ("waypipe", true),
        MachineType::Native => {
            let bundled = profile
                .runtime_overrides
                .bundled_app_id
                .as_deref()
                .unwrap_or("")
                .trim();
            if profile.runtime_overrides.waypipe_enabled == Some(true)
                && (bundled.is_empty() || bundled == "wawona-shell")
            {
                ("waypipe", false)
            } else if bundled == "wawona-wasm" {
                ("wasm", false)
            } else {
                ("terminal", false)
            }
        }
        MachineType::VirtualMachine | MachineType::Container => ("terminal", false),
    }
}
