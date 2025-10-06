use anyhow::{Context, Result};
use std::env;
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};

/// Ollama release version to download
const OLLAMA_VERSION: &str = "v0.12.3";

fn main() -> Result<()> {
    // Skip download if SKIP_OLLAMA_DOWNLOAD is set (for CI or testing)
    if env::var("SKIP_OLLAMA_DOWNLOAD").is_ok() {
        println!("cargo:warning=Skipping Ollama download (SKIP_OLLAMA_DOWNLOAD is set)");
        // Create empty placeholder file
        let out_dir = PathBuf::from(env::var("OUT_DIR")?);
        fs::write(out_dir.join("ollama_binary"), b"")?;
        return Ok(());
    }

    let target_os = env::var("CARGO_CFG_TARGET_OS")?;
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH")?;

    // Determine the download URL based on target platform
    // Note: As of v0.12.3, macOS uses universal binaries (ollama-darwin.tgz)
    let (download_url, binary_name) = match (target_os.as_str(), target_arch.as_str()) {
        ("macos", _) => (
            format!(
                "https://github.com/ollama/ollama/releases/download/{}/ollama-darwin.tgz",
                OLLAMA_VERSION
            ),
            "ollama",
        ),
        ("linux", "x86_64") => (
            format!(
                "https://github.com/ollama/ollama/releases/download/{}/ollama-linux-amd64.tgz",
                OLLAMA_VERSION
            ),
            "ollama",
        ),
        ("linux", "aarch64") => (
            format!(
                "https://github.com/ollama/ollama/releases/download/{}/ollama-linux-arm64.tgz",
                OLLAMA_VERSION
            ),
            "ollama",
        ),
        ("windows", "x86_64") => (
            format!(
                "https://github.com/ollama/ollama/releases/download/{}/ollama-windows-amd64.zip",
                OLLAMA_VERSION
            ),
            "ollama.exe",
        ),
        (os, arch) => {
            println!("cargo:warning=Unsupported platform: {} {}", os, arch);
            println!("cargo:warning=Ollama binary will not be embedded");
            let out_dir = PathBuf::from(env::var("OUT_DIR")?);
            fs::write(out_dir.join("ollama_binary"), b"")?;
            return Ok(());
        }
    };

    println!("cargo:warning=Downloading Ollama {} for {}-{}", OLLAMA_VERSION, target_os, target_arch);
    println!("cargo:warning=URL: {}", download_url);

    // Download the archive
    let response = reqwest::blocking::get(&download_url)
        .with_context(|| format!("Failed to download Ollama from {}", download_url))?;

    if !response.status().is_success() {
        anyhow::bail!(
            "Failed to download Ollama: HTTP {}",
            response.status()
        );
    }

    let bytes = response
        .bytes()
        .context("Failed to read response bytes")?;

    println!("cargo:warning=Downloaded {} bytes", bytes.len());

    // Extract the binary
    let binary_data = if download_url.ends_with(".zip") {
        extract_from_zip(&bytes, binary_name)?
    } else {
        extract_from_tgz(&bytes, binary_name)?
    };

    println!("cargo:warning=Extracted Ollama binary: {} bytes", binary_data.len());

    // Write the binary to OUT_DIR so we can include it
    let out_dir = PathBuf::from(env::var("OUT_DIR")?);
    let binary_path = out_dir.join("ollama_binary");
    fs::write(&binary_path, &binary_data)
        .context("Failed to write Ollama binary")?;

    println!("cargo:warning=Embedded Ollama binary at {:?}", binary_path);

    // Tell cargo to rerun if the build script changes
    println!("cargo:rerun-if-changed=build.rs");

    Ok(())
}

fn extract_from_tgz(bytes: &[u8], binary_name: &str) -> Result<Vec<u8>> {
    use flate2::read::GzDecoder;
    use tar::Archive;

    let cursor = Cursor::new(bytes);
    let decoder = GzDecoder::new(cursor);
    let mut archive = Archive::new(decoder);

    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?;

        // Look for the binary (could be in "bin/ollama" or just "ollama")
        if path.file_name()
            .and_then(|n| n.to_str())
            .map(|n| n == binary_name)
            .unwrap_or(false)
        {
            let mut buffer = Vec::new();
            entry.read_to_end(&mut buffer)?;
            return Ok(buffer);
        }
    }

    anyhow::bail!("Could not find '{}' in archive", binary_name)
}

fn extract_from_zip(bytes: &[u8], binary_name: &str) -> Result<Vec<u8>> {
    use std::io::Read;
    use zip::ZipArchive;

    let cursor = Cursor::new(bytes);
    let mut archive = ZipArchive::new(cursor)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let path = file.name();

        if Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n == binary_name)
            .unwrap_or(false)
        {
            let mut buffer = Vec::new();
            file.read_to_end(&mut buffer)?;
            return Ok(buffer);
        }
    }

    anyhow::bail!("Could not find '{}' in archive", binary_name)
}
