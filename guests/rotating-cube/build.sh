#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon build --target wasm --release
mkdir -p dist
core=_build/wasm/release/build/gen/gen.wasm
wasm-tools component embed wit "$core" --encoding utf16 -o _build/embedded.wasm
wasm-tools component new _build/embedded.wasm -o dist/guest.wasm
echo "wrote dist/guest.wasm"
