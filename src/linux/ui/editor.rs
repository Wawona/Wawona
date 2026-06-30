//! Machine profile editor modal (canonical model, full field set).

use std::cell::RefCell;
use std::rc::Rc;

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

use crate::linux::bundled_clients::BUNDLED_CLIENTS;
use crate::linux::machine_profile::{MachineProfile, MachineType};
use crate::linux::session_exit;
use crate::linux::ui::home::{rebuild_home, try_launch_profile, HomeShell, MachineSessions, RebuildHome};
use crate::linux::ui::modal_sheet::present_sheet;
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;
use crate::wlog;

pub fn show_editor(
    parent: &adw::ApplicationWindow,
    state: &SharedAppState,
    existing: Option<MachineProfile>,
    shell: &HomeShell,
    sessions: MachineSessions,
    layout: LayoutMode,
) {
    let is_new = existing.is_none();
    let profile = existing.unwrap_or_else(|| MachineProfile::new(""));
    let baseline = profile.clone();

    let header = adw::HeaderBar::new();
    let cancel_btn = gtk::Button::with_label("Cancel");
    let save_btn = gtk::Button::with_label("Save");
    save_btn.add_css_class("suggested-action");
    header.pack_start(&cancel_btn);
    header.pack_end(&save_btn);
    let title_lbl = gtk::Label::new(Some(if is_new {
        "New Machine"
    } else {
        &profile.name
    }));
    title_lbl.add_css_class("title");
    header.set_title_widget(Some(&title_lbl));

    // Profile
    let profile_group = adw::PreferencesGroup::new();
    profile_group.set_title("Profile");
    let name_entry = gtk::Entry::builder()
        .placeholder_text("Name")
        .text(&profile.name)
        .build();
    add_row(&profile_group, "Name", &name_entry);

    let favorite_switch = gtk::Switch::new();
    favorite_switch.set_active(profile.favorite);
    add_row(&profile_group, "Favorite", &favorite_switch);

    let type_combo = gtk::ComboBoxText::new();
    for mt in MachineType::all() {
        let id = mt_id(*mt);
        type_combo.append(Some(&id), mt.user_facing_name());
    }
    type_combo.set_active_id(Some(&mt_id(profile.machine_type)));
    add_row(&profile_group, "Type", &type_combo);

    // Bundled client picker (19 entries)
    let client_group = adw::PreferencesGroup::new();
    client_group.set_title("Bundled Wayland Client");
    client_group.set_description(Some("Native machines launch this client unless a custom command is set."));
    let selected_client = Rc::new(RefCell::new(
        profile
            .runtime_overrides
            .bundled_app_id
            .clone()
            .unwrap_or_else(|| profile.remote_command.clone()),
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
        client_group.add(&row);
    }

    // SSH
    let remote_group = adw::PreferencesGroup::new();
    remote_group.set_title("Remote Host");
    let host_entry = gtk::Entry::builder()
        .placeholder_text("host.example.com")
        .text(&profile.ssh_host)
        .build();
    let user_entry = gtk::Entry::builder()
        .placeholder_text("username")
        .text(&profile.ssh_user)
        .build();
    let password_entry = gtk::PasswordEntry::builder().show_peek_icon(true).build();
    password_entry.set_text(&profile.ssh_password);
    let port_entry = gtk::Entry::builder()
        .placeholder_text("22")
        .text(&profile.ssh_port.to_string())
        .build();
    add_row(&remote_group, "Host", &host_entry);
    add_row(&remote_group, "Username", &user_entry);
    add_row(&remote_group, "Password", &password_entry);
    add_row(&remote_group, "Port", &port_entry);

    // VM / Container subtype
    let vm_group = adw::PreferencesGroup::new();
    vm_group.set_title("Virtual Machine");
    let vm_subtype = gtk::Entry::builder().text(&profile.vm_subtype).build();
    add_row(&vm_group, "Subtype", &vm_subtype);

    let container_group = adw::PreferencesGroup::new();
    container_group.set_title("Container");
    let container_subtype = gtk::Entry::builder().text(&profile.container_subtype).build();
    add_row(&container_group, "Subtype", &container_subtype);

    // Command
    let command_group = adw::PreferencesGroup::new();
    let cmd_entry = gtk::Entry::builder().text(&profile.remote_command).build();
    add_row(&command_group, "Command", &cmd_entry);

    // Runtime overrides
    let overrides_group = adw::PreferencesGroup::new();
    overrides_group.set_title("Runtime Overrides");
    let renderer = gtk::ComboBoxText::new();
    for r in ["vulkan", "software"] {
        renderer.append(Some(r), r);
    }
    renderer.set_active_id(Some(
        profile
            .runtime_overrides
            .renderer
            .as_deref()
            .unwrap_or("vulkan"),
    ));
    let auto_scale = gtk::Switch::new();
    auto_scale.set_active(profile.runtime_overrides.auto_scale.unwrap_or(true));
    let force_ssd = gtk::Switch::new();
    force_ssd.set_active(profile.runtime_overrides.force_ssd.unwrap_or(true));
    let waypipe_enabled = gtk::Switch::new();
    waypipe_enabled.set_active(profile.runtime_overrides.waypipe_enabled.unwrap_or(true));
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
    add_row(&overrides_group, "Renderer", &renderer);
    add_row(&overrides_group, "Auto Scale", &auto_scale);
    add_row(&overrides_group, "Force SSD", &force_ssd);
    add_row(&overrides_group, "Waypipe Enabled", &waypipe_enabled);
    add_row(&overrides_group, "Shake to Close", &shake_switch);
    add_row(&overrides_group, "Swipe Back to Close", &swipe_switch);

    // Session controls
    let session_group = adw::PreferencesGroup::new();
    session_group.set_title("Session");
    let status_lbl = gtk::Label::new(None);
    status_lbl.set_xalign(1.0);
    add_row(&session_group, "Status", &status_lbl);
    let editor_run = gtk::Button::from_icon_name("media-playback-start-symbolic");
    let editor_stop = gtk::Button::from_icon_name("media-playback-stop-symbolic");
    let session_actions = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    session_actions.append(&editor_run);
    session_actions.append(&editor_stop);
    add_row(&session_group, "Control", &session_actions);

    let update_sections = {
        let cg = client_group.clone();
        let rg = remote_group.clone();
        let vg = vm_group.clone();
        let ctg = container_group.clone();
        let cmdg = command_group.clone();
        move |type_id: &str| {
            cg.set_visible(type_id == "native");
            let is_ssh = type_id == "ssh_waypipe" || type_id == "ssh_terminal";
            rg.set_visible(is_ssh);
            vg.set_visible(type_id == "virtual_machine");
            ctg.set_visible(type_id == "container");
            cmdg.set_visible(true);
            match type_id {
                "native" => {
                    cmdg.set_title("Custom Command");
                    cmdg.set_description(Some(
                        "Optional shell command overriding the bundled client.",
                    ));
                }
                "ssh_waypipe" => {
                    cmdg.set_title("Waypipe Remote Command");
                    cmdg.set_description(None);
                }
                "ssh_terminal" => {
                    cmdg.set_title("SSH Command");
                    cmdg.set_description(None);
                }
                "virtual_machine" => {
                    cmdg.set_title("VM Launch Command");
                    cmdg.set_description(Some(
                        "VM launch is a stub. Future support will come from Wawona's UTM SE fork.",
                    ));
                }
                "container" => {
                    cmdg.set_title("Container Launch Command");
                    cmdg.set_description(Some(
                        "Container runtime is a stub (integration pending).",
                    ));
                }
                _ => {}
            }
        }
    };
    update_sections(&mt_id(profile.machine_type));
    {
        let u = update_sections.clone();
        type_combo.connect_changed(move |c| {
            let id = c.active_id().map(|s| s.to_string()).unwrap_or_else(|| "native".into());
            u(&id);
        });
    }

    let form = adw::PreferencesPage::new();
    form.add(&profile_group);
    form.add(&client_group);
    form.add(&remote_group);
    form.add(&vm_group);
    form.add(&container_group);
    form.add(&command_group);
    form.add(&overrides_group);
    form.add(&session_group);

    let scroll = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .child(&form)
        .build();

    let content = gtk::Box::new(gtk::Orientation::Vertical, 0);
    content.append(&header);
    content.append(&scroll);

    let dialog = present_sheet(
        parent,
        if is_new { "New Machine" } else { "Edit Machine" },
        &content,
        layout,
    );

    let editor_mid = profile.id.clone();
    if is_new {
        session_group.set_sensitive(false);
        status_lbl.set_text("Not saved yet");
        editor_run.set_sensitive(false);
        editor_stop.set_sensitive(false);
    } else {
        refresh_session_row(&editor_mid, &sessions, &status_lbl, &editor_run, &editor_stop);
    }

    let st = state.clone();
    let sessions_er = sessions.clone();
    let status_c = status_lbl.clone();
    let run_refresh = editor_run.clone();
    let stop_refresh = editor_stop.clone();
    let mid = editor_mid.clone();
    editor_run.connect_clicked(move |_| {
        match try_launch_profile(&mid, &st) {
            Ok(child) => {
                sessions_er.borrow_mut().insert(mid.clone(), child);
                refresh_session_row(&mid, &sessions_er, &status_c, &run_refresh, &stop_refresh);
            }
            Err(e) => {
                wlog!("UI", "Editor launch failed: {}", e);
                let dlg = gtk::MessageDialog::new(
                    None::<&gtk::Window>,
                    gtk::DialogFlags::MODAL,
                    gtk::MessageType::Warning,
                    gtk::ButtonsType::Ok,
                    &e,
                );
                dlg.connect_response(|d, _| d.close());
                dlg.present();
            }
        }
    });

    let sessions_es = sessions.clone();
    let status_s = status_lbl.clone();
    let run_s = editor_run.clone();
    let stop_s = editor_stop.clone();
    let mid_s = editor_mid.clone();
    editor_stop.connect_clicked(move |_| {
        if let Some(mut child) = sessions_es.borrow_mut().remove(&mid_s) {
            let _ = child.kill();
            let _ = child.wait();
        }
        refresh_session_row(&mid_s, &sessions_es, &status_s, &run_s, &stop_s);
    });

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
        let mut updated = MachineProfile {
            id: pid.clone(),
            name: {
                let nm = name_entry.text().to_string();
                if nm.trim().is_empty() {
                    "Unnamed".to_string()
                } else {
                    nm
                }
            },
            machine_type: mt,
            ssh_host: host_entry.text().to_string(),
            ssh_user: user_entry.text().to_string(),
            ssh_port: port_entry.text().parse::<i32>().unwrap_or(22),
            ssh_password: password_entry.text().to_string(),
            remote_command: cmd_entry.text().to_string(),
            vm_subtype: vm_subtype.text().to_string(),
            container_subtype: container_subtype.text().to_string(),
            favorite: favorite_switch.is_active(),
            launchers: baseline.launchers.clone(),
            runtime_overrides: baseline.runtime_overrides.clone(),
        };
        if mt == MachineType::Native {
            updated.runtime_overrides.bundled_app_id = Some(selected_client.borrow().clone());
        }
        updated.runtime_overrides.renderer = renderer.active_id().map(|s| s.to_string());
        updated.runtime_overrides.auto_scale = Some(auto_scale.is_active());
        updated.runtime_overrides.force_ssd = Some(force_ssd.is_active());
        updated.runtime_overrides.waypipe_enabled = Some(waypipe_enabled.is_active());
        session_exit::write_session_exit_overrides(
            &mut updated.runtime_overrides,
            shake_switch.is_active(),
            swipe_switch.is_active(),
        );

        let mut app = st.borrow_mut();
        let _ = app.store.upsert(updated);
        let _ = app.store.set_active(Some(pid.clone()));
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

fn refresh_session_row(
    machine_id: &str,
    sessions: &MachineSessions,
    status: &gtk::Label,
    run_btn: &gtk::Button,
    stop_btn: &gtk::Button,
) {
    let mut map = sessions.borrow_mut();
    let running = map.get_mut(machine_id).is_some_and(|child| {
        matches!(child.try_wait(), Ok(None) | Err(_))
    });
    status.set_text(if running {
        "Running"
    } else {
        "Stopped"
    });
    run_btn.set_sensitive(!running);
    stop_btn.set_sensitive(running);
}
