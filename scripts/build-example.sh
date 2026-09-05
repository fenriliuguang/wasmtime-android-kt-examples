#!/usr/bin/env bash
# Build one scriptable example APK and optionally install it.
# Usage: scripts/build-example.sh <example> [--install]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="${1:-}"
if [[ -z "$EXAMPLE" ]]; then
  echo "usage: $0 {cube|border2d|compute|texture|pointer|cli|fs|tcp|http-tcp} [--install]" >&2
  exit 2
fi
INSTALL=0
if [[ "${2:-}" == "--install" ]]; then
  INSTALL=1
fi

build_guest() {
  case "$EXAMPLE" in
    cube) (cd "$ROOT/guests/rotating-cube" && ./build.sh) ;;
    border2d) (cd "$ROOT/guests/boundary-2d" && ./build.sh) ;;
    compute|texture|pointer|cli|fs|tcp)
      (cd "$ROOT/guests/kit" && ./build.sh "$EXAMPLE")
      ;;
    http-tcp) (cd "$ROOT/guests/http-tcp" && ./build.sh) ;;
    *)
      echo "unknown example: $EXAMPLE" >&2
      exit 2
      ;;
  esac
}

echo "== guest $EXAMPLE =="
build_guest

HOST="$ROOT/hosts/fullscreen-surface"
echo "== host -Pexample=$EXAMPLE =="
TASK=":app:assembleDebug"
if [[ "$INSTALL" -eq 1 ]]; then
  TASK=":app:installDebug"
fi
(cd "$HOST" && ./gradlew "$TASK" "-Pexample=$EXAMPLE")
echo "ok example=$EXAMPLE"
