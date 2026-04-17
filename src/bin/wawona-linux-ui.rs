#[cfg(feature = "linux-ui")]
mod app {
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::sync::Arc;

    use gtk4 as gtk;
    use gtk::prelude::*;
    use libadwaita as adw;
    use adw::prelude::*;
    use wawona::ffi::api::{build_info, version, WawonaCore};

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum LinuxMachineType {
        Native,
        SSHWaypipe,
        SSHTerminal,
    }

    impl LinuxMachineType {
        fn as_str(self) -> &'static str {
            match self {
                LinuxMachineType::Native => "native",
                LinuxMachineType::SSHWaypipe => "ssh_waypipe",
                LinuxMachineType::SSHTerminal => "ssh_terminal",
            }
        }

        fn from_str(value: &str) -> Self {
            match value {
                "ssh_waypipe" => LinuxMachineType::SSHWaypipe,
                "ssh_terminal" => LinuxMachineType::SSHTerminal,
                _ => LinuxMachineType::Native,
            }
        }
    }

    #[derive(Clone)]
    struct LinuxMachine {
        name: String,
        machine_type: LinuxMachineType,
        ssh_host: String,
        ssh_user: String,
        ssh_port: u16,
        remote_command: String,
    }

    impl LinuxMachine {
        fn summary(&self) -> String {
            match self.machine_type {
                LinuxMachineType::Native => "Native compositor profile".to_string(),
                LinuxMachineType::SSHWaypipe | LinuxMachineType::SSHTerminal => {
                    format!("{}@{}:{}", self.ssh_user, self.ssh_host, self.ssh_port)
                }
            }
        }
    }

    #[derive(Clone)]
    struct LinuxSettingsState {
        wayland_display: String,
        renderer: String,
        auto_scale: bool,
    }

    #[derive(Clone)]
    struct LinuxShellState {
        machines: Vec<LinuxMachine>,
        selected_machine: Option<usize>,
        settings: LinuxSettingsState,
    }

    pub fn run() {
        adw::init().expect("failed to initialize libadwaita");
        let app = adw::Application::builder()
            .application_id("com.aspauldingcode.wawona.linux")
            .build();

        app.connect_activate(build_ui);
        let _ = app.run();
    }

    fn build_ui(app: &adw::Application) {
        let core = WawonaCore::new();
        let initial_state = LinuxShellState {
            machines: vec![
                LinuxMachine {
                    name: "Local Native".to_string(),
                    machine_type: LinuxMachineType::Native,
                    ssh_host: String::new(),
                    ssh_user: String::new(),
                    ssh_port: 22,
                    remote_command: "weston-simple-shm".to_string(),
                },
                LinuxMachine {
                    name: "Remote Waypipe".to_string(),
                    machine_type: LinuxMachineType::SSHWaypipe,
                    ssh_host: "192.168.1.25".to_string(),
                    ssh_user: "wawona".to_string(),
                    ssh_port: 22,
                    remote_command: "weston-simple-shm".to_string(),
                },
            ],
            selected_machine: Some(0),
            settings: LinuxSettingsState {
                wayland_display: "wayland-0".to_string(),
                renderer: "vulkan".to_string(),
                auto_scale: true,
            },
        };
        let shell = LinuxShell::new(core, Rc::new(RefCell::new(initial_state)));
        let window = adw::ApplicationWindow::builder()
            .application(app)
            .title("Wawona Linux")
            .default_width(1180)
            .default_height(760)
            .content(&shell.root)
            .build();
        window.present();
    }

    struct LinuxShell {
        root: adw::NavigationSplitView,
        _core: Arc<WawonaCore>,
        _state: Rc<RefCell<LinuxShellState>>,
    }

    impl LinuxShell {
        fn new(core: Arc<WawonaCore>, state: Rc<RefCell<LinuxShellState>>) -> Self {
            let list = gtk::ListBox::new();
            list.add_css_class("navigation-sidebar");
            for row in ["Machines", "Editor", "Settings"] {
                let label = gtk::Label::new(Some(row));
                label.set_xalign(0.0);
                list.append(&label);
            }

            let content_stack = gtk::Stack::new();
            content_stack.set_hexpand(true);
            content_stack.set_vexpand(true);

            content_stack.add_titled(&machines_page(state.clone(), core.clone()), Some("machines"), "Machines");
            content_stack.add_titled(&editor_page(state.clone()), Some("editor"), "Editor");
            content_stack.add_titled(&settings_page(state.clone(), core.clone()), Some("settings"), "Settings");

            list.connect_row_selected(move |_, row| {
                if let Some(row) = row {
                    let name = match row.index() {
                        0 => "machines",
                        1 => "editor",
                        _ => "settings",
                    };
                    content_stack.set_visible_child_name(name);
                }
            });

            let sidebar = adw::NavigationPage::new(&list, Some("Sections"));
            let content = adw::NavigationPage::new(&content_stack, Some("Wawona"));

            let split = adw::NavigationSplitView::new();
            split.set_sidebar(&sidebar);
            split.set_content(&content);
            split.set_show_content(true);

            Self { root: split, _core: core, _state: state }
        }
    }

    fn machines_page(state: Rc<RefCell<LinuxShellState>>, core: Arc<WawonaCore>) -> gtk::Widget {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 8);
        root.set_margin_top(12);
        root.set_margin_bottom(12);
        root.set_margin_start(12);
        root.set_margin_end(12);

        let status = adw::Banner::new(&format!("Rust core active: {} ({})", version(), build_info()));
        root.append(&status);

        let content = gtk::Paned::new(gtk::Orientation::Horizontal);
        content.set_wide_handle(true);
        content.set_position(380);
        root.append(&content);

        let machine_list = gtk::ListBox::new();
        machine_list.set_selection_mode(gtk::SelectionMode::Single);
        content.set_start_child(Some(&machine_list));

        let detail = adw::PreferencesPage::new();
        let detail_group = adw::PreferencesGroup::new();
        detail_group.set_title("Machine Detail");
        let detail_name = adw::ActionRow::new();
        detail_name.set_title("Name");
        let detail_type = adw::ActionRow::new();
        detail_type.set_title("Type");
        let detail_target = adw::ActionRow::new();
        detail_target.set_title("Target");
        detail_group.add(&detail_name);
        detail_group.add(&detail_type);
        detail_group.add(&detail_target);
        detail.add(&detail_group);
        content.set_end_child(Some(&detail));

        {
            let state_ref = state.borrow();
            for machine in &state_ref.machines {
                let row = adw::ActionRow::new();
                row.set_title(&machine.name);
                row.set_subtitle(&machine.summary());
                machine_list.append(&row);
            }
        }

        let detail_state = state.clone();
        machine_list.connect_row_selected(move |_, row| {
            let mut state_ref = detail_state.borrow_mut();
            state_ref.selected_machine = row.map(|r| r.index() as usize);
            if let Some(index) = state_ref.selected_machine {
                if let Some(machine) = state_ref.machines.get(index) {
                    detail_name.set_subtitle(&machine.name);
                    detail_type.set_subtitle(machine.machine_type.as_str());
                    detail_target.set_subtitle(&machine.summary());
                }
            } else {
                detail_name.set_subtitle("None");
                detail_type.set_subtitle("None");
                detail_target.set_subtitle("None");
            }
        });

        if !state.borrow().machines.is_empty() {
            if let Some(first) = machine_list.row_at_index(0) {
                machine_list.select_row(Some(&first));
            }
        }

        let footer = gtk::Label::new(Some(&format!(
            "Managed by Rust compositor core object (refs: {}).",
            Arc::strong_count(&core)
        )));
        footer.set_xalign(0.0);
        footer.add_css_class("dim-label");
        root.append(&footer);

        root.upcast()
    }

    fn editor_page(state: Rc<RefCell<LinuxShellState>>) -> gtk::Widget {
        let page = adw::PreferencesPage::new();
        let group = adw::PreferencesGroup::new();
        group.set_title("Machine Editor");
        group.set_description(Some("Declarative machine profile form rendered with GTK/libadwaita."));

        let name_entry = gtk::Entry::builder().placeholder_text("Name").build();
        let host_entry = gtk::Entry::builder().placeholder_text("SSH Host").build();
        let user_entry = gtk::Entry::builder().placeholder_text("SSH User").build();
        let port_entry = gtk::Entry::builder().placeholder_text("SSH Port").build();
        let command_entry = gtk::Entry::builder().placeholder_text("Remote Command").build();

        let type_combo = gtk::ComboBoxText::new();
        for value in ["native", "ssh_waypipe", "ssh_terminal"] {
            type_combo.append(Some(value), value);
        }
        type_combo.set_active_id(Some("native"));

        let save = gtk::Button::with_label("Save Profile");
        save.add_css_class("suggested-action");
        let create = gtk::Button::with_label("Add New");
        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        actions.append(&create);
        actions.append(&save);

        let row_name = adw::ActionRow::new();
        row_name.set_title("Name");
        row_name.add_suffix(&name_entry);
        row_name.set_activatable(false);
        group.add(&row_name);

        let row_type = adw::ActionRow::new();
        row_type.set_title("Type");
        row_type.add_suffix(&type_combo);
        row_type.set_activatable(false);
        group.add(&row_type);

        let row_host = adw::ActionRow::new();
        row_host.set_title("SSH Host");
        row_host.add_suffix(&host_entry);
        row_host.set_activatable(false);
        group.add(&row_host);

        let row_user = adw::ActionRow::new();
        row_user.set_title("SSH User");
        row_user.add_suffix(&user_entry);
        row_user.set_activatable(false);
        group.add(&row_user);

        let row_port = adw::ActionRow::new();
        row_port.set_title("SSH Port");
        row_port.add_suffix(&port_entry);
        row_port.set_activatable(false);
        group.add(&row_port);

        let row_cmd = adw::ActionRow::new();
        row_cmd.set_title("Remote Command");
        row_cmd.add_suffix(&command_entry);
        row_cmd.set_activatable(false);
        group.add(&row_cmd);

        let row_actions = adw::ActionRow::new();
        row_actions.set_title("Actions");
        row_actions.add_suffix(&actions);
        row_actions.set_activatable(false);
        group.add(&row_actions);

        let load_state = state.clone();
        {
            let state_ref = load_state.borrow();
            if let Some(index) = state_ref.selected_machine {
                if let Some(machine) = state_ref.machines.get(index) {
                    name_entry.set_text(&machine.name);
                    type_combo.set_active_id(Some(machine.machine_type.as_str()));
                    host_entry.set_text(&machine.ssh_host);
                    user_entry.set_text(&machine.ssh_user);
                    port_entry.set_text(&machine.ssh_port.to_string());
                    command_entry.set_text(&machine.remote_command);
                }
            }
        }

        let create_state = state.clone();
        create.connect_clicked(move |_| {
            let mut state_ref = create_state.borrow_mut();
            state_ref.machines.push(LinuxMachine {
                name: "New Machine".to_string(),
                machine_type: LinuxMachineType::Native,
                ssh_host: String::new(),
                ssh_user: String::new(),
                ssh_port: 22,
                remote_command: "weston-simple-shm".to_string(),
            });
            state_ref.selected_machine = Some(state_ref.machines.len() - 1);
        });

        let save_state = state.clone();
        save.connect_clicked(move |_| {
            let mut state_ref = save_state.borrow_mut();
            let selected = state_ref.selected_machine.unwrap_or(0);
            if selected >= state_ref.machines.len() {
                return;
            }
            let machine_type = type_combo
                .active_id()
                .map(|v| LinuxMachineType::from_str(v.as_str()))
                .unwrap_or(LinuxMachineType::Native);
            let ssh_port = port_entry.text().parse::<u16>().unwrap_or(22);
            state_ref.machines[selected] = LinuxMachine {
                name: name_entry.text().to_string(),
                machine_type,
                ssh_host: host_entry.text().to_string(),
                ssh_user: user_entry.text().to_string(),
                ssh_port,
                remote_command: command_entry.text().to_string(),
            };
        });

        page.add(&group);
        page.upcast()
    }

    fn settings_page(state: Rc<RefCell<LinuxShellState>>, core: Arc<WawonaCore>) -> gtk::Widget {
        let page = adw::PreferencesPage::new();
        let group = adw::PreferencesGroup::new();
        group.set_title("Connection & Rendering");

        let display_entry = gtk::Entry::builder().placeholder_text("wayland-0").build();
        let renderer_entry = gtk::Entry::builder().placeholder_text("vulkan").build();
        let autoscale_switch = gtk::Switch::new();
        let apply = gtk::Button::with_label("Apply Settings");
        apply.add_css_class("suggested-action");

        let row_display = adw::ActionRow::new();
        row_display.set_title("Wayland Display");
        row_display.add_suffix(&display_entry);
        row_display.set_activatable(false);
        group.add(&row_display);

        let row_renderer = adw::ActionRow::new();
        row_renderer.set_title("Renderer");
        row_renderer.add_suffix(&renderer_entry);
        row_renderer.set_activatable(false);
        group.add(&row_renderer);

        let row_scale = adw::ActionRow::new();
        row_scale.set_title("Auto Scale");
        row_scale.add_suffix(&autoscale_switch);
        row_scale.set_activatable(false);
        group.add(&row_scale);

        let row_apply = adw::ActionRow::new();
        row_apply.set_title("Actions");
        row_apply.add_suffix(&apply);
        row_apply.set_activatable(false);
        group.add(&row_apply);

        let diagnostics = adw::PreferencesGroup::new();
        diagnostics.set_title("Runtime Diagnostics");
        let diag = adw::ActionRow::new();
        diag.set_title("Core Build");
        diag.set_subtitle(&format!("{} ({})", version(), build_info()));
        diagnostics.add(&diag);
        let ref_row = adw::ActionRow::new();
        ref_row.set_title("Core Handle Refs");
        ref_row.set_subtitle(&Arc::strong_count(&core).to_string());
        diagnostics.add(&ref_row);

        {
            let state_ref = state.borrow();
            display_entry.set_text(&state_ref.settings.wayland_display);
            renderer_entry.set_text(&state_ref.settings.renderer);
            autoscale_switch.set_active(state_ref.settings.auto_scale);
        }

        let apply_state = state.clone();
        apply.connect_clicked(move |_| {
            let mut state_ref = apply_state.borrow_mut();
            state_ref.settings.wayland_display = display_entry.text().to_string();
            state_ref.settings.renderer = renderer_entry.text().to_string();
            state_ref.settings.auto_scale = autoscale_switch.is_active();
        });

        page.add(&group);
        page.add(&diagnostics);
        page.upcast()
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
