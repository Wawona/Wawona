//! Project delivery board matching macOS/iOS `WawonaProjectStatusView`.
//! Status items come from verified project evidence.

use adw::prelude::*;
use gtk::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

struct ProjectStatusItem {
    id: &'static str,
    title: &'static str,
    state: &'static str,
    is_ready: bool,
    detail: &'static str,
}

const ROWS: &[ProjectStatusItem] = &[
    ProjectStatusItem {
        id: "relay-staticcpu",
        title: "Relay StaticCpu",
        state: "Ready",
        is_ready: true,
        detail: "Multi-User NixOS on E4A1C0DE (4 KiB and 16 KiB). auth51.",
    },
    ProjectStatusItem {
        id: "nixos-readiness",
        title: "NixOS readiness",
        state: "Ready",
        is_ready: true,
        detail: "WAWONA_RELAY_AUTH_OK=1 on vsock plus WAWONA_RELAY_READY=1.",
    },
    ProjectStatusItem {
        id: "nixpkgs-over-nat",
        title: "nixpkgs over NAT",
        state: "Ready",
        is_ready: true,
        detail: "nix run nixpkgs#fastfetch substitutes then wawona-fastfetch: end.",
    },
    ProjectStatusItem {
        id: "wayland-shm-import",
        title: "Wayland SHM import",
        state: "Ready",
        is_ready: true,
        detail: "Relay imported SHM frame 800x600 sha256=5b6add91... (auth18/51).",
    },
    ProjectStatusItem {
        id: "iland-present",
        title: "iland present in UI",
        state: "Active",
        is_ready: false,
        detail: "Wiring Ready (N10). Live non-black session surface still required on tip Start.",
    },
    ProjectStatusItem {
        id: "interaction",
        title: "Interaction",
        state: "Active",
        is_ready: false,
        detail: "Multi-Touch + Stop park wired. Need guest-seen touch evidence on session surface.",
    },
    ProjectStatusItem {
        id: "oci-lifecycle",
        title: "OCI lifecycle",
        state: "Active",
        is_ready: false,
        detail: "Host -> Relay; ContainerCommand includes Kill. Prove one StaticCpu create/start/stop/kill.",
    },
    ProjectStatusItem {
        id: "offline-aot",
        title: "Offline AOT",
        state: "Ready",
        is_ready: true,
        detail: "aot-translate offline only. Not in store staticlib. Hot-kernel measure recorded.",
    },
    ProjectStatusItem {
        id: "stardust-asc",
        title: "STARDUST / ASC",
        state: "Active",
        is_ready: false,
        detail: "ASC VALID/IN_BETA_TESTING. Store IPA audit + TF Distribution still open. Completely complete 0%.",
    },
];

pub fn build_work_status_view(on_toggle_sidebar: Option<std::rc::Rc<dyn Fn()>>) -> gtk::Box {
    let header = adw::HeaderBar::new();
    header.set_show_end_title_buttons(false);
    header.set_show_start_title_buttons(false);
    if let Some(on_toggle) = on_toggle_sidebar {
        let toggle_btn = gtk::Button::from_icon_name("sidebar-show-symbolic");
        toggle_btn.set_tooltip_text(Some("Toggle Sidebar (Ctrl+B)"));
        toggle_btn.connect_clicked(move |_| on_toggle());
        header.pack_start(&toggle_btn);
    }
    let title_lbl = gtk::Label::new(Some("Work Status"));
    title_lbl.add_css_class("title");
    header.set_title_widget(Some(&title_lbl));

    let page = adw::PreferencesPage::new();

    let overview_group = adw::PreferencesGroup::new();
    overview_group.set_title("Wawona Delivery Board");
    overview_group.set_description(Some(
        "Green proved. Orange in progress. Red blocker. Session pixels use Machines Focus surface, not this board.",
    ));
    page.add(&overview_group);

    let current_group = adw::PreferencesGroup::new();
    current_group.set_title("Current Work");

    for item in ROWS {
        let row = adw::ActionRow::new();
        row.set_title(item.title);
        row.set_title_lines(1);
        row.set_subtitle(item.detail);
        row.set_subtitle_lines(0);

        let badge = gtk::Label::new(Some(item.state));
        badge.add_css_class("caption-heading");
        badge.add_css_class(if item.is_ready {
            "wwn-icon-green"
        } else {
            "wwn-icon-orange"
        });
        badge.set_valign(gtk::Align::Center);
        badge.set_margin_end(8);
        row.add_suffix(&badge);

        let a11y_id = format!("wwn.projectStatus.{}", item.id);
        crate::linux::ui::a11y::set_wwn_a11y(&row, &a11y_id, Some(item.title));
        current_group.add(&row);
    }
    page.add(&current_group);

    let gate_group = adw::PreferencesGroup::new();
    gate_group.set_title("Completion Gate");
    gate_group.set_description(Some(
        "Completely complete needs every acceptance gate plus a store-shaped IPA that boots NixOS on device. Work Status is a board only; guest frames present on the session surface.",
    ));
    page.add(&gate_group);

    let scroller = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .hexpand(true)
        .min_content_width(0)
        .min_content_height(0)
        .propagate_natural_width(false)
        .child(&page)
        .build();

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&header);
    root.append(&scroller);
    crate::linux::ui::a11y::set_wwn_a11y(&root, "wwn.projectStatus", Some("Work Status"));
    root
}
