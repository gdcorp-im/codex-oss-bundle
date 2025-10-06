use anyhow::{Context, Result};
use std::fs;
use std::io::Write;
use std::path::PathBuf;

/// Embedded Ollama binary (included at compile time)
const OLLAMA_BINARY: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/ollama_binary"));

/// Get the path where the Ollama binary should be extracted
pub fn get_ollama_bundle_dir() -> Result<PathBuf> {
    let home = dirs::home_dir().context("Could not determine home directory")?;
    Ok(home.join(".codex-oss"))
}

/// Get the path to the extracted Ollama binary
pub fn get_ollama_binary_path() -> Result<PathBuf> {
    let bundle_dir = get_ollama_bundle_dir()?;
    let binary_name = if cfg!(windows) { "ollama.exe" } else { "ollama" };
    Ok(bundle_dir.join("bin").join(binary_name))
}

/// Extract the embedded Ollama binary to disk if not already present
pub fn ensure_ollama_extracted() -> Result<PathBuf> {
    let binary_path = get_ollama_binary_path()?;

    // If the binary is empty (build was skipped), return error
    if OLLAMA_BINARY.is_empty() {
        anyhow::bail!(
            "Ollama binary was not embedded at build time. \
             Please rebuild with SKIP_OLLAMA_DOWNLOAD unset, or provide your own Ollama installation."
        );
    }

    // If binary already exists and has correct size, skip extraction
    if binary_path.exists() {
        if let Ok(metadata) = fs::metadata(&binary_path) {
            if metadata.len() == OLLAMA_BINARY.len() as u64 {
                tracing::debug!("Ollama binary already extracted at {:?}", binary_path);
                return Ok(binary_path);
            }
        }
        tracing::info!("Ollama binary exists but size mismatch, re-extracting");
    }

    // Create parent directory
    if let Some(parent) = binary_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create directory {:?}", parent))?;
    }

    // Write the binary
    tracing::info!("Extracting Ollama binary to {:?}", binary_path);
    let mut file = fs::File::create(&binary_path)
        .with_context(|| format!("Failed to create file {:?}", binary_path))?;
    file.write_all(OLLAMA_BINARY)
        .context("Failed to write Ollama binary")?;

    // Make it executable on Unix
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&binary_path)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&binary_path, perms)?;
        tracing::debug!("Set executable permissions on Ollama binary");
    }

    Ok(binary_path)
}

/// Get the data directory for Ollama models
pub fn get_ollama_models_dir() -> Result<PathBuf> {
    let bundle_dir = get_ollama_bundle_dir()?;
    Ok(bundle_dir.join("models"))
}
