#[cfg(feature = "linux-ui")]
fn main() -> anyhow::Result<()> {
    let socket = std::env::args().nth(1);
    wawona::linux::service::run_compositor_host(socket)
}

#[cfg(not(feature = "linux-ui"))]
fn main() {
    eprintln!("wawona-linux-compositor-host requires --features linux-ui");
}
