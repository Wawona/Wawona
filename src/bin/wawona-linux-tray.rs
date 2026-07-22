#[cfg(feature = "linux-ui")]
mod applet {
    use gtk4 as gtk;
    use gtk::prelude::*;
    use libadwaita as adw;
    use adw::prelude::*;

    use wawona::linux::service;

    pub fn run() {
        adw::init().expect("failed to initialize libadwaita");
        let app = adw::Application::builder()
            .application_id("com.aspauldingcode.wawona.linux.tray")
            .build();
        app.connect_activate(build_ui);
        let _ = app.run();
    }

    fn build_ui(app: &adw::Application) {
        let root = gtk::Box::new(gtk::Orientation::Vertical, 8);
        root.set_margin_top(12);
        root.set_margin_bottom(12);
        root.set_margin_start(12);
        root.set_margin_end(12);

        let status = gtk::Label::new(Some("Wawona Linux applet"));
        status.set_xalign(0.0);
        status.add_css_class("heading");
        root.append(&status);

        let start = gtk::Button::with_label("Start Compositor");
        let stop = gtk::Button::with_label("Stop Compositor");
        let restart = gtk::Button::with_label("Restart Compositor");
        let open = gtk::Button::with_label("Open Wawona Linux");
        let install = gtk::Button::with_label("Install Services");
        let quit = gtk::Button::with_label("Quit Wawona");

        for btn in [&start, &stop, &restart, &open, &install, &quit] {
            root.append(btn);
        }

        let status_clone = status.clone();
        glib::timeout_add_seconds_local(2, move || {
            let running = service::service_is_active("wawona-compositor.service");
            status_clone.set_label(if running {
                "Compositor service is active"
            } else {
                "Compositor service is stopped"
            });
            glib::ControlFlow::Continue
        });

        let status_clone = status.clone();
        start.connect_clicked(move |_| {
            let msg = match service::start_compositor_service() {
                Ok(_) => "Started compositor service".to_string(),
                Err(e) => format!("Failed to start: {e}"),
            };
            status_clone.set_label(&msg);
        });

        let status_clone = status.clone();
        stop.connect_clicked(move |_| {
            let msg = match service::stop_compositor_service() {
                Ok(_) => "Stopped compositor service".to_string(),
                Err(e) => format!("Failed to stop: {e}"),
            };
            status_clone.set_label(&msg);
        });

        let status_clone = status.clone();
        restart.connect_clicked(move |_| {
            let msg = match service::restart_compositor_service() {
                Ok(_) => "Restarted compositor service".to_string(),
                Err(e) => format!("Failed to restart: {e}"),
            };
            status_clone.set_label(&msg);
        });

        let status_clone = status.clone();
        install.connect_clicked(move |_| {
            let msg = match service::install_user_units() {
                Ok(_) => "Installed user units + autostart".to_string(),
                Err(e) => format!("Install failed: {e}"),
            };
            status_clone.set_label(&msg);
        });

        open.connect_clicked(move |_| {
            let flake_ref = std::env::var("WAWONA_FLAKE").unwrap_or_else(|_| "/home/alex/Wawona".to_string());
            let _ = std::process::Command::new("sh")
                .args(["-lc", &format!("nix run {flake_ref}#wawona-linux")])
                .spawn();
        });

        let app_weak = app.downgrade();
        let status_clone = status.clone();
        quit.connect_clicked(move |_| {
            // Tear down systemd units + autostart before exit so Restart=/login
            // cannot reopen Wawona (macOS Quit Wawona parity).
            match service::stop_compositor_and_tray_services() {
                Ok(_) => status_clone.set_label("Stopped services; quitting"),
                Err(e) => status_clone.set_label(&format!("Stop failed: {e}")),
            }
            if let Some(app) = app_weak.upgrade() {
                app.quit();
            }
        });

        let window = adw::ApplicationWindow::builder()
            .application(app)
            .title("Wawona Applet")
            .default_width(320)
            .default_height(300)
            .content(&root)
            .build();
        window.present();
    }
}

#[cfg(feature = "linux-ui")]
fn main() {
    applet::run();
}

#[cfg(not(feature = "linux-ui"))]
fn main() {
    eprintln!("wawona-linux-tray requires --features linux-ui");
}
