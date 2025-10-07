# Codex OSS - Standalone AI Code Assistant

A completely free, offline AI coding assistant with no API keys or cloud services required.

## What is Codex OSS?

Codex OSS is a standalone version of Codex that runs entirely on your local machine using open-source AI models. Everything runs locally - your code never leaves your computer.

## Quick Start

### 1. Download

Download the binary for your platform from the [latest release](https://github.com/gdcorp-im/codex-oss-bundle/releases):

**macOS:**
- [codex-oss-universal-apple-darwin.tar.gz](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest) (Intel + Apple Silicon)

**Linux x86_64:**
- [codex-oss-x86_64-unknown-linux-musl.tar.gz](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest) (recommended - static binary)
- [codex-oss-x86_64-unknown-linux-gnu.tar.gz](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest) (glibc)

**Linux ARM64:**
- [codex-oss-aarch64-unknown-linux-musl.tar.gz](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest) (recommended - static binary)
- [codex-oss-aarch64-unknown-linux-gnu.tar.gz](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest) (glibc)

**Windows x86_64:**
- [codex-oss-x86_64-pc-windows-msvc.zip](https://github.com/gdcorp-im/codex-oss-bundle/releases/latest)

### 2. Install

**macOS:**
```bash
# Extract the archive
tar -xzf codex-oss-*.tar.gz

# Move to a directory in your PATH
sudo mv codex-oss-* /usr/local/bin/codex-oss

# Make executable
chmod +x /usr/local/bin/codex-oss

# Remove quarantine attribute (required on macOS)
xattr -d com.apple.quarantine /usr/local/bin/codex-oss
```

**Linux:**
```bash
# Extract the archive
tar -xzf codex-oss-*.tar.gz

# Move to a directory in your PATH
sudo mv codex-oss-* /usr/local/bin/codex-oss

# Make executable
chmod +x /usr/local/bin/codex-oss
```

**Windows:**
```powershell
# Extract the .zip file (right-click → Extract All)
# Then add the directory to your PATH, or run directly:
.\codex-oss.exe
```

### 3. Run

```bash
codex-oss
```

On first run:
- The embedded Ollama server will start automatically
- The default AI model will download (one-time only)
- Once complete, you can start coding!

### Model Selection

By default, codex-oss uses **gpt-oss:20b** (~13GB), which has excellent tool-calling behavior for agentic coding tasks. You can change the model by setting the `CODEX_OSS_MODEL` environment variable:

```bash
# Use a different model
export CODEX_OSS_MODEL="qwen2.5-coder:7b"
codex-oss

# Or use a specific model for one session
CODEX_OSS_MODEL="qwen2.5-coder:7b" codex-oss
```

**Recommended models for agentic coding (with tool support):**
- `gpt-oss:20b` - Best for agentic tasks (13GB) **default & recommended**
- `qwen2.5-coder:7b` - Smaller, faster, less agentic (4.7GB)
- `qwen2.5-coder:32b` - Larger, slower, less agentic (19GB)

**Important**: Not all models work well for agentic coding. Models must:
1. Support tool calling (function calling)
2. Be trained to use tools proactively for file operations

Models like `deepseek-coder-v2` don't support tool calling and won't work with codex-oss.

You can browse all available models at https://ollama.com/library

## Features

✅ **Completely Free** - No API keys, no subscriptions, no usage fees
✅ **100% Offline** - Runs entirely on your machine after initial model download
✅ **Private** - Your code never leaves your computer
✅ **No Setup** - Single binary with everything embedded
✅ **Cross-Platform** - Works on macOS, Linux x86_64, and Linux ARM64

## System Requirements

- **RAM**: 16GB minimum (32GB recommended for larger models)
- **Disk**: 10-20GB free space depending on model
- **OS**: macOS 10.15+, Linux (kernel 3.2+), Windows 10+

## Usage Examples

Start an interactive session:
```bash
codex-oss
```

Use a specific model (120B instead of default 20B):
```bash
codex-oss -m gpt-oss:120b
```

Start with a prompt:
```bash
codex-oss "Create a Python web scraper"
```

## Model Options

- **gpt-oss:20b** (default): Faster, 12GB download, requires 16GB RAM
- **gpt-oss:120b**: More capable, 70GB download, requires 80GB RAM

## How It Works

Codex OSS bundles:
1. **The Codex CLI** - Full Codex functionality
2. **Ollama** - Local AI model server (embedded)
3. **GPT-OSS Models** - Open-source language models

When you run `codex-oss`, it:
1. Extracts Ollama to `~/.codex-oss/bin/`
2. Starts Ollama server on an available port
3. Downloads the AI model (first run only)
4. Launches the Codex interactive interface

## Uninstall

```bash
# Remove the binary
sudo rm /usr/local/bin/codex-oss

# Remove downloaded models (optional - frees ~15GB)
rm -rf ~/.codex-oss/
```

## Troubleshooting

### macOS: "Apple could not verify codex-oss is free of malware"
Run this command to remove the quarantine flag:
```bash
xattr -d com.apple.quarantine /usr/local/bin/codex-oss
```

### "Ollama server failed to start"
- Check that port 8000-9000 range is available
- Ensure you have at least 16GB RAM

### Model download is slow
- First download can take 20-60 minutes depending on connection
- Downloads are cached - subsequent runs are instant

### Out of memory errors
- Close other applications
- Try the 20B model instead of 120B
- Ensure you have at least 16GB RAM

## FAQ

**Q: Is this really free?**
A: Yes, completely free with no hidden costs.

**Q: Does this work offline?**
A: Yes, after the initial model download.

**Q: How does it compare to ChatGPT/Claude?**
A: The 20B model is comparable to GPT-3.5, the 120B is closer to GPT-4 quality.

**Q: Can I use this commercially?**
A: Check the Apache-2.0 license for details. The models have their own licenses.

**Q: Is this affiliated with OpenAI?**
A: No, this is an independent project using open-source models.

## License

Apache-2.0 (see LICENSE file)

## Support

- Report issues: https://github.com/gdcorp-im/codex-oss-bundle/issues

---

Made with ❤️ for the open source community
