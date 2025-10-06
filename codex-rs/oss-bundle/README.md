# Codex OSS Bundle

A standalone, zero-dependency distribution of Codex that runs completely locally with no API keys or cloud services required.

## What is this?

`codex-oss` is a self-contained binary that bundles:
- The full Codex CLI
- An embedded Ollama server
- GPT-OSS models (downloaded on first run)

Everything runs locally on your machine. No API keys, no usage fees, no data sent to the cloud.

## Architecture

This crate provides a **loosely-coupled wrapper** around Codex:

1. **Build time**: Downloads the Ollama binary for your platform and embeds it
2. **Runtime**:
   - Extracts Ollama to `~/.codex-oss/bin/ollama`
   - Finds an available ephemeral port
   - Starts Ollama server on that port
   - Configures Codex to use the local OSS provider
   - Launches the Codex TUI
   - Cleans up Ollama on exit

## Building

### Universal macOS binary (recommended for distribution):
```bash
./oss-bundle/build-universal.sh
```

This will:
- Build for both x86_64 and ARM64 architectures
- Download Ollama v0.12.3 (universal binary) at build time
- Create a fat binary at `target/universal-apple-darwin/release/codex-oss`
- Size: ~161MB (contains both architectures + embedded Ollama)

### Single architecture build:
```bash
cargo build --release -p codex-oss-bundle
```

This will:
- Download Ollama v0.12.3 for your platform at build time
- Embed the binary into the executable
- Produce `target/release/codex-oss` (~80MB for single arch)

### CI/testing build (skip Ollama download):
```bash
SKIP_OLLAMA_DOWNLOAD=1 cargo build -p codex-oss-bundle
```

## Running

```bash
./codex-oss
```

On first run, it will:
1. Extract Ollama to `~/.codex-oss/`
2. Start the Ollama server
3. Download the GPT-OSS model (~12GB for 20B version)
4. Launch Codex

Subsequent runs will use the cached model.

## Distribution

The built binary is completely standalone:
- Single file: `codex-oss` (or `codex-oss.exe` on Windows)
- Size:
  - macOS universal: ~161MB (both Intel and Apple Silicon)
  - Single arch: ~80MB per platform
- No runtime dependencies
- Works offline after initial model download

Users just need to:
1. Download the binary
2. Run it
3. Wait for model download (first time only - ~12GB for gpt-oss:20b)
4. Start coding

## Environment Variables

The wrapper sets these automatically:
- `CODEX_OSS_PORT=<random>` - Ollama server port (ephemeral)
- `CODEX_OSS_BASE_URL=http://127.0.0.1:<random>/v1` - Ollama API endpoint
- `OLLAMA_MODELS=~/.codex-oss/models` - Where models are stored
- `OLLAMA_HOST=127.0.0.1:<random>` - Ollama bind address

Users can override these if needed.

## Design Principles

1. **Loose coupling**: Zero modifications to core Codex codebase
2. **Build-time bundling**: Ollama embedded at compile time, not runtime
3. **Clean lifecycle**: Ollama started on launch, killed on exit
4. **User-friendly**: Single binary, no setup required

## File Layout

```
~/.codex-oss/
├── bin/
│   └── ollama          # Extracted Ollama binary
└── models/             # Downloaded model files
    └── gpt-oss:20b/
```

## Platform Support

Supports the same platforms as Ollama:
- macOS (Apple Silicon & Intel)
- Linux (x86_64 & ARM64)
- Windows (x86_64)

## Limitations

- First run requires ~12GB download for the 20B model
- Requires ~16GB RAM for 20B model inference
- Multiple instances will each start their own Ollama server on different ports
