#!/usr/bin/env bash
# Compila picom v12 (animaciones) en ~/.local/opt/picom-12 sin tocar el
# picom v10 que usa la sesión. Para probarlo:
#   pkill -x picom; ~/.local/opt/picom-12/bin/picom --config data/picom/fenster.conf &
# y para volver al de siempre:
#   pkill -x picom; ~/.local/bin/picom --config ~/.config/picom/picom.conf &
set -euo pipefail

VERSION="${PICOM_VERSION:-v12.5}"
PREFIX="${PICOM_PREFIX:-$HOME/.local/opt/picom-12}"
SRC="${XDG_CACHE_HOME:-$HOME/.cache}/fenster/picom-$VERSION"

PKGS=(meson ninja-build cmake libconfig-dev libdbus-1-dev libegl-dev libev-dev libgl-dev
      libepoxy-dev libpcre2-dev libpixman-1-dev libx11-xcb-dev libxcb1-dev
      libxcb-composite0-dev libxcb-damage0-dev libxcb-glx0-dev libxcb-image0-dev
      libxcb-present-dev libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev
      libxcb-shape0-dev libxcb-util-dev libxcb-xfixes0-dev libxcb-sync-dev uthash-dev)

missing=()
for p in "${PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Faltan dependencias de compilación. Instálalas con:"
    echo
    echo "  sudo apt install ${missing[*]}"
    echo
    exit 1
fi

if [ ! -d "$SRC" ]; then
    mkdir -p "$(dirname "$SRC")"
    echo "Descargando picom $VERSION…"
    curl -fsSL "https://github.com/yshui/picom/archive/refs/tags/$VERSION.tar.gz" \
        | tar -xz -C "$(dirname "$SRC")"
    mv "$(dirname "$SRC")/picom-${VERSION#v}" "$SRC"
fi

cd "$SRC"
meson setup build --prefix "$PREFIX" --buildtype=release -Dwith_docs=false --reconfigure 2>/dev/null \
    || meson setup build --prefix "$PREFIX" --buildtype=release -Dwith_docs=false
ninja -C build
ninja -C build install

echo
"$PREFIX/bin/picom" --version
echo "Instalado en $PREFIX (el picom de la sesión no se ha tocado)."
