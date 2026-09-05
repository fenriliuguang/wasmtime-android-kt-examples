#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
SCENARIO="${1:-compute}"
case "$SCENARIO" in
  compute|texture|pointer|cli|fs|tcp) ;;
  *)
    echo "usage: $0 {compute|texture|pointer|cli|fs|tcp}" >&2
    exit 2
    ;;
esac
cp "scenarios/${SCENARIO}.mbt" gen/world/guest/run.mbt
moon build --target wasm --release
mkdir -p dist
core=_build/wasm/release/build/gen/gen.wasm
wasm-tools component embed wit "$core" --encoding utf16 -o _build/embedded.wasm
wasm-tools component new _build/embedded.wasm -o "dist/${SCENARIO}.wasm"
echo "wrote dist/${SCENARIO}.wasm"
