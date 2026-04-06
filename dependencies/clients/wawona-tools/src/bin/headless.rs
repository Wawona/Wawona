use wawona::platform::{Platform, api::StubPlatform};

fn main() {
    std::env::set_var("RUST_LOG", "info");
    tracing_subscriber::fmt().init();
    
    let mut app = StubPlatform;
    app.initialize().unwrap();
    println!("Headless Wawona compositor listening...");
    app.run().unwrap();
}
