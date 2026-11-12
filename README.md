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

## Usarlo como gestor de ventanas predeterminado

```sh
make install     # ~/.local/bin/fenster y ~/.local/bin/fenster-session
```

y una entrada de arranque automático en `~/.config/autostart/fenster.desktop`
con `Exec=$HOME/.local/bin/fenster-session`.

`fenster-session` deja que XFCE arranque xfwm4 y lo sustituye a los 2
segundos. **Si Fenster se cae, vuelve a lanzar xfwm4 al instante**: nunca te
quedas sin gestor de ventanas. El registro queda en
`~/.local/state/fenster.log`.

Para volver a xfwm4 como predeterminado: borra (o pon `Hidden=true` en)
`~/.config/autostart/fenster.desktop`. Para cambiar solo en la sesión actual:
`xfwm4 --replace &` (Fenster sale con normalidad y no se relanza nada).

## Pruebas automáticas

```sh
./scripts/test.sh
```

Monta dos monitores virtuales invisibles (Xvfb + Xephyr anidado), simula
teclado y ratón (`scripts/fake-input.py`) y comprueba colocación, ajuste,
saltos entre monitores, Alt+Tab, arrastre, escritorios, capas, pistas de
tamaño, modales, urgencia, robo de foco, el panel del Alt+Tab (píxel a
píxel), iconos, vista previa del ajuste, cuartos, animación de minimizar y
reglas por aplicación, redimensionado enlazado, transiciones, barra de
título y bordes invisibles (128 comprobaciones; tarda unos 4 minutos). Necesita
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

## Configuración

`~/.config/fenster/fenster.conf` (o `fenster --config RUTA`). Se recarga sola
al guardar y afecta a las ventanas que se abran después.

```ini
# Los comentarios van siempre en su propia línea: el formato no admite
# comentarios al final de una línea (el valor se leería entero).

[General]
# si no hay un gestor previo del que heredarlos
escritorios = 4
# animación al minimizar/restaurar
animaciones = true
# las ventanas pegadas cambian de tamaño juntas
redimension-enlazada = true
# barra propia para las apps que no dibujan la suya (Thunar, xterm…)
barras-de-titulo = true

# Cualquier grupo que empiece por «Regla»
[Regla Tilix]
# WM_CLASS: xprop WM_CLASS + clic en la ventana
clase = Tilix
# o 1200x800
tamaño = 60%x70%
# o 100,80 (relativo al monitor)
posicion = centro

[Regla Telegram]
clase = TelegramDesktop
# 1…n o «todos»
escritorio = 2

[Regla preferencias]
# expresión regular sobre el título
titulo = ^Preferencias
# maximizada, pantalla-completa, minimizada, izquierda, derecha,
# arriba-izquierda, arriba-derecha, abajo-izquierda, abajo-derecha
estado = derecha
encima = true
en-alt-tab = false
# no darle el foco al abrirse
enfocar = false
# principal, 1, 2…
monitor = principal
```

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
| Redimensionar junto a otras | Las ventanas pegadas se ajustan a la vez (borde común) |
| Barra de título (apps sin la suya) | Arrastrar = mover · doble clic = maximizar · – + ✕ a la derecha |
| Bordes de cualquier ventana | Arrastrar para redimensionar (también esquinas) |

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
src/linked-resize.vala   redimensionado enlazado de ventanas pegadas
src/minimize.vala        animación de minimizar/restaurar en el sitio
src/morph.vala           transición animada al maximizar, ajustar o cambiar de monitor
src/decoration.vala      barra de título propia para apps sin decoración
src/handles.vala         bordes invisibles para redimensionar cualquier ventana
src/config.vala          configuración y reglas por aplicación
src/icons.vala           iconos: _NET_WM_ICON, .desktop y tema (sin GTK)
src/style.vala           tokens visuales y de movimiento (de Dock-e)
src/xconst.vala          constantes de X11
vapi/xextra.vapi         bindings de Xlib que faltan en Vala
data/picom/fenster.conf  animaciones y reglas para picom v12
scripts/build-picom.sh   compila picom v12 en ~/.local/opt/picom-12
scripts/fenster-session  arranque en la sesión con vuelta a xfwm4 si Fenster falla
scripts/xephyr.sh        entorno de pruebas anidado (visible)
scripts/test.sh          pruebas automáticas (invisibles)
scripts/fake-input.py    simulador de teclado y ratón (XTest)
scripts/test-client.py   ventanas GTK con comportamientos concretos (pruebas)
```

## Depuración

```sh
G_MESSAGES_DEBUG=all ./build/fenster
```
