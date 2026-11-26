cat << 'EOF' > ~/rapx-manager.sh
#!/usr/bin/env bash

# Auto-open Terminal on double-click / Tu dong mo Terminal khi click dup
if [ ! -t 0 ]; then
    SCRIPT_PATH="$(readlink -f "$0")"
    for term in konsole gnome-terminal xfce4-terminal x-terminal-emulator mate-terminal lxterminal tilix alacritty kitty xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            case "$term" in
                gnome-terminal|tilix) exec "$term" -- bash "$SCRIPT_PATH" "$@" ;;
                *) exec "$term" -e bash "$SCRIPT_PATH" "$@" ;;
            esac
        fi
    done
    exit 1
fi

set -e

GIT_HOST="github.com"
REPO_PATH="heshamhabib/rapx"
REPO_URL="https://${GIT_HOST}/${REPO_PATH}"
DOTNET_HOST="dot.net"
DOTNET_SCRIPT="https://${DOTNET_HOST}/v1/dotnet-install.sh"
APPIMAGE_REPO="AppImage/appimagetool"
RUNTIME_REPO="AppImage/type2-runtime"
GH_REL="releases/download/continuous"

APP_NAME="rapx"
APP_TITLE="Red Alert: Project X"
VERSION="1.0.0"

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DEB_ARCH="amd64"
    APPIMAGE_ARCH="x86_64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    DEB_ARCH="arm64"
    APPIMAGE_ARCH="aarch64"
else
    DEB_ARCH="$ARCH"
    APPIMAGE_ARCH="$ARCH"
fi

APPIMAGE_TOOL_URL="https://${GIT_HOST}/${APPIMAGE_REPO}/${GH_REL}/appimagetool-${APPIMAGE_ARCH}.AppImage"
RUNTIME_URL="https://${GIT_HOST}/${RUNTIME_REPO}/${GH_REL}/runtime-${APPIMAGE_ARCH}"

WORK_DIR="$HOME/rapx-build/workspace"
SRC_DIR="$WORK_DIR/rapx-main"
PKG_DIR="$WORK_DIR/pkg-root"
APP_DIR="$WORK_DIR/RAPX.AppDir"
OUT_DIR="$HOME/RAPX-Packages"

DEB_OUTPUT="$OUT_DIR/${APP_NAME}_${VERSION}_${DEB_ARCH}.deb"
APPIMAGE_OUTPUT="$OUT_DIR/Red_Alert_Project_X-${VERSION}-${APPIMAGE_ARCH}.AppImage"

if [ "$EUID" -eq 0 ]; then
    echo "[ERROR / LOI] Please run as a normal user (do not use root)."
    echo "              Vui long chay script bang tai khoan user thuong (khong dung root)."
    read -rp "Press Enter to exit / Nhan Enter de thoat..."
    exit 1
fi

install_dotnet_manual() {
    if ! dotnet --list-sdks 2>/dev/null | grep -q "^6\.0\."; then
        echo "[*] Installing .NET 6.0 SDK / Dang cai dat .NET 6.0 SDK..."
        wget -q "$DOTNET_SCRIPT" -O /tmp/dotnet-install.sh
        chmod +x /tmp/dotnet-install.sh
        sudo /tmp/dotnet-install.sh --channel 6.0 --install-dir /usr/share/dotnet
        sudo ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    fi
}

install_dependencies() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$ID
        DISTRO_LIKE=$ID_LIKE
    else
        DISTRO_ID="unknown"
    fi
    echo "[*] Detected OS / He dieu hanh phat hien: ${NAME:-Linux} ($DISTRO_ID)"
    echo "[*] Installing dependencies / Dang cai dat thu vien phu thuoc..."

    if [[ "$DISTRO_ID" =~ ^(biglinux|manjaro|arch|endeavouros|garuda|cachyos)$ ]] || [[ "$DISTRO_LIKE" == *"arch"* ]]; then
        sudo pacman -Syu --needed --noconfirm git base-devel openal libgl freetype2 sdl2 lua51 dotnet-sdk-6.0 wget unzip rsync dpkg fuse2
    elif [[ "$DISTRO_ID" =~ ^(ubuntu|debian|linuxmint|pop|zorin|mx|kali)$ ]] || [[ "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        sudo apt-get update
        sudo apt-get install -y git build-essential libfreetype6 libopenal1 liblua5.1-0 libsdl2-2.0-0 wget unzip dpkg-dev rsync libfuse2
        install_dotnet_manual
    elif [[ "$DISTRO_ID" =~ ^(fedora|nobara|bazzite|rhel|almalinux|rocky)$ ]] || [[ "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* ]]; then
        sudo dnf install -y git gcc-c++ make SDL2 freetype "lua = 5.1" openal-soft wget unzip rsync dpkg fuse fuse-libs
        install_dotnet_manual
    elif [[ "$DISTRO_ID" == *"opensuse"* || "$DISTRO_ID" == *"suse"* ]] || [[ "$DISTRO_LIKE" == *"suse"* ]]; then
        sudo zypper install -y git gcc-c++ make openal-soft freetype2 SDL2 lua51 wget unzip rsync dpkg fuse libfuse2
        install_dotnet_manual
    elif [[ "$DISTRO_ID" == "void" ]]; then
        sudo xbps-install -Sy git base-devel openal freetype SDL2 lua51 wget unzip rsync fuse
        install_dotnet_manual
    else
        install_dotnet_manual
    fi
}

build_source() {
    install_dependencies
    mkdir -p "$WORK_DIR" "$OUT_DIR"
    cd "$WORK_DIR"
    rm -rf "$SRC_DIR" main.zip
    echo "[*] Downloading source code / Dang tai ma nguon tu: ${REPO_URL}"
    wget -O main.zip "${REPO_URL}/archive/refs/heads/main.zip"
    unzip -q main.zip
    rm -f main.zip
    echo "[*] Compiling game / Dang bien dich game..."
    cd "$SRC_DIR"
    make
}
EOF
cat << 'EOF' >> ~/rapx-manager.sh

package_and_install_system() {
    local INSTALL_TO_OS="$1"
    rm -rf "$PKG_DIR"
    mkdir -p "$PKG_DIR/opt/$APP_NAME" "$PKG_DIR/usr/bin" "$PKG_DIR/usr/share/applications" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"
    rsync -a "$SRC_DIR/" "$PKG_DIR/opt/$APP_NAME/"

    cat << 'LAUNCHER' > "$PKG_DIR/usr/bin/rapx"
#!/usr/bin/env bash
cd /opt/rapx || exit 1
exec ./launch-game.sh "$@"
LAUNCHER
    chmod +x "$PKG_DIR/usr/bin/rapx"

    ICON_PATH=$(find "$SRC_DIR" -iname "*icon*.png" -o -iname "*logo*.png" | head -n 1)
    [ -n "$ICON_PATH" ] && cp "$ICON_PATH" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png"

    cat << DESKTOP > "$PKG_DIR/usr/share/applications/$APP_NAME.desktop"
[Desktop Entry]
Name=$APP_TITLE
Comment=Red Alert rebuilt as a modern HD strategy game
Exec=/usr/bin/rapx
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Game;StrategyGame;
StartupNotify=true
DESKTOP

    if command -v dpkg-deb >/dev/null 2>&1; then
        echo "[*] Packaging .deb file / Dang dong goi file .deb..."
        mkdir -p "$PKG_DIR/DEBIAN"
        INSTALLED_SIZE=$(du -sk "$PKG_DIR" | cut -f1)
        cat << CONTROL > "$PKG_DIR/DEBIAN/control"
Package: $APP_NAME
Version: $VERSION
Section: games
Priority: optional
Architecture: $DEB_ARCH
Installed-Size: $INSTALLED_SIZE
Depends: libfreetype6, libopenal1, liblua5.1-0, libsdl2-2.0-0
Maintainer: RAPX Universal Packager
Description: Red Alert: Project X (HD Strategy Game)
 The Red Alert you remember, rebuilt as a modern HD strategy game.
CONTROL
        rm -f "$DEB_OUTPUT"
        dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_OUTPUT"
    fi

    if [ "$INSTALL_TO_OS" = "yes" ]; then
        echo "[*] Installing to system / Dang cai dat vao he thong..."
        if command -v apt-get >/dev/null 2>&1 && [ -f "$DEB_OUTPUT" ]; then
            sudo apt-get install -y "$DEB_OUTPUT"
        else
            sudo rm -rf "/opt/$APP_NAME"
            sudo cp -r "$PKG_DIR/opt/$APP_NAME" /opt/
            sudo cp "$PKG_DIR/usr/bin/rapx" /usr/bin/
            sudo cp "$PKG_DIR/usr/share/applications/$APP_NAME.desktop" /usr/share/applications/
            [ -f "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" ] && sudo cp "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" /usr/share/icons/hicolor/256x256/apps/
            sudo update-desktop-database /usr/share/applications 2>/dev/null || true
        fi
        echo "[OK] Installed successfully / Da cai dat hoan chinh vao may!"
    fi
}

package_appimage() {
    echo "[*] Packaging AppImage / Dang dong goi file AppImage..."
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/usr/share/$APP_NAME" "$APP_DIR/usr/share/dotnet" "$APP_DIR/usr/lib"
    rsync -a "$SRC_DIR/" "$APP_DIR/usr/share/$APP_NAME/"

    DOTNET_BIN=$(readlink -f "$(command -v dotnet)")
    DOTNET_ROOT_DIR=$(dirname "$DOTNET_BIN")
    if [ -d "$DOTNET_ROOT_DIR/shared" ]; then
        cp -a "$DOTNET_ROOT_DIR/dotnet" "$APP_DIR/usr/share/dotnet/"
        cp -a "$DOTNET_ROOT_DIR/host" "$APP_DIR/usr/share/dotnet/"
        cp -a "$DOTNET_ROOT_DIR/shared" "$APP_DIR/usr/share/dotnet/"
    fi

    for lib in libSDL2-2.0.so.0 libopenal.so.1 liblua5.1.so.0 liblua-5.1.so; do
        LIB_PATH=$(ldconfig -p 2>/dev/null | grep "$lib" | awk '{print $NF}' | head -n 1)
        [ -f "$LIB_PATH" ] && cp -L "$LIB_PATH" "$APP_DIR/usr/lib/"
    done

    cat << 'APPRUN' > "$APP_DIR/AppRun"
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
if [ -x "$HERE/usr/share/dotnet/dotnet" ]; then
    export DOTNET_ROOT="$HERE/usr/share/dotnet"
    export PATH="$DOTNET_ROOT:$PATH"
fi
export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH}"
cd "$HERE/usr/share/rapx" || exit 1
exec ./launch-game.sh "$@"
APPRUN
    chmod +x "$APP_DIR/AppRun"

    cat << DESKTOP > "$APP_DIR/$APP_NAME.desktop"
[Desktop Entry]
Name=$APP_TITLE
Comment=Red Alert rebuilt as a modern HD strategy game
Exec=AppRun
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Game;StrategyGame;
DESKTOP

    ICON_PATH=$(find "$SRC_DIR" -iname "*icon*.png" -o -iname "*logo*.png" | head -n 1)
    if [ -n "$ICON_PATH" ]; then
        cp "$ICON_PATH" "$APP_DIR/$APP_NAME.png"
        ln -sf "$APP_NAME.png" "$APP_DIR/.DirIcon"
    else
        printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' > "$APP_DIR/$APP_NAME.png"
    fi

    TOOL_BIN="$WORK_DIR/appimagetool-${APPIMAGE_ARCH}.AppImage"
    if [ ! -f "$TOOL_BIN" ]; then
        echo "[*] Downloading appimagetool / Dang tai cong cu appimagetool..."
        wget -q "$APPIMAGE_TOOL_URL" -O "$TOOL_BIN"
        chmod +x "$TOOL_BIN"
    fi

    RUNTIME_BIN="$WORK_DIR/runtime-${APPIMAGE_ARCH}"
    if [ ! -f "$RUNTIME_BIN" ]; then
        echo "[*] Downloading AppImage runtime / Dang tai AppImage runtime..."
        wget -q "$RUNTIME_URL" -O "$RUNTIME_BIN"
    fi

    rm -f "$APPIMAGE_OUTPUT"
    ARCH="$APPIMAGE_ARCH" "$TOOL_BIN" --appimage-extract-and-run --runtime-file "$RUNTIME_BIN" "$APP_DIR" "$APPIMAGE_OUTPUT"
    chmod +x "$APPIMAGE_OUTPUT"

    echo "=================================================================="
    echo "[SUCCESS / THANH CONG] Packages saved at / Cac goi da luu tai:"
    echo " -> $OUT_DIR"
    [ -f "$DEB_OUTPUT" ] && echo " -> .deb     : $DEB_OUTPUT"
    [ -f "$APPIMAGE_OUTPUT" ] && echo " -> AppImage : $APPIMAGE_OUTPUT"
    echo "=================================================================="
}

do_uninstall() {
    echo "[*] Uninstalling RAPX completely / Dang go bo hoan toan RAPX khoi may..."
    if command -v apt-get >/dev/null 2>&1 && dpkg -l 2>/dev/null | grep -qw "$APP_NAME"; then
        sudo apt-get remove --purge -y "$APP_NAME"
    fi
    sudo rm -rf "/opt/$APP_NAME" "/usr/bin/$APP_NAME" "/usr/share/applications/$APP_NAME.desktop" "/usr/share/icons/hicolor/256x256/apps/$APP_NAME.png" "/root/rapx-build"
    rm -rf "$HOME/rapx-build" "$HOME/rapx" "$HOME/.config/openra" "$HOME/.local/share/openra"
    sudo update-desktop-database /usr/share/applications 2>/dev/null || true
    echo "[OK] Uninstalled cleanly! / Da go bo sach se!"
    echo "     (Packages in $OUT_DIR are kept / Cac file goi trong $OUT_DIR duoc giu lai)"
}

while true; do
    clear
    echo "=================================================================="
    echo "   RAPX UNIVERSAL MANAGER - $APP_TITLE"
    echo "   User: $USER | Output / Thu muc xuat goi: $OUT_DIR"
    echo "=================================================================="
    echo "  1) Install to PC + Export .deb & .AppImage"
    echo "     Cai dat vao may + Xuat goi .deb & .AppImage"
    echo "  ----------------------------------------------------------------"
    echo "  2) Build & Export .deb + .AppImage ONLY (No system install)"
    echo "     Chi bien dich & Xuat goi .deb + .AppImage (Khong cai vao may)"
    echo "  ----------------------------------------------------------------"
    echo "  3) Completely uninstall game from PC"
    echo "     Go bo hoan toan game khoi may"
    echo "  ----------------------------------------------------------------"
    echo "  4) Exit / Thoat"
    echo "=================================================================="
    read -rp "Enter your choice / Nhap lua chon cua ban [1-4]: " CHOICE
    echo ""
    case "$CHOICE" in
        1)
            build_source
            package_and_install_system "yes"
            package_appimage
            read -rp "Press Enter to return to Menu / Nhan Enter de quay lai Menu..."
            ;;
        2)
            build_source
            package_and_install_system "no"
            package_appimage
            read -rp "Press Enter to return to Menu / Nhan Enter de quay lai Menu..."
            ;;
        3)
            do_uninstall
            read -rp "Press Enter to return to Menu / Nhan Enter de quay lai Menu..."
            ;;
        4)
            exit 0
            ;;
        *)
            echo "[ERROR / LOI] Invalid choice / Lua chon khong hop le."
            sleep 1
            ;;
    esac
done
EOF

chmod +x ~/rapx-manager.sh && ~/rapx-manager.sh
