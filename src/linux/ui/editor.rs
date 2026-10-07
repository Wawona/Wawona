//! Machine profile editor modal. 1:1 with the macOS `WWNMachineEditorView`
//! (section order, titles, subtitles, labels, and button placement).

use std::cell::RefCell;
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use gtk4::gio;
use gtk4::glib;
use libadwaita as adw;

use crate::linux::machine_profile::{MachineProfile, MachineType};
use crate::linux::session_exit;
use crate::linux::ui::home::{rebuild_home, HomeShell, MachineSessions, RebuildHome};
use crate::linux::ui::modal_sheet::present_sheet;
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;
use crate::wlog;

pub fn show_editor(
    parent: &adw::ApplicationWindow,
    state: &SharedAppState,
    existing: Option<MachineProfile>,
    default_type: MachineType,
    shell: &HomeShell,
    sessions: MachineSessions,
    layout: LayoutMode,
) {
    let is_new = existing.is_none();
    let title = if is_new {
        "Add Machine Profile"
    } else {
        "Edit Machine Profile"
    };
    let mut profile = existing.unwrap_or_else(|| MachineProfile::new(""));
    if is_new {
        profile.machine_type = default_type;
    }
    let baseline = profile.clone();

    // Toolbar: Cancel (cancellation) leading, Save (confirmation) trailing.
    let header = adw::HeaderBar::new();
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
    profile_group.set_description(Some("Name and type for this machine profile."));
    let name_entry = gtk::Entry::builder()
        .placeholder_text("e.g. Studio Linux VM")
        .text(&profile.name)
        .build();
    add_row(&profile_group, "Display Name", &name_entry);

    let type_combo = gtk::ComboBoxText::new();
    for mt in MachineType::selectable_for_ui() {
        let id = mt_id(*mt);
        type_combo.append(Some(&id), mt.user_facing_name());
    }
    let ui_type = match profile.machine_type {
        MachineType::Wasm | MachineType::SshWaypipe | MachineType::SshTerminal => {
            MachineType::Native
        }
        other => other,
    };
    type_combo.set_active_id(Some(&mt_id(ui_type)));
    add_row(&profile_group, "Type", &type_combo);

    let (initial_session, initial_use_ssh) = native_shell_session_from(&profile);
    let session_group = adw::PreferencesGroup::new();
    session_group.set_title("Native Shell Session");
    session_group.set_description(Some(
        "Terminal is Wawona Terminal (local or SSH). Wayland and Wasm run as clients. Waypipe streams with optional SSH.",
    ));
    let session_combo = gtk::ComboBoxText::new();
    for (id, label) in [
        ("terminal", "Terminal"),
        ("wayland", "Wayland"),
        ("wasm", "Wasm"),
        ("waypipe", "Waypipe"),
    ] {
        session_combo.append(Some(id), label);
    }
    session_combo.set_active_id(Some(initial_session));
    add_row(&session_group, "Session", &session_combo);
    let use_ssh_switch = gtk::Switch::builder()
        .active(initial_use_ssh)
        .valign(gtk::Align::Center)
        .build();
    add_row(&session_group, "Use SSH", &use_ssh_switch);
    let terminal_custom_entry = gtk::Entry::builder()
        .placeholder_text("e.g. bash -l (empty = interactive shell)")
        .text(&profile.remote_command)
        .build();
    let terminal_custom_row = adw::ActionRow::new();
    terminal_custom_row.set_title("Custom Command");
    terminal_custom_row.set_title_lines(1);
    terminal_custom_row.set_activatable(false);
    terminal_custom_row.add_suffix(&terminal_custom_entry);
    session_group.add(&terminal_custom_row);

    // MARK: Wayland Software (Native): Compositors, then client types.
    // Custom commands belong under Terminal, not the Wayland picker.
    use crate::linux::bundled_clients::{wayland_picker_groups, SoftwareKind};
    let mut initial_client = profile
        .runtime_overrides
        .bundled_app_id
        .clone()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "weston-terminal".to_string());
    // Legacy Wayland "custom" → Terminal Custom Command (command stays in remote_command).
    if initial_client == "custom" {
        session_combo.set_active_id(Some("terminal"));
        initial_client = "weston-simple-shm".to_string();
    }
    let selected_client = Rc::new(RefCell::new(initial_client));
    let mut first_radio: Option<gtk::CheckButton> = None;
    let mut client_groups: Vec<adw::PreferencesGroup> = Vec::new();

    for (kind, clients) in wayland_picker_groups() {
        let group = adw::PreferencesGroup::new();
        group.set_title(kind.section_title());
        if kind == SoftwareKind::Compositor {
            group.set_description(Some(
                "Nested compositors. Then Terminals, Graphics, Demos, and Other. Custom commands are under Terminal.",
            ));
        }
        for client in clients {
            let row = adw::ActionRow::new();
            row.set_title(client.name);
            row.set_subtitle(client.description);
            row.set_title_lines(1);
            row.set_activatable(false);
            let radio = gtk::CheckButton::new();
            if let Some(ref first) = first_radio {
                radio.set_group(Some(first));
            } else {
                first_radio = Some(radio.clone());
            }
            if *selected_client.borrow() == client.id {
                radio.set_active(true);
            }
            let sel = selected_client.clone();
            let id = client.id.to_string();
            radio.connect_toggled(move |btn| {
                if btn.is_active() {
                    *sel.borrow_mut() = id.clone();
                }
            });
            row.add_prefix(&radio);
            let icon = gtk::Image::from_icon_name(client.icon_name);
            row.add_prefix(&icon);
            group.add(&row);
        }
        client_groups.push(group);
    }

    let wasm_group = adw::PreferencesGroup::new();
    wasm_group.set_title("Wasm");
    wasm_group.set_description(Some(
        "Same as native shell: wasm hello-wasi-gui. Local file, package name, or typed command. Native still runs wasm from the shell.",
    ));
    let wasm_cmd = gtk::Entry::builder()
        .placeholder_text("wasm hello-wasi-gui")
        .text(
            profile
                .runtime_overrides
                .wasm_command
                .as_deref()
                .unwrap_or("wasm hello-wasi-gui"),
        )
        .build();
    add_row(&wasm_group, "Command", &wasm_cmd);
    let wasm_pkg = gtk::Entry::builder()
        .placeholder_text("hello-wasi-gui")
        .text(
            profile
                .runtime_overrides
                .wasm_package
                .as_deref()
                .unwrap_or(""),
        )
        .build();
    add_row(&wasm_group, "Package", &wasm_pkg);
    let wasm_path = gtk::Entry::builder()
        .placeholder_text("~/…/Wawona/wasm-modules/hello-wasi-gui.wasm")
        .text(
            profile
                .runtime_overrides
                .wasm_module_path
                .as_deref()
                .unwrap_or(""),
        )
        .build();
    add_row(&wasm_group, "Local .wasm", &wasm_path);
    let wasm_pick = gtk::Button::with_label("Choose file…");
    add_row(&wasm_group, "Browse", &wasm_pick);
    let wasm_search = gtk::Button::with_label("Search catalog");
    add_row(&wasm_group, "Repo", &wasm_search);
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
        row.set_activatable(true);
        let wasm_path_c = wasm_path.clone();
        let wasm_cmd_c = wasm_cmd.clone();
        let path_s = local.display().to_string();
        row.connect_activated(move |_| {
            wasm_path_c.set_text(&path_s);
            wasm_cmd_c.set_text(&format!("wasm {path_s}"));
        });
        wasm_group.add(&row);
    }
    {
        let win = parent.clone();
        let wasm_path_c = wasm_path.clone();
        wasm_pick.connect_clicked(move |_| {
            let dialog = gtk::FileDialog::builder()
                .title("Choose a Wasm module")
                .modal(true)
                .build();
            let filter = gtk::FileFilter::new();
            filter.set_name(Some("Wasm modules"));
            filter.add_pattern("*.wasm");
            let filters = gio::ListStore::new::<gtk::FileFilter>();
            filters.append(&filter);
            dialog.set_filters(Some(&filters));
            let wasm_path_c = wasm_path_c.clone();
            dialog.open(
                Some(&win),
                None::<&gio::Cancellable>,
                move |result| {
                    if let Ok(file) = result {
                        if let Some(path) = file.path() {
                            wasm_path_c.set_text(&path.to_string_lossy());
                        }
                    }
                },
            );
        });
    }
    {
        let wasm_pkg_c = wasm_pkg.clone();
        let wasm_cmd_c = wasm_cmd.clone();
        let wasm_path_c = wasm_path.clone();
        let results = wasm_results.clone();
        let note = wasm_note.clone();
        wasm_search.connect_clicked(move |_| {
            let q = wasm_pkg_c.text().to_string();
            note.set_text("Searching /wasm/v1…");
            let note = note.clone();
            let results = results.clone();
            let pkg_e = wasm_pkg_c.clone();
            let cmd_e = wasm_cmd_c.clone();
            let path_e = wasm_path_c.clone();
            std::thread::spawn(move || {
                let found = crate::linux::wasm_launch::search_catalog(&q);
                glib::MainContext::default().invoke(move || {
                    while let Some(child) = results.first_child() {
                        results.remove(&child);
                    }
                    match found {
                        Ok(pkgs) if pkgs.is_empty() => {
                            note.set_text("No packages in /wasm/v1 match.");
                        }
                        Ok(pkgs) => {
                            note.set_text("Tap a package to download from /wasm/v1.");
                            for pkg in pkgs {
                                let row = adw::ActionRow::new();
                                row.set_title(&pkg.name);
                                row.set_subtitle(&format!("{}  {}", pkg.version, pkg.summary));
                                row.set_activatable(true);
                                let name = pkg.name.clone();
                                let pe = pkg_e.clone();
                                let ce = cmd_e.clone();
                                let pte = path_e.clone();
                                let nte = note.clone();
                                row.connect_activated(move |_| {
                                    pe.set_text(&name);
                                    ce.set_text(&format!("wasm {name}"));
                                    nte.set_text("Downloading…");
                                    let name2 = name.clone();
                                    let pte2 = pte.clone();
                                    let nte2 = nte.clone();
                                    std::thread::spawn(move || {
                                        let got =
                                            crate::linux::wasm_launch::ensure_package_file(&name2);
                                        glib::MainContext::default().invoke(move || {
                                            match got {
                                                Some(p) => {
                                                    pte2.set_text(&p.to_string_lossy());
                                                    nte2.set_text("Saved to the Wawona folder.");
                                                }
                                                None => nte2.set_text(
                                                    "Download failed, or this is bundled hello-wasi-gui.",
                                                ),
                                            }
                                        });
                                    });
                                });
                                results.append(&row);
                            }
                        }
                        Err(e) => note.set_text(&e),
                    }
                });
            });
        });
    }

    // MARK: SSH + Waypipe / SSH Connection (Remote)
    let remote_group = adw::PreferencesGroup::new();
    let host_entry = gtk::Entry::builder()
        .placeholder_text("host.example.com")
        .text(&profile.ssh_host)
        .build();
    let user_entry = gtk::Entry::builder()
        .placeholder_text("username")
        .text(&profile.ssh_user)
        .build();
    let port_entry = gtk::Entry::builder()
        .placeholder_text("22")
        .text(&profile.ssh_port.to_string())
        .build();
    let password_entry = gtk::PasswordEntry::builder()
        .show_peek_icon(true)
        .placeholder_text("Optional")
        .build();
    password_entry.set_text(&profile.ssh_password);
    let cmd_entry = gtk::Entry::builder().text(&profile.remote_command).build();
    let cmd_row = adw::ActionRow::new();
    cmd_row.set_activatable(false);
    cmd_row.add_suffix(&cmd_entry);
    add_row(&remote_group, "Host", &host_entry);
    add_row(&remote_group, "User", &user_entry);
    add_row(&remote_group, "Port", &port_entry);
    add_row(&remote_group, "Password", &password_entry);
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
    let force_ssd = gtk::Switch::new();
    force_ssd.set_active(profile.runtime_overrides.force_ssd.unwrap_or(true));
    let auto_scale = gtk::Switch::new();
    auto_scale.set_active(profile.runtime_overrides.auto_scale.unwrap_or(true));
    let vulkan_driver = gtk::ComboBoxText::new();
    for (id, label) in [
        ("none", "None"),
        ("moltenvk", "MoltenVK"),
        ("kosmickrisp", "KosmicKrisp"),
    ] {
        vulkan_driver.append(Some(id), label);
    }
    vulkan_driver.set_active_id(Some(
        profile
            .runtime_overrides
            .vulkan_driver
            .as_deref()
            .unwrap_or("none"),
    ));
    let opengl_driver = gtk::ComboBoxText::new();
    for (id, label) in [("none", "None"), ("angle", "ANGLE")] {
        opengl_driver.append(Some(id), label);
    }
    opengl_driver.set_active_id(Some(
        profile
            .runtime_overrides
            .open_gl_driver
            .as_deref()
            .unwrap_or("none"),
    ));
    let dmabuf = gtk::Switch::new();
    dmabuf.set_active(profile.runtime_overrides.dmabuf_enabled.unwrap_or(false));
    let color_ops = gtk::Switch::new();
    color_ops.set_active(profile.runtime_overrides.color_operations.unwrap_or(false));
    add_row(&dig_group, "Force Server-Side Decorations", &force_ssd);
    add_row(&dig_group, "Auto Scale", &auto_scale);
    add_row(&dig_group, "Vulkan Driver", &vulkan_driver);
    add_row(&dig_group, "OpenGL Driver", &opengl_driver);
    add_row(&dig_group, "Enable DMABUF", &dmabuf);
    add_row(&dig_group, "Enable HDR", &color_ops);

    // MARK: Session Exit
    let session_exit_group = adw::PreferencesGroup::new();
    session_exit_group.set_title("Session Exit");
    session_exit_group
        .set_description(Some("Per-machine overrides for closing an active session."));
    let shake_switch = gtk::Switch::new();
    shake_switch.set_active(session_exit::shake_to_close_enabled(
        &state.borrow().settings,
        Some(&profile),
    ));
    let swipe_switch = gtk::Switch::new();
    swipe_switch.set_active(session_exit::swipe_back_to_close_enabled(
        &state.borrow().settings,
        Some(&profile),
    ));
    add_row(&session_exit_group, "Shake to Exit Machine", &shake_switch);
    add_row(
        &session_exit_group,
        "Swipe Back to Exit Machine",
        &swipe_switch,
    );

    // MARK: Virtual Machine
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machine");
    vm_group.set_description(Some(
        "Hypervisor is selected automatically for this platform.",
    ));
    let vm_backend = gtk::Label::new(Some("Relay KVM"));
    vm_backend.add_css_class("dim-label");
    add_row(&vm_group, "Backend", &vm_backend);
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
        "Container runtime is selected automatically for this platform.",
    ));
    let container_backend = gtk::Label::new(Some("OCI-in-VM"));
    container_backend.add_css_class("dim-label");
    add_row(&container_group, "Backend", &container_backend);
    let container_cmd = gtk::Entry::builder()
        .placeholder_text("weston-simple-shm")
        .text(&profile.remote_command)
        .build();
    add_row(&container_group, "Startup Command", &container_cmd);
    let container_note = gtk::Label::new(Some(
        "Containers unpack OCI, then run on the same KVM VM as virtual_machine. Not host Docker.",
    ));
    container_note.set_xalign(0.0);
    container_note.set_wrap(true);
    container_note.add_css_class("dim-label");
    container_note.add_css_class("caption");
    container_group.add(&container_note);

    // Command preview text mirrors WWNMachineEditorView.previewCommand.
    let update_preview = {
        let host = host_entry.clone();
        let user = user_entry.clone();
        let port = port_entry.clone();
        let cmd = cmd_entry.clone();
        let terminal_cmd = terminal_custom_entry.clone();
        let session = session_combo.clone();
        let lbl = preview_lbl.clone();
        let settings = state.borrow().settings.clone();
        Rc::new(move || {
            let kind = session
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "terminal".into());
            let is_waypipe = kind == "waypipe";
            let host = host.text().trim().to_string();
            if host.is_empty() {
                lbl.set_text("Preview unavailable: SSH host is empty");
                return;
            }
            let user = user.text().trim().to_string();
            let target = if user.is_empty() {
                host
            } else {
                format!("{user}@{host}")
            };
            let port = port.text().trim().parse::<i32>().unwrap_or(22);
            let command = if is_waypipe {
                cmd.text().trim().to_string()
            } else {
                terminal_cmd.text().trim().to_string()
            };
            let effective = if command.is_empty() {
                if is_waypipe {
                    "weston-simple-shm"
                } else {
                    "bash -l"
                }
                .to_string()
            } else {
                command
            };
            let text = if is_waypipe {
                format!(
                    "waypipe --compress '{}' ssh -p {} '{}' '{}'",
                    settings.waypipe_compression, port, target, effective
                )
            } else {
                format!("ssh -p {} '{}' '{}'", port, target, effective)
            };
            lbl.set_text(&text);
        })
    };

    // Show/hide type-specific sections + relabel command field, mirroring the
    // macOS editor's conditional sections.
    let update_sections = {
        let cgs = client_groups.clone();
        let wg = wasm_group.clone();
        let sg = session_group.clone();
        let rg = remote_group.clone();
        let pg = preview_group.clone();
        let vg = vm_group.clone();
        let ctg = container_group.clone();
        let cmd_row = cmd_row.clone();
        let cmd = cmd_entry.clone();
        let terminal_custom_row = terminal_custom_row.clone();
        let terminal_custom_entry = terminal_custom_entry.clone();
        let session = session_combo.clone();
        let use_ssh = use_ssh_switch.clone();
        let preview = update_preview.clone();
        move |type_id: &str| {
            let is_native = type_id == "native";
            sg.set_visible(is_native);
            let kind = session
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "terminal".into());
            let ssh_on = use_ssh.is_active() && (kind == "terminal" || kind == "waypipe");
            let show_wayland = is_native && kind == "wayland";
            for g in &cgs {
                g.set_visible(show_wayland);
            }
            wg.set_visible(is_native && kind == "wasm");
            rg.set_visible(is_native && ssh_on);
            pg.set_visible(is_native && ssh_on);
            vg.set_visible(type_id == "virtual_machine");
            ctg.set_visible(type_id == "container");
            use_ssh.set_sensitive(kind == "terminal" || kind == "waypipe");
            terminal_custom_row.set_visible(is_native && kind == "terminal");
            // Terminal Custom Command lives under Native Shell Session; Waypipe keeps Remote Command here.
            cmd_row.set_visible(kind == "waypipe" && ssh_on);
            if kind == "waypipe" && ssh_on {
                rg.set_title("SSH + Waypipe");
                rg.set_description(Some(
                    "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe.",
                ));
                cmd_row.set_title("Remote Command");
                cmd.set_placeholder_text(Some("weston-simple-shm"));
            } else if kind == "terminal" && ssh_on {
                rg.set_title("SSH Connection");
                rg.set_description(Some(
                    "Connects to a remote host via SSH and opens a terminal session.",
                ));
                terminal_custom_entry.set_placeholder_text(Some("e.g. bash -l"));
            } else if kind == "terminal" {
                terminal_custom_entry
                    .set_placeholder_text(Some("e.g. htop (empty = interactive shell)"));
            }
            preview();
        }
    };
    update_sections(&mt_id(ui_type));
    {
        let u = update_sections.clone();
        type_combo.connect_changed(move |c| {
            let id = c
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "native".into());
            u(&id);
        });
    }
    {
        let u = update_sections.clone();
        let type_combo = type_combo.clone();
        session_combo.connect_changed(move |_| {
            let id = type_combo
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "native".into());
            u(&id);
        });
    }
    {
        let u = update_sections.clone();
        let type_combo = type_combo.clone();
        use_ssh_switch.connect_active_notify(move |_| {
            let id = type_combo
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "native".into());
            u(&id);
        });
    }
    for entry in [
        &host_entry,
        &user_entry,
        &port_entry,
        &cmd_entry,
        &terminal_custom_entry,
    ] {
        let preview = update_preview.clone();
        entry.connect_changed(move |_| preview());
    }

    // Section order matches WWNMachineEditorView.body.
    let form = adw::PreferencesPage::new();
    form.add(&profile_group);
    form.add(&session_group);
    for g in &client_groups {
        form.add(g);
    }
    form.add(&wasm_group);
    form.add(&remote_group);
    form.add(&preview_group);
    form.add(&dig_group);
    form.add(&session_exit_group);
    form.add(&vm_group);
    form.add(&container_group);

    let scroll = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .child(&form)
        .build();

    let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
    content.append(&header);
    content.append(&scroll);

    let dialog = present_sheet(parent, title, &content, layout);

    let d = dialog.clone();
    cancel_btn.connect_clicked(move |_| d.close());

    let d = dialog.clone();
    let st = state.clone();
    let pid = profile.id.clone();
    let shell = shell.clone();
    let sessions_sv = sessions.clone();
    let parent_c = parent.clone();
    save_btn.connect_clicked(move |_| {
        let tid = type_combo
            .active_id()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "native".into());
        let kind = session_combo
            .active_id()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "terminal".into());
        let use_ssh = use_ssh_switch.is_active() && (kind == "terminal" || kind == "waypipe");
        let mt = if tid == "native" {
            storage_type_for_native_shell(&kind, use_ssh)
        } else {
            parse_mt(&tid)
        };
        let remote_command = if mt == MachineType::Container {
            container_cmd.text().trim().to_string()
        } else if kind == "terminal" {
            terminal_custom_entry.text().trim().to_string()
        } else {
            cmd_entry.text().trim().to_string()
        };
        let mut updated = MachineProfile {
            id: pid.clone(),
            name: {
                let nm = name_entry.text().trim().to_string();
                if nm.is_empty() {
                    "Unnamed Machine".to_string()
                } else {
                    nm
                }
            },
            machine_type: mt,
            ssh_host: if use_ssh {
                host_entry.text().trim().to_string()
            } else {
                String::new()
            },
            ssh_user: if use_ssh {
                user_entry.text().trim().to_string()
            } else {
                String::new()
            },
            ssh_port: if use_ssh {
                port_entry.text().trim().parse::<i32>().unwrap_or(22)
            } else {
                22
            },
            ssh_password: if use_ssh {
                password_entry.text().to_string()
            } else {
                String::new()
            },
            remote_command,
            favorite: baseline.favorite,
            launchers: baseline.launchers.clone(),
            runtime_overrides: baseline.runtime_overrides.clone(),
            ..baseline.clone()
        };
        if tid == "native" && kind == "wayland" {
            updated.runtime_overrides.bundled_app_id = Some(selected_client.borrow().clone());
        } else if tid == "native" && kind == "terminal" && !use_ssh {
            updated.runtime_overrides.bundled_app_id = Some("wawona-shell".into());
        } else if tid == "native" && kind == "wasm" {
            updated.runtime_overrides.bundled_app_id = Some("wawona-wasm".into());
            let cmd = wasm_cmd.text().trim().to_string();
            updated.runtime_overrides.wasm_command = Some(if cmd.is_empty() {
                "wasm hello-wasi-gui".into()
            } else {
                cmd
            });
            let pkg = wasm_pkg.text().trim().to_string();
            updated.runtime_overrides.wasm_package = if pkg.is_empty() { None } else { Some(pkg) };
            let path = wasm_path.text().trim().to_string();
            updated.runtime_overrides.wasm_module_path =
                if path.is_empty() { None } else { Some(path.clone()) };
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
        } else if tid == "native" && kind == "waypipe" {
            updated.runtime_overrides.bundled_app_id = None;
        }
        updated.runtime_overrides.waypipe_enabled =
            Some(kind == "waypipe" || (kind == "terminal" && use_ssh));
        updated.runtime_overrides.force_ssd = Some(force_ssd.is_active());
        updated.runtime_overrides.auto_scale = Some(auto_scale.is_active());
        updated.runtime_overrides.vulkan_driver = vulkan_driver.active_id().map(|s| s.to_string());
        updated.runtime_overrides.open_gl_driver = opengl_driver.active_id().map(|s| s.to_string());
        updated.runtime_overrides.dmabuf_enabled = Some(dmabuf.is_active());
        updated.runtime_overrides.color_operations = Some(color_ops.is_active());
        session_exit::write_session_exit_overrides(
            &mut updated.runtime_overrides,
            shake_switch.is_active(),
            swipe_switch.is_active(),
        );

        let mut app = st.borrow_mut();
        let _ = app.store.upsert(updated);
        drop(app);

        rebuild_home(RebuildHome {
            shell: &shell,
            state: &st,
            parent: &parent_c,
            sessions: sessions_sv.clone(),
            layout,
        });
        wlog!("UI", "Machine saved id={} type={}", pid, tid);
        d.close();
    });
}

fn add_row(group: &adw::PreferencesGroup, title: &str, widget: &impl IsA<gtk::Widget>) {
    let row = adw::ActionRow::new();
    row.set_title(title);
    row.set_title_lines(1);
    row.add_suffix(widget);
    row.set_activatable(false);
    group.add(&row);
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
            } else if bundled.is_empty() || bundled == "wawona-shell" {
                ("terminal", false)
            } else {
                ("wayland", false)
            }
        }
        MachineType::VirtualMachine | MachineType::Container => ("terminal", false),
    }
}
