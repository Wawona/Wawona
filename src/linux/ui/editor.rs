//! Machine profile editor modal — 1:1 with the macOS `WWNMachineEditorView`
//! (section order, titles, subtitles, labels, and button placement).

use std::cell::RefCell;
use std::rc::Rc;

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

use crate::linux::bundled_clients::BUNDLED_CLIENTS;
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
    for mt in MachineType::all() {
        let id = mt_id(*mt);
        type_combo.append(Some(&id), mt.user_facing_name());
    }
    type_combo.set_active_id(Some(&mt_id(profile.machine_type)));
    add_row(&profile_group, "Type", &type_combo);

    // MARK: Wayland Client (Native)
    let client_group = adw::PreferencesGroup::new();
    client_group.set_title("Wayland Client");
    client_group.set_description(Some(
        "Choose a bundled client to connect directly to the compositor via Wayland socket. No SSH or network required.",
    ));
    let selected_client = Rc::new(RefCell::new(
        profile
            .runtime_overrides
            .bundled_app_id
            .clone()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "weston-terminal".to_string()),
    ));
    let mut first_radio: Option<gtk::CheckButton> = None;
    for client in BUNDLED_CLIENTS {
        let row = adw::ActionRow::new();
        row.set_title(client.name);
        row.set_subtitle(client.description);
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
        client_group.add(&row);
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
    for (id, label) in [("none", "None"), ("moltenvk", "MoltenVK"), ("kosmickrisp", "KosmicKrisp")] {
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
    add_row(&dig_group, "HDR / Color Operations", &color_ops);

    // MARK: Session Exit
    let session_exit_group = adw::PreferencesGroup::new();
    session_exit_group.set_title("Session Exit");
    session_exit_group.set_description(Some(
        "Per-machine overrides for closing an active session.",
    ));
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
    add_row(&session_exit_group, "Swipe Back to Exit Machine", &swipe_switch);

    // MARK: Virtual Machine
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machine");
    vm_group.set_description(Some("Hypervisor is selected automatically for this platform."));
    let vm_backend = gtk::Label::new(Some("QEMU/KVM"));
    vm_backend.add_css_class("dim-label");
    add_row(&vm_group, "Backend", &vm_backend);
    let vm_note = gtk::Label::new(Some(
        "The VM engine is fixed per build target (QEMU/KVM on Linux) and is not user-configurable.",
    ));
    vm_note.set_xalign(0.0);
    vm_note.set_wrap(true);
    vm_note.add_css_class("dim-label");
    vm_note.add_css_class("caption");
    vm_group.add(&vm_note);

    // MARK: Container
    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Container");
    container_group.set_description(Some("Container runtime is selected automatically for this platform."));
    let container_backend = gtk::Label::new(Some("crun"));
    container_backend.add_css_class("dim-label");
    add_row(&container_group, "Backend", &container_backend);
    let container_cmd = gtk::Entry::builder()
        .placeholder_text("weston-simple-shm")
        .text(&profile.remote_command)
        .build();
    add_row(&container_group, "Startup Command", &container_cmd);
    let container_note = gtk::Label::new(Some(
        "Container launch support is currently placeholder behavior until runtime integration is complete.",
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
        let combo = type_combo.clone();
        let lbl = preview_lbl.clone();
        let settings = state.borrow().settings.clone();
        Rc::new(move || {
            let type_id = combo
                .active_id()
                .map(|s| s.to_string())
                .unwrap_or_else(|| "native".into());
            let is_waypipe = type_id == "ssh_waypipe";
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
            let command = cmd.text().trim().to_string();
            let effective = if command.is_empty() {
                if is_waypipe { "weston-simple-shm" } else { "bash -l" }.to_string()
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
        let cg = client_group.clone();
        let rg = remote_group.clone();
        let pg = preview_group.clone();
        let vg = vm_group.clone();
        let ctg = container_group.clone();
        let cmd_row = cmd_row.clone();
        let cmd = cmd_entry.clone();
        let preview = update_preview.clone();
        move |type_id: &str| {
            cg.set_visible(type_id == "native");
            let is_ssh = type_id == "ssh_waypipe" || type_id == "ssh_terminal";
            rg.set_visible(is_ssh);
            pg.set_visible(is_ssh);
            vg.set_visible(type_id == "virtual_machine");
            ctg.set_visible(type_id == "container");
            match type_id {
                "ssh_waypipe" => {
                    rg.set_title("SSH + Waypipe");
                    rg.set_description(Some(
                        "Connects to a remote host via SSH and proxies the Wayland protocol using waypipe.",
                    ));
                    cmd_row.set_title("Remote Command");
                    cmd.set_placeholder_text(Some("weston-simple-shm"));
                }
                "ssh_terminal" => {
                    rg.set_title("SSH Connection");
                    rg.set_description(Some(
                        "Connects to a remote host via SSH and opens a terminal session.",
                    ));
                    cmd_row.set_title("SSH Command");
                    cmd.set_placeholder_text(Some("bash -l"));
                }
                _ => {}
            }
            preview();
        }
    };
    update_sections(&mt_id(profile.machine_type));
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
    for entry in [&host_entry, &user_entry, &port_entry, &cmd_entry] {
        let preview = update_preview.clone();
        entry.connect_changed(move |_| preview());
    }

    // Section order matches WWNMachineEditorView.body.
    let form = adw::PreferencesPage::new();
    form.add(&profile_group);
    form.add(&client_group);
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
        let mt = parse_mt(&tid);
        let remote_command = if mt == MachineType::Container {
            container_cmd.text().trim().to_string()
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
            ssh_host: host_entry.text().trim().to_string(),
            ssh_user: user_entry.text().trim().to_string(),
            ssh_port: port_entry.text().trim().parse::<i32>().unwrap_or(22),
            ssh_password: password_entry.text().to_string(),
            remote_command,
            favorite: baseline.favorite,
            launchers: baseline.launchers.clone(),
            runtime_overrides: baseline.runtime_overrides.clone(),
        };
        if mt == MachineType::Native {
            updated.runtime_overrides.bundled_app_id = Some(selected_client.borrow().clone());
        }
        updated.runtime_overrides.waypipe_enabled =
            Some(mt == MachineType::SshWaypipe || mt == MachineType::SshTerminal);
        updated.runtime_overrides.force_ssd = Some(force_ssd.is_active());
        updated.runtime_overrides.auto_scale = Some(auto_scale.is_active());
        updated.runtime_overrides.vulkan_driver =
            vulkan_driver.active_id().map(|s| s.to_string());
        updated.runtime_overrides.open_gl_driver =
            opengl_driver.active_id().map(|s| s.to_string());
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
    row.add_suffix(widget);
    row.set_activatable(false);
    group.add(&row);
}

fn mt_id(mt: MachineType) -> String {
    match mt {
        MachineType::Native => "native".into(),
        MachineType::SshWaypipe => "ssh_waypipe".into(),
        MachineType::SshTerminal => "ssh_terminal".into(),
        MachineType::VirtualMachine => "virtual_machine".into(),
        MachineType::Container => "container".into(),
    }
}

fn parse_mt(id: &str) -> MachineType {
    match id {
        "ssh_waypipe" => MachineType::SshWaypipe,
        "ssh_terminal" => MachineType::SshTerminal,
        "virtual_machine" => MachineType::VirtualMachine,
        "container" => MachineType::Container,
        _ => MachineType::Native,
    }
}
