use wawona::platform::{Platform, api::StubPlatform};
use anyhow::Result;

fn main() -> Result<()> {
    // Initialize logging
    // Set default log level to info
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info,wawona=debug");
    }
    // Initialize logging with standardized format
    tracing_subscriber::fmt()
        .with_timer(tracing_subscriber::fmt::time::ChronoLocal::new("%Y-%m-%d %H:%M:%S".to_string()))
        .with_ansi(false)
        .init();

    // Check for version argument
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && (args[1] == "--version" || args[1] == "-v") {
        let version = include_str!("../VERSION").trim();
        println!("Wawona v{}", version);
        
        // Get OS version if on macOS
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            #[cfg(target_os = "macos")]
            let os_ver = std::process::Command::new("sw_vers")
                .arg("-productVersion")
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_else(|_| "unknown".to_string());
            
            #[cfg(target_os = "macos")]
            println!("macOS v{}", os_ver);
            
            #[cfg(target_os = "ios")]
            println!("iOS v{}", std::env::consts::OS);
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            println!("{}", std::env::consts::OS);
        }
        
        println!("{}", std::env::consts::ARCH);
        return Ok(());
    }

    // Create a stub platform app (actual frontends are native/FFI)
    let mut app = StubPlatform;
    
    // Initialize the platform (this sets up the event loop, etc.)
    app.initialize()?;

    // Run the application
    app.run()?;

    Ok(())
}
// Test comment
// Test comment 2
