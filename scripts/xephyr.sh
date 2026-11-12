#!/usr/bin/env bash
# Abre una pantalla anidada (Xephyr) y arranca Fenster dentro,
# sin tocar la sesión real. Cierra la ventana de Xephyr para terminar.
set -euo pipefail

cd "$(dirname "$0")/.."
DISP="${FENSTER_DISPLAY:-:3}"
SIZE="${FENSTER_SIZE:-1280x800}"

make -s

Xephyr "$DISP" -screen "$SIZE" -ac -br -reset -terminate >/dev/null 2>&1 &
XEPHYR=$!
trap 'kill $XEPHYR 2>/dev/null || true' EXIT
sleep 1

export DISPLAY="$DISP"
G_MESSAGES_DEBUG="${G_MESSAGES_DEBUG:-Fenster}" ./build/fenster &

# Apps de prueba: una con decoración propia (CSD) y una clásica
(command -v tilix >/dev/null && tilix --new-process) >/dev/null 2>&1 &
(command -v xterm >/dev/null && xterm) >/dev/null 2>&1 &
# Para probar picom dentro:  DISPLAY=$DISP picom --config data/picom/fenster.conf &

wait "$XEPHYR"
