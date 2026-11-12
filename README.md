# Fenster

Gestor de ventanas ligero para X11, escrito en Vala, pensado para
Linux Mint XFCE junto a Dock-e y picom.

> *Fenster* = "ventana" en alemán.

Estado: **v0.3.0-dev — fase 3 (estilo) en curso: Alt+Tab propio e iconos listos**. Ver [docs/PLAN.md](docs/PLAN.md).

## Compilar

Dependencias (ya presentes en este equipo):

```sh
sudo apt install valac libglib2.0-dev libx11-dev libxrandr-dev libxinerama-dev \
                 libcairo2-dev libgdk-pixbuf-2.0-dev xserver-xephyr
```

## Animaciones (picom v12)

Fenster no anima por sí mismo: marca cada ventana con `_FENSTER_ANIM` y
picom v12 ejecuta la animación. El sistema trae picom v10 (sin animaciones):

```sh
./scripts/build-picom.sh     # dice qué instalar con apt; luego compila
pkill -x picom; ~/.local/opt/picom-12/bin/picom --config data/picom/fenster.conf &
```

```sh
make            # genera build/fenster
make install    # copia a ~/.local/bin/fenster
```

## Probar sin riesgo

```sh
make run-xephyr
```

Abre una pantalla anidada con Fenster, Tilix y xterm dentro. Tu sesión real
no se toca.

## Pruebas automáticas

```sh
./scripts/test.sh
```

Monta dos monitores virtuales invisibles (Xvfb + Xephyr anidado), simula
teclado y ratón (`scripts/fake-input.py`) y comprueba colocación, ajuste,
saltos entre monitores, Alt+Tab, arrastre, escritorios, capas, pistas de
tamaño, modales, urgencia, robo de foco, el panel del Alt+Tab (píxel a
píxel), iconos, vista previa del ajuste y cuartos (72 comprobaciones). Necesita
`xterm`, `wmctrl`, `xprop`, `xwininfo` y python3-gi (GTK 3).

## Probar en la sesión real

```sh
fenster --replace &      # sustituye a xfwm4
xfwm4 --replace &        # vuelve a xfwm4 en cualquier momento
```

Si algo falla y no puedes usar el ratón: Ctrl+Alt+F3, inicia sesión y
ejecuta `DISPLAY=:0 xfwm4 --replace &`.

Al reemplazar a xfwm4, Fenster conserva el número de escritorios, el
escritorio actual, en qué escritorio estaba cada ventana y cuál tenía el foco.
Al salir o ser reemplazado, vuelve a mostrar todas las ventanas que tenía
ocultas para que el siguiente gestor las encuentre.

## Atajos

| Atajo | Acción |
|---|---|
| Alt + Tab / Alt + Shift + Tab | App siguiente / anterior (uso reciente, como macOS) |
| Alt + Tab, luego ← / → / Esc / Intro | Navegar / cancelar / confirmar en el panel |
| Alt + ` | Siguiente ventana de la misma app |
| Alt + F4 | Cerrar |
| Super + ← / → | Ajustar a la mitad izquierda / derecha |
| Super + ↑ | Maximizar / restaurar; desde una mitad: cuarto superior → maximizar |
| Super + ↓ | Restaurar o minimizar; desde una mitad: cuarto inferior → restaurar |
| Super + Shift + ← / → | Mover la ventana al monitor izquierdo / derecho |
| Super + ← / → (ya ajustada a ese lado) | Saltar al monitor vecino |
| Super + T | Siempre encima (activar / desactivar) |
| Super + 1…9 | Ir al escritorio 1…9 |
| Super + Shift + 1…9 | Enviar la ventana al escritorio 1…9 |
| Ctrl + Alt + ← / → | Escritorio anterior / siguiente |
| Ctrl + Alt + Shift + ← / → | Llevar la ventana al escritorio anterior / siguiente |
| Alt + arrastrar (clic izq.) | Mover |
| Alt + arrastrar (clic der.) | Redimensionar desde la esquina más cercana |
| Arrastrar a un borde / esquina | Vista previa; al soltar: mitad, cuarto o maximizar (arriba) |

## Estructura

```
src/main.vala            argumentos y arranque
src/window-manager.vala  núcleo: eventos, foco, apilado, ajuste, EWMH
src/client.vala          estado de cada ventana
src/monitors.vala        monitores (RandR/Xinerama) y área útil por monitor
src/atoms.vala           atoms ICCCM / EWMH
src/argb-window.vala     ventanas propias transparentes dibujadas con cairo
src/switcher.vala        panel del Alt+Tab
src/snap.vala            zonas de ajuste (mitades, cuartos) y su vista previa
src/icons.vala           iconos: _NET_WM_ICON, .desktop y tema (sin GTK)
src/style.vala           tokens visuales y de movimiento (de Dock-e)
src/xconst.vala          constantes de X11
vapi/xextra.vapi         bindings de Xlib que faltan en Vala
data/picom/fenster.conf  animaciones y reglas para picom v12
scripts/build-picom.sh   compila picom v12 en ~/.local/opt/picom-12
scripts/xephyr.sh        entorno de pruebas anidado (visible)
scripts/test.sh          pruebas automáticas (invisibles)
scripts/fake-input.py    simulador de teclado y ratón (XTest)
scripts/test-client.py   ventanas GTK con comportamientos concretos (pruebas)
```

## Depuración

```sh
G_MESSAGES_DEBUG=all ./build/fenster
```
