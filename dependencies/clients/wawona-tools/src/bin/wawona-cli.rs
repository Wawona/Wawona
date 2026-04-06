use clap::{Parser, Subcommand};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::net::Shutdown;

#[derive(Parser)]
#[command(name = "wawona-cli")]
#[command(about = "Command line interface for Wawona Compositor", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Ping the compositor
    Ping,
    /// List active windows
    Windows,
    /// Dump the scene graph
    Tree,
    /// Get version
    Version,
}

fn main() {
    let cli = Cli::parse();

    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let socket_path = PathBuf::from(runtime_dir).join("wawona-0.sock");

    let mut stream = match UnixStream::connect(&socket_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to connect to Wawona compositor at {:?}: {}", socket_path, e);
            std::process::exit(1);
        }
    };

    let cmd = match cli.command {
        Commands::Ping => "ping\n",
        Commands::Windows => "windows\n",
        Commands::Tree => "tree\n",
        Commands::Version => "version\n",
    };

    if let Err(e) = stream.write_all(cmd.as_bytes()) {
        eprintln!("Failed to write to socket: {}", e);
        std::process::exit(1);
    }
    
    // Signal that we are done writing, so the server knows we're finishing the session
    // This causes the server's read_line loop to hit EOF after processing our command,
    // which in turn causes the server to close the connection, allowing read_to_string below to finish.
    if let Err(e) = stream.shutdown(Shutdown::Write) {
        eprintln!("Failed to shutdown write: {}", e);
    }

    let mut response = String::new();
    if let Err(e) = stream.read_to_string(&mut response) {
        eprintln!("Failed to read from socket: {}", e);
        std::process::exit(1);
    }
    
    print!("{}", response);
}
