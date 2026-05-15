#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Claude Monitor"
EXEC_NAME="ClaudeMonitor"
APP="${APP_NAME}.app"

# Universal binary build (--arch arm64 --arch x86_64) requires full Xcode (xcbuild).
# With Command Line Tools only we fall back to a host-arch single-arch build.
HAS_XCODE=0
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
case "${DEV_DIR}" in
    *Xcode*.app/Contents/Developer) HAS_XCODE=1 ;;
esac

if [ "${HAS_XCODE}" = "1" ]; then
    echo "==> Building universal binary (arm64 + x86_64)…"
    swift build -c release --arch arm64 --arch x86_64
    BIN_PATH=".build/apple/Products/Release/${EXEC_NAME}"
    BUNDLE_DIR=".build/apple/Products/Release"
else
    HOST_ARCH="$(uname -m)"
    echo "==> Building single-arch binary (${HOST_ARCH}) — Command Line Tools only, no full Xcode."
    swift build -c release
    BIN_PATH=".build/release/${EXEC_NAME}"
    BUNDLE_DIR=".build/${HOST_ARCH}-apple-macosx/release"
fi

if [ ! -x "${BIN_PATH}" ]; then
    echo "error: build artifact not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${EXEC_NAME}"
cp Info.plist "${APP}/Contents/Info.plist"
cp Sources/ClaudeMonitor/Resources/claude.svg    "${APP}/Contents/Resources/"
cp Sources/ClaudeMonitor/Resources/codex.svg     "${APP}/Contents/Resources/"
cp Sources/ClaudeMonitor/Resources/AppIcon.icns  "${APP}/Contents/Resources/"
cp -R "${BUNDLE_DIR}/ClaudeMonitor_ClaudeMonitor.bundle" "${APP}/Contents/Resources/"

echo "==> Ad-hoc signing (lets Gatekeeper at least allow override on first open)…"
codesign --force --deep --sign - "${APP}"

echo ""
echo "Done. Built: $(pwd)/${APP}"
echo ""
echo "Next:"
echo "  1. mv \"${APP}\" /Applications/"
echo "  2. Right-click → Open (first launch only — Gatekeeper override for unsigned apps)"
