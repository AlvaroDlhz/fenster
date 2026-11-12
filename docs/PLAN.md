# Plan de Fenster

Gestor de ventanas ligero para X11 (Linux Mint XFCE), con el lenguaje visual
y el ritmo de animación de **Dock-e**.

## Principios

- **Ligero:** Vala → C nativo, solo Xlib + GLib. Sin marcos (non-reparenting).
- **Fenster decide, picom dibuja:** el gestor coloca las ventanas; las
  animaciones, esquinas y desenfoque los hace picom v12 en GPU.
- **Convive con XFCE:** respeta EWMH para que Dock-e, xfce4-panel y
  xfdesktop funcionen sin cambios. Se sustituye a xfwm4 con `--replace`.
- **Un solo sistema visual:** los tokens de `src/style.vala` salen del tema
  *Navbar* de Dock-e (negro sólido, radio 12 px, sin borde).

## Arquitectura

```
Fenster (Vala + Xlib)                 picom v12
 ventanas · foco · atajos ──EWMH──▶   animaciones · esquinas · blur
 ajuste · Alt+Tab · reglas            Dock-e · xfce4-panel · xfdesktop
```

## Animaciones (ejecutadas por picom)

| Acción | Animación | Duración | Origen en Dock-e |
|---|---|---|---|
| Abrir | aparecer + escala 95 %→100 % | 230 ms | ItemMoveTime |
| Cerrar | desvanecer + escala →95 % | 120 ms | HideTime |
| Minimizar / restaurar | encoger hacia el icono del dock | 300 ms | SlideTime |
| Maximizar / ajustar | transición de geometría | 300 ms | ActiveTime |
| Cambiar de escritorio | deslizamiento horizontal | 300 ms | SlideTime |
| Alt+Tab | aparecer + escala, selección deslizante | 120 ms | HideTime |

Curva: *ease-out*, sin rebotes (salvo avisos urgentes).

## Fases

### Fase 1 — Base ✅ (v0.1.0)
- [x] Toma de control (`WM_S0`, `--replace`, sale al ser reemplazado)
- [x] Gestionar / soltar ventanas, ventanas ya abiertas al arrancar
- [x] Clic para enfocar, orden MRU, `_NET_ACTIVE_WINDOW`
- [x] Capas: escritorio < ventanas < docks < pantalla completa
- [x] Struts de docks y paneles → `_NET_WORKAREA`
- [x] Mover (Alt+clic izq.) y redimensionar (Alt+clic der.)
- [x] `_NET_WM_MOVERESIZE` (arrastrar la barra de apps CSD como Tilix)
- [x] Maximizar, pantalla completa, minimizar (también desde Dock-e)
- [x] Ajuste a mitades: Super+←/→ y soltando en el borde; arriba = maximizar
- [x] Respeta `_GTK_FRAME_EXTENTS` (márgenes de sombra CSD) al ajustar
- [x] Alt+Tab básico en orden MRU (sin interfaz todavía)
- [x] Diálogos centrados sobre su ventana madre

### Fase 2 — Uso diario
- [x] Multimonitor (RandR 1.5, con Xinerama como alternativa)
  - área útil por monitor: los struts solo afectan a la pantalla que tocan
  - maximizar, ajustar y pantalla completa en el monitor de la ventana
  - ventanas nuevas en el monitor del puntero; diálogos en el de su madre
  - Super+Shift+←/→ mueve la ventana de monitor conservando su estado
  - Super+← estando ya a la izquierda salta al monitor vecino
  - soltar en un borde compartido no ajusta (se puede cruzar)
  - conectar/desconectar pantallas recoloca las ventanas huérfanas
- [x] Escritorios virtuales
  - 4 por defecto; hereda número y escritorio actual de xfwm4 al reemplazarlo
  - Super+1…9 / Ctrl+Alt+←→ para cambiar; Super+Shift+1…9 envía la ventana;
    Ctrl+Alt+Shift+←→ la lleva y la sigue
  - el panel/paginador y Dock-e pueden cambiar de escritorio y activar
    ventanas de otros escritorios (`_NET_CURRENT_DESKTOP`, `_NET_ACTIVE_WINDOW`)
  - ventanas fijas (sticky), diálogos en el escritorio de su madre
  - cambiar el número de escritorios recoloca las ventanas huérfanas
  - Alt+Tab solo muestra el escritorio actual (como Dock-e: current-workspace-only)
- [x] `WM_NORMAL_HINTS`: mínimo/máximo, incrementos de terminal al redimensionar,
      colocación respetando USPosition/PPosition; ventanas de tamaño fijo no
      se maximizan ni ajustan
- [x] `WM_HINTS`: apps sin entrada de teclado, arranque minimizado, urgencia
- [x] Capas: encima (Super+T) / debajo; `SKIP_TASKBAR` fuera de Alt+Tab
- [x] Diálogos modales: activar la madre enfoca el modal
- [x] Foco sin robos: `_NET_WM_USER_TIME` (y su ventana auxiliar de GTK); una
      app que se abre o se activa sola mientras escribes en otra queda debajo
      pidiendo atención; Dock-e y el paginador siempre pueden activar
- [x] Urgencia (`DEMANDS_ATTENTION`): se activa por WM_HINTS o robo evitado y se
      limpia al enfocar — Dock-e la usa para hacer rebotar el icono
- [ ] Sesión: arrancar Fenster en lugar de xfwm4 de forma opcional (pendiente
      de probarlo en la sesión real; ver README)

### Fase 3 — Estilo
- [x] Alt+Tab propio al estilo macOS con la estética de Dock-e
  - una entrada por aplicación (ventana más reciente), punto bajo las apps
    con varias ventanas, Alt+` recorre las ventanas de la app activa
  - panel negro sólido, radio 18, iconos de 64 px que encogen si no caben,
    pastilla gris al 16 % con radio 12 — los mismos valores que el gtk.css
    aplicado a xfwm4
  - aparece tras 120 ms (un Alt+Tab rápido no parpadea); Esc cancela,
    ←/→ y Shift+Tab navegan, soltar Alt confirma
  - ventana ARGB propia dibujada con cairo, sin GTK (sigue siendo ligero)
- [x] Iconos sin GTK: `_NET_WM_ICON` o, si falta, el `.desktop` según WM_CLASS
      y el tema de iconos de XFCE (spec freedesktop); se asigna a la ventana,
      así que **sustituye a `wm-icon-fixer`**
- [x] Marcas `_FENSTER_ANIM` (desk-next / desk-prev / minimize) para que picom
      sepa qué animación usar al mostrar u ocultar
- [x] `data/picom/fenster.conf` con animaciones y reglas para picom v12
- [ ] Compilar picom v12 (`scripts/build-picom.sh`, necesita `sudo apt install`)
      y ajustar el borrador de animaciones con picom real
- [x] Vista previa del ajuste al arrastrar a un borde: rectángulo negro
      translúcido (40 %) con borde blanco sutil y radio 12, justo debajo de la
      ventana que se arrastra; desaparece al alejarse del borde

### Fase 4 — Extras
- [x] Cuartos de pantalla: arrastrando a las esquinas (franja de 80 px) y con
      Super+↑/↓ desde una mitad (mitad → cuarto → maximizar / restaurar)
- [x] Animación de minimizar/restaurar en el sitio (encoger al 90 %, bajar 16 px
      y desvanecer en 220 ms), animada por Fenster con XRender: funciona con
      picom v10. (Se probó hacia el icono de Dock-e y se descartó: con el dock
      oculto el destino no se ve.)
- [x] Reglas por aplicación en `~/.config/fenster/fenster.conf` (escritorio,
      monitor, tamaño, posición, estado, encima, Alt+Tab, foco); se recarga sola
- [x] Redimensionado enlazado: las ventanas pegadas comparten el borde al
      cambiar de tamaño (vecinas y hermanas alineadas, respetando mínimos)
- [ ] Vista general de ventanas (tipo Mission Control)
- [ ] Barra de título mínima opcional para apps sin CSD
