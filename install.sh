#!/bin/bash
# ZCode Widget — one-command installer for other ZCode users.
# Builds from source and installs the app + launcher.
#
# Usage:  ./install.sh
# Needs:  macOS 13+, Xcode command line tools, xcodegen (brew install xcodegen)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ZCodeWidget"
INSTALL_DIR="/Applications"
BIN_DIR="/usr/local/bin"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
error() { printf "\033[1;31mError:\033[0m %s\n" "$1" >&2; exit 1; }

# --- prerequisites -----------------------------------------------------------
[[ "$(uname)" == "Darwin" ]] || error "macOS only."
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ]] || error "macOS 13.0+ required."

if ! xcode-select -p >/dev/null 2>&1; then
    info "Xcode command line tools not found — installing (may prompt)…"
    xcode-select --install || error "Install Xcode command line tools, then re-run."
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        info "Installing xcodegen via Homebrew…"
        brew install xcodegen
    else
        error "xcodegen is required. Install Homebrew (brew.sh) then: brew install xcodegen"
    fi
fi

# --- build -------------------------------------------------------------------
info "Generating Xcode project…"
cd "$REPO_DIR"
xcodegen generate

info "Building (Release)…"
xcodebuild -project ZCodeWidget.xcodeproj -scheme ZCodeWidget \
    -configuration Release -derivedDataPath build build \
    -quiet || error "Build failed."

BUILT_APP="build/Build/Products/Release/${APP_NAME}.app"
[[ -d "$BUILT_APP" ]] || error "Built app not found at $BUILT_APP"

# --- install -----------------------------------------------------------------
info "Installing to $INSTALL_DIR (may ask for your password)…"
if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    rm -rf "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || sudo rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi
cp -R "$BUILT_APP" "$INSTALL_DIR/" 2>/dev/null || sudo cp -R "$BUILT_APP" "$INSTALL_DIR/"

# --- launcher ----------------------------------------------------------------
info "Installing launcher to $BIN_DIR/zcode-widget…"
LAUNCHER='#!/bin/bash
APP_PATH="'"$INSTALL_DIR/$APP_NAME.app"'"
pkill -f "'"${APP_NAME}"'" 2>/dev/null
sleep 0.3
open "$APP_PATH"'

if [[ -w "$BIN_DIR" ]]; then
    printf '%s\n' "$LAUNCHER" > "$BIN_DIR/zcode-widget"
    chmod +x "$BIN_DIR/zcode-widget"
else
    printf '%s\n' "$LAUNCHER" | sudo tee "$BIN_DIR/zcode-widget" >/dev/null
    sudo chmod +x "$BIN_DIR/zcode-widget"
fi

info "Done! Look for the Z icon in your menu bar."
echo    "    • Toggle panel:   left-click the Z icon (or run: zcode-widget)"
echo    "    • Menu:           right-click the Z icon"
echo    "    • The widget reads your ZCode data from ~/.zcode/ automatically."
