#!/bin/bash
set -e

echo "Building codex-oss for all platforms..."
echo ""

# Array of targets to build
TARGETS=(
    "aarch64-apple-darwin"
    "x86_64-apple-darwin"
    "x86_64-unknown-linux-musl"
    "aarch64-unknown-linux-musl"
)

# Ensure all targets are installed
echo "Installing required targets..."
for target in "${TARGETS[@]}"; do
    echo "  - $target"
    rustup target add "$target" || true
done
echo ""

# Build for each target
for target in "${TARGETS[@]}"; do
    echo "Building for $target..."
    cargo build --release -p codex-oss-bundle --target "$target"
    echo ""
done

# Create macOS universal binary
if [[ -f "target/aarch64-apple-darwin/release/codex-oss" ]] && [[ -f "target/x86_64-apple-darwin/release/codex-oss" ]]; then
    echo "Creating macOS universal binary..."
    mkdir -p target/universal-apple-darwin/release
    lipo -create \
        target/aarch64-apple-darwin/release/codex-oss \
        target/x86_64-apple-darwin/release/codex-oss \
        -output target/universal-apple-darwin/release/codex-oss

    echo "Verifying macOS universal binary..."
    lipo -info target/universal-apple-darwin/release/codex-oss
    echo ""
fi

# Create dist directory with all binaries
echo "Creating distribution directory..."
mkdir -p dist

if [[ -f "target/universal-apple-darwin/release/codex-oss" ]]; then
    cp target/universal-apple-darwin/release/codex-oss dist/codex-oss-macos-universal
    echo "  ✓ dist/codex-oss-macos-universal"
fi

if [[ -f "target/x86_64-unknown-linux-musl/release/codex-oss" ]]; then
    cp target/x86_64-unknown-linux-musl/release/codex-oss dist/codex-oss-linux-x86_64
    echo "  ✓ dist/codex-oss-linux-x86_64"
fi

if [[ -f "target/aarch64-unknown-linux-musl/release/codex-oss" ]]; then
    cp target/aarch64-unknown-linux-musl/release/codex-oss dist/codex-oss-linux-arm64
    echo "  ✓ dist/codex-oss-linux-arm64"
fi

echo ""
echo "Build summary:"
ls -lh dist/
echo ""
echo "All platforms built successfully!"
