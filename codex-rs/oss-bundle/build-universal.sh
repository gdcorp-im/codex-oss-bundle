#!/bin/bash
set -e

echo "Building universal macOS binary for codex-oss..."

# Build for both architectures
echo "Building for ARM64..."
cargo build --release -p codex-oss-bundle --target aarch64-apple-darwin

echo "Building for x86_64..."
cargo build --release -p codex-oss-bundle --target x86_64-apple-darwin

# Create universal binary
echo "Creating universal binary..."
mkdir -p target/universal-apple-darwin/release
lipo -create \
    target/aarch64-apple-darwin/release/codex-oss \
    target/x86_64-apple-darwin/release/codex-oss \
    -output target/universal-apple-darwin/release/codex-oss

echo "Verifying universal binary..."
lipo -info target/universal-apple-darwin/release/codex-oss
file target/universal-apple-darwin/release/codex-oss

echo ""
echo "Universal binary created at: target/universal-apple-darwin/release/codex-oss"
ls -lh target/universal-apple-darwin/release/codex-oss
