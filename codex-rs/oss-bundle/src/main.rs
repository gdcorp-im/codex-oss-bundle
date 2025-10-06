mod embedded;

use anyhow::{Context, Result};
use std::env;
use std::net::TcpListener;
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use tokio::time::sleep;

// Use mimalloc as the global allocator on musl targets for better performance
#[cfg(target_env = "musl")]
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

/// Main entry point for codex-oss standalone binary
#[tokio::main]
async fn main() -> Result<()> {
    // Don't initialize tracing here - the TUI will handle it
    // Any logs before TUI starts will be suppressed to avoid polluting the terminal

    // Extract embedded Ollama binary
    let ollama_binary = embedded::ensure_ollama_extracted()
        .context("Failed to extract embedded Ollama binary")?;

    println!("🚀 Starting Codex OSS (standalone edition)");
    println!("   Ollama binary: {:?}", ollama_binary);

    // Find an available ephemeral port
    let ollama_port = find_available_port()?;
    println!("   Using port {} for Ollama server", ollama_port);

    // Set up environment for Ollama
    let models_dir = embedded::get_ollama_models_dir()?;
    std::fs::create_dir_all(&models_dir)?;

    unsafe {
        env::set_var("OLLAMA_MODELS", models_dir.to_string_lossy().to_string());
        env::set_var("OLLAMA_HOST", format!("127.0.0.1:{}", ollama_port));
    }

    // Start Ollama server in the background
    println!("   Starting Ollama server...");
    let mut ollama_process = start_ollama_server(&ollama_binary, ollama_port)?;

    // Set up signal handler for clean shutdown
    let shutdown = Arc::new(AtomicBool::new(false));
    let shutdown_clone = shutdown.clone();

    ctrlc::set_handler(move || {
        shutdown_clone.store(true, Ordering::SeqCst);
    })?;

    // Wait for Ollama to be ready
    wait_for_ollama_ready(ollama_port).await?;
    println!("   ✓ Ollama server ready");

    // Configure environment for codex to use the local OSS provider
    unsafe {
        env::set_var("CODEX_OSS_PORT", ollama_port.to_string());
        env::set_var("CODEX_OSS_BASE_URL", format!("http://127.0.0.1:{}/v1", ollama_port));
        // Suppress verbose logging unless explicitly requested
        if env::var("RUST_LOG").is_err() {
            env::set_var("RUST_LOG", "error");
        }
    }

    // Launch codex CLI with --oss flag and pass through all arguments
    let result = run_codex_with_oss().await;

    // Clean up: kill Ollama server
    println!("\n🛑 Shutting down Ollama server...");
    let _ = ollama_process.kill();
    let _ = ollama_process.wait();

    result
}

/// Find an available port by binding to port 0 and letting the OS choose
fn find_available_port() -> Result<u16> {
    let listener = TcpListener::bind("127.0.0.1:0")
        .context("Failed to bind to ephemeral port")?;
    let port = listener.local_addr()?.port();
    Ok(port)
}

/// Start the Ollama server as a background process
fn start_ollama_server(binary_path: &std::path::Path, port: u16) -> Result<Child> {
    let child = Command::new(binary_path)
        .arg("serve")
        .env("OLLAMA_HOST", format!("127.0.0.1:{}", port))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Failed to start Ollama server")?;

    Ok(child)
}

/// Wait for Ollama server to be ready by polling the health endpoint
async fn wait_for_ollama_ready(port: u16) -> Result<()> {
    let client = reqwest::Client::new();
    let health_url = format!("http://127.0.0.1:{}", port);

    for attempt in 1..=30 {
        match client.get(&health_url).send().await {
            Ok(response) if response.status().is_success() => {
                return Ok(());
            }
            _ => {
                if attempt == 30 {
                    anyhow::bail!("Ollama server failed to start after 30 seconds");
                }
                sleep(Duration::from_secs(1)).await;
            }
        }
    }

    Ok(())
}

/// Run the codex CLI with OSS configuration
async fn run_codex_with_oss() -> Result<()> {
    // Collect command-line arguments (skip the first one which is our binary name)
    let args: Vec<String> = env::args().skip(1).collect();

    // Check if user specified a model with -m or --model
    let user_specified_model = args.iter().any(|arg| {
        arg == "-m" || arg == "--model" || arg.starts_with("--model=")
    });

    // Build the config overrides for OSS mode
    // The --oss flag tells Codex to use the OSS provider
    let mut codex_args = vec!["--oss".to_string()];

    // Only set default model if user didn't specify one
    if !user_specified_model {
        codex_args.push("--model".to_string());
        codex_args.push(codex_ollama::DEFAULT_OSS_MODEL.to_string());
    }

    // Append user-provided arguments (which may include their own --model)
    codex_args.extend(args);

    println!("   Starting Codex CLI...\n");

    // Run codex TUI directly using the public API
    run_codex_tui_with_args(codex_args).await
}

/// Run the codex TUI with the given arguments
async fn run_codex_tui_with_args(args: Vec<String>) -> Result<()> {
    use codex_tui::Cli as TuiCli;
    use clap::Parser;

    // Build a command line with our overrides
    let mut full_args = vec!["codex-oss".to_string()];
    full_args.extend(args);

    // Parse as TuiCli
    let cli = match TuiCli::try_parse_from(&full_args) {
        Ok(cli) => cli,
        Err(e) => {
            // If parsing fails, show the error and exit
            eprintln!("{}", e);
            std::process::exit(1);
        }
    };

    // Run the TUI
    let _exit_info = codex_tui::run_main(cli, None).await?;

    Ok(())
}
