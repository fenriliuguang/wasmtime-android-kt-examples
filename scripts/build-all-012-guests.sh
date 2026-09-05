#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$ROOT/guests/kit" && ./build.sh compute && ./build.sh texture && ./build.sh pointer && ./build.sh cli && ./build.sh fs && ./build.sh tcp)
(cd "$ROOT/guests/http-tcp" && ./build.sh)
echo "all 0.1.2 scenario wasm written under guests/kit/dist and guests/http-tcp/dist"
