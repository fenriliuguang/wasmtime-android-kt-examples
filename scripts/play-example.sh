#!/usr/bin/env bash
# Launch one installed example and wait for EXAMPLE_OK / EXAMPLE_FAIL.
# Usage: scripts/play-example.sh <example> [timeout_sec]
set -euo pipefail
EXAMPLE="${1:-}"
TIMEOUT="${2:-30}"
if [[ -z "$EXAMPLE" ]]; then
  echo "usage: $0 {cube|border2d|compute|texture|pointer|cli|fs|tcp|http-tcp} [timeout_sec]" >&2
  exit 2
fi

PKG_BASE="io.github.fenriliuguang.wasmtime.android.examples.fullscreen"
declare -A PKG SUFFIX ACT TAG EXPECT
PKG["cube"]="$PKG_BASE"
ACT["cube"]=".MainActivity"
TAG["cube"]="FullscreenSurface"
EXPECT["cube"]="" # frame count; not a smoke code

PKG["border2d"]="$PKG_BASE.border2d"
ACT["border2d"]=".Border2dActivity"
TAG["border2d"]="FullscreenBorder2d"
EXPECT["border2d"]=""

PKG["compute"]="$PKG_BASE.compute"
ACT["compute"]=".ComputeActivity"
TAG["compute"]="ExampleCompute"
EXPECT["compute"]="1"

PKG["texture"]="$PKG_BASE.texture"
ACT["texture"]=".TextureActivity"
TAG["texture"]="ExampleTexture"
EXPECT["texture"]="1"

PKG["pointer"]="$PKG_BASE.pointer"
ACT["pointer"]=".PointerActivity"
TAG["pointer"]="ExamplePointer"
EXPECT["pointer"]="1"

PKG["cli"]="$PKG_BASE.cli"
ACT["cli"]=".CliActivity"
TAG["cli"]="ExampleCli"
EXPECT["cli"]="4"

PKG["fs"]="$PKG_BASE.fs"
ACT["fs"]=".FsActivity"
TAG["fs"]="ExampleFs"
EXPECT["fs"]="4"

PKG["tcp"]="$PKG_BASE.tcp"
ACT["tcp"]=".TcpActivity"
TAG["tcp"]="ExampleTcp"
EXPECT["tcp"]="4"

PKG["http-tcp"]="$PKG_BASE.httptcp"
ACT["http-tcp"]=".HttpTcpActivity"
TAG["http-tcp"]="ExampleHttpTcp"
EXPECT["http-tcp"]="4"

if [[ -z "${PKG[$EXAMPLE]+x}" ]]; then
  echo "unknown example: $EXAMPLE" >&2
  exit 2
fi

COMP="${PKG[$EXAMPLE]}/${PKG_BASE}${ACT[$EXAMPLE]}"
adb logcat -c
adb shell am force-stop "${PKG[$EXAMPLE]}" >/dev/null 2>&1 || true
adb shell am start -W -n "$COMP"
echo "started $COMP (timeout ${TIMEOUT}s)"
END=$((SECONDS + TIMEOUT))
while (( SECONDS < END )); do
  if adb logcat -d -s "${TAG[$EXAMPLE]}:I" "${TAG[$EXAMPLE]}:E" | grep -q "EXAMPLE_OK example=$EXAMPLE"; then
    LINE="$(adb logcat -d | grep "EXAMPLE_OK example=$EXAMPLE" | tail -n 1)"
    echo "$LINE"
    CODE="$(echo "$LINE" | sed -n 's/.*code=\([0-9][0-9]*\).*/\1/p')"
    WANT="${EXPECT[$EXAMPLE]}"
    if [[ -n "$WANT" && "$CODE" != "$WANT" ]]; then
      echo "FAIL expected code=$WANT got code=$CODE" >&2
      exit 1
    fi
    echo "PASS example=$EXAMPLE code=$CODE"
    exit 0
  fi
  if adb logcat -d | grep -q "EXAMPLE_FAIL example=$EXAMPLE"; then
    adb logcat -d | grep "EXAMPLE_FAIL example=$EXAMPLE" | tail -n 5
    echo "FAIL example=$EXAMPLE" >&2
    exit 1
  fi
  sleep 1
done
echo "TIMEOUT example=$EXAMPLE after ${TIMEOUT}s" >&2
adb logcat -d -s "${TAG[$EXAMPLE]}:*" | tail -n 40 >&2
exit 1
