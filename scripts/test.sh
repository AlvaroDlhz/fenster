#!/usr/bin/env bash
# Pruebas automáticas de Fenster en pantallas virtuales (no se ve nada en la
# sesión real): Xvfb invisible → Xephyr anidado con 2 monitores (Xinerama).
# Simula teclado y ratón con XTest (scripts/fake-input.py).
set -uo pipefail
cd "$(dirname "$0")/.."
make -s || exit 1

HOST=:97
DISP=:98
LOG="${TMPDIR:-/tmp}/fenster-test.log"
FI=scripts/fake-input.py
PASS=0
FAIL=0

Xvfb $HOST -screen 0 2600x900x24 >/dev/null 2>&1 & XVFB=$!
sleep 1
DISPLAY=$HOST Xephyr $DISP -screen 1280x800 -screen 1280x800 +xinerama \
    +extension XTEST -ac >/dev/null 2>&1 & XEPHYR=$!
sleep 1.5
export DISPLAY=$DISP

cleanup() { kill $FENSTER $XEPHYR $XVFB 2>/dev/null; wait 2>/dev/null; }
trap cleanup EXIT

# Configuración de prueba (reglas por aplicación)
CONF="${TMPDIR:-/tmp}/fenster-test.conf"
cat >"$CONF" <<'CONFEOF'
[General]
escritorios = 4

[Regla centrada en el monitor 2]
titulo = ^prueba-plain-regla$
monitor = 2
tamaño = 50%x50%
encima = true
en-alt-tab = false

[Regla mitad derecha]
titulo = ^prueba-plain-derecha$
estado = derecha
CONFEOF

G_MESSAGES_DEBUG=Fenster ./build/fenster --config "$CONF" >"$LOG" 2>&1 & FENSTER=$!
sleep 0.8

geo() {
    xwininfo -id "$1" | awk '/Absolute upper-left X/{x=$NF} /Absolute upper-left Y/{y=$NF}
                             /Width/{w=$NF} /Height/{h=$NF} END{print x","y" "w"x"h}'
}
active() { xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}'; }
newest() { wmctrl -l | tail -1 | cut -d' ' -f1; }
check() {  # check "descripción" "esperado" "obtenido"
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ✔ $1"
    else FAIL=$((FAIL+1)); echo "  ✘ $1 — esperado [$2], obtenido [$3]"; fi
}
norm() { printf '0x%x' "$1"; }

echo "== Monitores"
check "detecta 2 monitores" "1" "$(grep -c 'activo: pantalla 2560x800, 2 monitor(es)' "$LOG")"
check "ignora avisos de pantalla sin cambios" "0" "$(grep -c 'Cambio de pantallas' "$LOG")"

echo "== Colocación según el puntero"
$FI move 300 300
xterm -geometry 80x24 & sleep 0.8; A=$(newest)
$FI move 1900 300
xterm -geometry 80x24 & sleep 0.8; B=$(newest)
check "A centrada en el monitor izquierdo" "398,242 484x316" "$(geo "$A")"
check "B centrada en el monitor derecho" "1678,242 484x316" "$(geo "$B")"

echo "== Strut (dock) solo en el monitor izquierdo"
xprop -id "$A" -f _NET_WM_STRUT_PARTIAL 32c -set _NET_WM_STRUT_PARTIAL \
    "0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 1279"
sleep 0.3
wmctrl -i -a "$A"; sleep 0.2
$FI key super+Up; sleep 0.2
check "Super+↑ maximiza en el izquierdo, respetando el dock" "0,0 1280x760" "$(geo "$A")"

echo "== Saltos entre monitores"
$FI key super+shift+Right; sleep 0.2
check "Super+Shift+→ lleva la ventana maximizada al derecho" "1280,0 1280x800" "$(geo "$A")"
$FI key super+Down; sleep 0.2
# y proporcional: 242 de (760-316) en el izquierdo → 263 de (800-316) en el derecho
check "Super+↓ restaura en el monitor nuevo (posición proporcional)" "1678,263 484x316" "$(geo "$A")"
$FI key super+Left; sleep 0.2
check "Super+← ajusta a la mitad izquierda del derecho" "1280,0 640x800" "$(geo "$A")"
$FI key super+Left; sleep 0.2
check "Super+← otra vez salta a la mitad derecha del izquierdo" "640,0 640x760" "$(geo "$A")"

echo "== Alt+Tab (una entrada por aplicación, como macOS)"
TC=scripts/test-client.py
by_title() { wmctrl -l | awk -v t="$1" '$0 ~ t {print $1; exit}'; }
switcher_win() { xwininfo -root -tree | awk '/"fenster-switcher"/{print $1; exit}'; }
$TC & sleep 1.2; G=$(by_title "prueba-$")
wmctrl -i -a "$G"; sleep 0.2; wmctrl -i -a "$A"; sleep 0.2
$FI hold alt; $FI key Tab; $FI release alt; sleep 0.2
check "Alt+Tab vuelve a la app anterior" "$(norm "$G")" "$(norm "$(active)")"
$FI hold alt; $FI key Tab; $FI release alt; sleep 0.2
check "Alt+Tab de nuevo regresa" "$(norm "$A")" "$(norm "$(active)")"
$FI hold alt; $FI key Tab; sleep 0.4
SW=$(switcher_win)
check "mantener Alt muestra el panel" "IsViewable" "$(xwininfo -id "$SW" | awk '/Map State/{print $NF}')"
check "panel: esquina transparente (radio 18)" "00000000" "$(scripts/fake-input.py pixel "$SW" 1 1)"
check "panel: fondo negro sólido (Dock-e)" "ff000000" "$(scripts/fake-input.py pixel "$SW" 8 50)"
# 16 % de blanco sobre el negro del panel = 0x28
check "panel: pastilla gris translúcida en la app elegida" "ff282828" "$(scripts/fake-input.py pixel "$SW" 128 16)"
# 2·14 (margen) + 2·84 (celdas) + 6 (separación) = 202
check "una entrada por app (XTerm ×2 + GTK = 2 iconos)" "202x112" \
    "$(xwininfo -id "$SW" | awk '/Width/{w=$NF} /Height/{h=$NF} END{print w"x"h}')"
$FI key Escape; $FI release alt; sleep 0.2
check "Esc cancela sin cambiar de ventana" "$(norm "$A")" "$(norm "$(active)")"
check "y oculta el panel" "IsUnMapped" "$(xwininfo -id "$SW" | awk '/Map State/{print $NF}')"
wmctrl -i -a "$B"; sleep 0.2; wmctrl -i -a "$A"; sleep 0.2
$FI key alt+grave; sleep 0.2
check "Alt+\` cambia entre ventanas de la misma app" "$(norm "$B")" "$(norm "$(active)")"
$FI key alt+grave; sleep 0.2
check "Alt+\` otra vez vuelve" "$(norm "$A")" "$(norm "$(active)")"
wmctrl -i -c "$G"; sleep 0.3

echo "== Iconos (integra wm-icon-fixer)"
$TC noicon & sleep 1.2; NI=$(by_title "prueba-noicon")
check "una app sin icono propio recibe el de su .desktop" "1" \
    "$(xprop -id "$NI" _NET_WM_ICON | head -1 | grep -c 'Icon (64 x 64)')"
wmctrl -i -c "$NI"; sleep 0.3

echo "== Ratón"
wmctrl -i -a "$B"; sleep 0.2
$FI move 1900 400; $FI hold alt; $FI down 1
$FI move 1800 350; $FI move 1700 300
$FI up 1; $FI release alt; sleep 0.2
check "Alt+arrastrar mueve la ventana" "1478,142 484x316" "$(geo "$B")"
$FI move 1700 300; $FI hold alt; $FI down 1
$FI move 1280 300; $FI move 1279 300
$FI up 1; $FI release alt; sleep 0.2
check "Cruzar el borde compartido no ajusta" "316x484" \
    "$(geo "$B" | awk '{split($2,a,"x"); print a[2]"x"a[1]}')"
$FI move 1279 300; $FI hold alt; $FI down 1
$FI move 600 300; $FI move 0 300
$FI up 1; $FI release alt; sleep 0.2
check "Soltar en el borde exterior izquierdo ajusta a la mitad" "0,0 640x760" "$(geo "$B")"
$FI move 300 300; $FI hold alt; $FI down 1; $FI move 640 400
$FI up 1; $FI release alt; sleep 0.2
check "Arrastrar una ventana ajustada recupera su tamaño" "484x316" "$(geo "$B" | cut -d' ' -f2)"

echo "== Vista previa del ajuste y cuartos"
preview_win() { xwininfo -root -tree | awk '/"fenster-snap-preview"/{print $1; exit}'; }
mapstate() {  # sin id, xwininfo esperaría un clic: devolver algo y seguir
    [ -n "$1" ] || { echo "(sin ventana)"; return; }
    xwininfo -id "$1" | awk '/Map State/{print $NF}'
}
just_below() {  # ¿$1 está inmediatamente debajo de $2? (xwininfo lista de arriba abajo)
    local prev="" w
    for w in $(xwininfo -root -children | grep -o '^ *0x[0-9a-f]*'); do
        [ "$(norm "$prev")" = "$(norm "$2")" ] && { [ "$(norm "$w")" = "$(norm "$1")" ] && echo 1 || echo 0; return; }
        prev=$w
    done
    echo 0
}
read -r bx by _ _ <<<"$(geo "$B" | tr ',x' '  ')"
$FI move $((bx + 40)) $((by + 40)); $FI hold alt; $FI down 1
$FI move 300 300; $FI move 0 300
PV=$(preview_win)
check "arrastrar al borde muestra la vista previa" "IsViewable" "$(mapstate "$PV")"
check "con WM_CLASS completo para las reglas de picom" 'WM_CLASS(STRING) = "fenster-snap-preview", "Fenster"' "$(xprop -id "$PV" WM_CLASS)"
# mitad izquierda del monitor izquierdo (área 1280x760 por el dock) con margen de 8
check "con la geometría de la mitad izquierda" "8,8 624x744" "$(geo "$PV")"
check "justo debajo de la ventana arrastrada" "1" "$(just_below "$PV" "$B")"
$FI move 0 750
check "en la esquina la vista previa pasa a un cuarto" "8,388 624x364" "$(geo "$PV")"
$FI move 400 400
check "lejos de los bordes desaparece" "IsUnMapped" "$(mapstate "$PV")"
$FI move 0 750
$FI up 1; $FI release alt; sleep 0.2
check "soltar en la esquina ajusta al cuarto inferior izquierdo" "0,380 640x380" "$(geo "$B")"
check "y oculta la vista previa" "IsUnMapped" "$(mapstate "$PV")"
wmctrl -i -a "$B"; sleep 0.2
$FI key super+Left; sleep 0.2
check "Super+← lleva a la mitad izquierda" "0,0 640x760" "$(geo "$B")"
$FI key super+Up; sleep 0.2
check "Super+↑ desde la mitad → cuarto superior" "0,0 640x380" "$(geo "$B")"
$FI key super+Up; sleep 0.2
check "Super+↑ desde el cuarto → maximizar" "0,0 1280x760" "$(geo "$B")"
$FI key super+Down; sleep 0.2
check "Super+↓ restaura el tamaño original" "484x316" "$(geo "$B" | cut -d' ' -f2)"
$FI key super+Right; $FI key super+Down; sleep 0.2
check "Super+→ y Super+↓ → cuarto inferior derecho" "640,380 640x380" "$(geo "$B")"
$FI key super+Down; sleep 0.2
check "Super+↓ desde el cuarto inferior restaura" "484x316" "$(geo "$B" | cut -d' ' -f2)"

echo "== Quitar el dock libera el área"
xprop -id "$A" -remove _NET_WM_STRUT_PARTIAL; sleep 0.3
wmctrl -i -a "$B"; sleep 0.2; $FI key super+Up; sleep 0.2
check "Maximizar ocupa todo el monitor izquierdo" "0,0 1280x800" "$(geo "$B")"

echo "== Escritorios virtuales"
mapped() { mapstate "$1"; }
cur() { xprop -root _NET_CURRENT_DESKTOP | awk '{print $NF}'; }
desk() { xprop -id "$1" _NET_WM_DESKTOP | awk '{print $NF}'; }
state() { xprop -id "$1" _NET_WM_STATE; }
stack_index() {  # posición (1 = abajo) de una ventana en _NET_CLIENT_LIST_STACKING
    local i=0 w want; want=$(norm "$1")
    for w in $(xprop -root _NET_CLIENT_LIST_STACKING | cut -d'#' -f2 | tr ',' ' '); do
        i=$((i+1)); [ "$(norm "$w")" = "$want" ] && { echo $i; return; }
    done
}

check "4 escritorios por defecto" "4" "$(xprop -root _NET_NUMBER_OF_DESKTOPS | awk '{print $NF}')"
wmctrl -i -a "$A"; sleep 0.2
$FI key super+2
check "marca la animación de escritorio para picom" '_FENSTER_ANIM(STRING) = "desk-next"' "$(xprop -id "$A" _FENSTER_ANIM)"
sleep 0.6
check "y la borra al terminar" "0" "$(xprop -id "$A" _FENSTER_ANIM | grep -c STRING)"
check "Super+2 cambia al escritorio 2" "1" "$(cur)"
check "las ventanas del escritorio 1 se ocultan" "IsUnMapped" "$(mapped "$A")"
xterm & sleep 0.8; C=$(newest)
check "una ventana nueva va al escritorio actual" "1" "$(desk "$C")"
check "y recibe el foco" "$(norm "$C")" "$(norm "$(active)")"
$FI key ctrl+alt+Left; sleep 0.2
check "Ctrl+Alt+← vuelve al escritorio 1" "0" "$(cur)"
check "reaparecen sus ventanas" "IsViewable" "$(mapped "$A")"
check "y se ocultan las del 2" "IsUnMapped" "$(mapped "$C")"
wmctrl -i -a "$C"; sleep 0.3
check "activar una ventana de otro escritorio (Dock-e) lleva a él" "1" "$(cur)"
$FI key super+shift+3; sleep 0.2
check "Super+Shift+3 envía la ventana al escritorio 3" "2" "$(desk "$C")"
check "sin cambiar de escritorio" "1" "$(cur)"
check "y la oculta" "IsUnMapped" "$(mapped "$C")"
$FI key super+1; sleep 0.2; wmctrl -i -a "$A"; sleep 0.2
$FI key ctrl+alt+shift+Right; sleep 0.3
check "Ctrl+Alt+Shift+→ lleva la ventana y la sigue" "1 1 $(norm "$A")" "$(desk "$A") $(cur) $(norm "$(active)")"
wmctrl -s 0; sleep 0.2
check "el panel/paginador puede cambiar de escritorio" "0" "$(cur)"
wmctrl -i -r "$B" -b add,sticky; sleep 0.2; $FI key super+3; sleep 0.2
check "una ventana fija (sticky) se ve en todos" "IsViewable 4294967295" "$(mapped "$B") $(desk "$B")"
wmctrl -n 2; sleep 0.3
check "reducir a 2 escritorios mueve las ventanas del 3 al 2" "2 1 1" \
    "$(xprop -root _NET_NUMBER_OF_DESKTOPS | awk '{print $NF}') $(desk "$C") $(cur)"
wmctrl -n 4; wmctrl -s 0; sleep 0.2
wmctrl -i -r "$A" -t 0; wmctrl -i -r "$B" -b remove,sticky; wmctrl -i -r "$B" -t 0; sleep 0.3

echo "== Capas"
wmctrl -i -a "$A"; sleep 0.2
$FI key super+t; sleep 0.2
check "Super+T marca la ventana como siempre encima" "1" "$(state "$A" | grep -c ABOVE)"
wmctrl -i -a "$B"; sleep 0.2
check "activar otra ventana no la tapa" "1" \
    "$([ "$(stack_index "$A")" -gt "$(stack_index "$B")" ] && echo 1 || echo 0)"
wmctrl -i -a "$A"; $FI key super+t; sleep 0.2
check "Super+T de nuevo lo desactiva" "0" "$(state "$A" | grep -c ABOVE)"

echo "== Pistas de tamaño"
$FI move 300 300
xterm -geometry 60x15 & sleep 0.8; D=$(newest)
inc=$(xprop -id "$D" WM_NORMAL_HINTS | awk '/resize increment/{print $(NF-2)}')
base=$(xprop -id "$D" WM_NORMAL_HINTS | awk '/base size/{print $(NF-2)}')
read -r dx dy dw dh <<<"$(geo "$D" | tr ',x' '  ')"
$FI move $((dx + dw - 5)) $((dy + dh - 5)); $FI hold alt; $FI down 3
$FI move $((dx + dw + 30)) $((dy + dh + 20)); $FI move $((dx + dw + 37)) $((dy + dh + 23))
$FI up 3; $FI release alt; sleep 0.2
nw=$(geo "$D" | awk '{split($2,a,"x"); print a[1]}')
check "redimensionar una terminal respeta sus incrementos (${inc}px)" "0" "$(( (nw - base) % inc ))"
check "y la ha agrandado" "1" "$([ "$nw" -gt "$dw" ] && echo 1 || echo 0)"
$TC fixed & sleep 1.2; FX=$(by_title prueba-fixed)
before=$(geo "$FX" | cut -d' ' -f2)
$FI key super+Up; sleep 0.2
check "una ventana de tamaño fijo no se maximiza" "$before" "$(geo "$FX" | cut -d' ' -f2)"
wmctrl -i -c "$FX"; wmctrl -i -c "$D"; sleep 0.3

echo "== Foco"
wmctrl -i -a "$A"; sleep 0.2
$TC nofocus & sleep 1.2; NF=$(by_title prueba-nofocus)
check "una app que pide no enfocar no roba el foco" "$(norm "$A")" "$(norm "$(active)")"
check "y queda marcada pidiendo atención" "1" "$(state "$NF" | grep -c DEMANDS_ATTENTION)"
wmctrl -i -a "$NF"; sleep 0.2
check "al activarla se limpia la atención" "0" "$(state "$NF" | grep -c DEMANDS_ATTENTION)"
wmctrl -i -c "$NF"
$TC modal & sleep 1.5; MP=$(by_title prueba-modal); MD=$(by_title prueba-dialogo)
check "el diálogo modal recibe el foco" "$(norm "$MD")" "$(norm "$(active)")"
wmctrl -i -a "$A"; sleep 0.2; wmctrl -i -a "$MP"; sleep 0.2
check "activar la madre de un modal enfoca el modal" "$(norm "$MD")" "$(norm "$(active)")"
check "y el diálogo queda en su mismo escritorio" "$(desk "$MP")" "$(desk "$MD")"
wmctrl -i -c "$MD"; wmctrl -i -c "$MP"
$TC urgent & sleep 0.6; UR=$(by_title prueba-urgent)
wmctrl -i -a "$A"; sleep 1.2
check "WM_HINTS urgente → pide atención" "1" "$(state "$UR" | grep -c DEMANDS_ATTENTION)"
wmctrl -i -a "$UR"; sleep 0.2
check "enfocarla limpia la urgencia" "0" "$(state "$UR" | grep -c DEMANDS_ATTENTION)"
wmctrl -i -c "$UR"; sleep 0.3

echo "== Minimizar en el sitio (encoger, bajar y desvanecer)"
anim_win() { xwininfo -root -tree | awk '/"fenster-minimize"/{print $1; exit}'; }
wmctrl -i -a "$A"; sleep 0.3
wmctrl -i -r "$A" -b add,hidden; sleep 0.1
AW=$(anim_win)
check "minimizar muestra la animación" "IsViewable" "$(mapstate "$AW")"
check "y la ventana real ya está oculta" "IsUnMapped" "$(mapstate "$A")"
read -r ax ay aw ah <<<"$(geo "$AW" | tr ',x' '  ')"
check "la animación ocupa la ventana más su descenso de 16 px" "$(geo "$A" | awk '{split($2,s,"x"); print s[1]"x"s[2]+16}')" "${aw}x${ah}"
sleep 0.5
check "la animación termina y se retira" "" "$(anim_win)"
check "la ventana queda minimizada" "1" "$(state "$A" | grep -c HIDDEN)"
wmctrl -i -a "$A"; sleep 0.1
check "restaurar también anima" "IsViewable" "$(mapstate "$(anim_win)")"
check "con la ventana aún oculta durante la animación" "IsUnMapped" "$(mapstate "$A")"
sleep 0.5
check "al terminar aparece la ventana real" "IsViewable" "$(mapstate "$A")"
check "y la captura se retira en cuanto la ventana está pintada (DAMAGE)" "" "$(anim_win)"
check "y recibe el foco" "$(norm "$A")" "$(norm "$(active)")"
xterm & sleep 0.8; E=$(newest)   # ventana sin ajustar: Super+↓ minimiza
FI_SLEEP=0 $FI key super+Down; sleep 0.05
check "Super+↓ también minimiza con animación" "IsViewable" "$(mapstate "$(anim_win)")"
sleep 0.5; wmctrl -i -c "$E"; sleep 0.3

echo "== Reglas por aplicación (~/.config/fenster/fenster.conf)"
$FI move 300 300
$TC plain-regla 2>/dev/null & sleep 1.2; R1=$(by_title "prueba-plain-regla")
check "monitor y tamaño de la regla (50 % centrado en el monitor 2)" "1600,200 640x400" "$(geo "$R1")"
check "siempre encima por regla" "1" "$(state "$R1" | grep -c ABOVE)"
check "fuera del Alt+Tab por regla" "1" "$(state "$R1" | grep -c SKIP_TASKBAR)"
$TC plain-derecha 2>/dev/null & sleep 1.2; R2=$(by_title "prueba-plain-derecha")
check "estado inicial de la regla (mitad derecha)" "640,0 640x800" "$(geo "$R2")"
cat >>"$CONF" <<'CONFEOF'

[Regla recarga]
titulo = ^prueba-plain-recarga$
estado = maximizada
CONFEOF
sleep 1
$TC plain-recarga 2>/dev/null & sleep 1.2; R3=$(by_title "prueba-plain-recarga")
check "el archivo se recarga solo al guardarlo" "1" "$(state "$R3" | grep -c MAXIMIZED_VERT)"
wmctrl -i -c "$R1"; wmctrl -i -c "$R2"; wmctrl -i -c "$R3"; sleep 0.3

echo "== Redimensionado enlazado"
rdrag() {  # rdrag X0 Y0 X1 Y1: Alt+clic derecho arrastrando (redimensionar)
    $FI move "$1" "$2"; $FI hold alt; $FI down 3
    $FI move $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 )); $FI move "$3" "$4"
    $FI up 3; $FI release alt; sleep 0.2
}
wmctrl -s 3; sleep 0.3   # escritorio vacío
$FI move 300 300
xterm & sleep 0.8; P=$(newest); $FI key super+Left; sleep 0.2
xterm & sleep 0.8; Q=$(newest); $FI key super+Right; sleep 0.2
rdrag 630 700 730 700
check "dos mitades: la de la izquierda crece" "0,0 740x800" "$(geo "$P")"
check "y la de la derecha encoge sin dejar hueco" "740,0 540x800" "$(geo "$Q")"
wmctrl -i -a "$P"; $FI key super+Left; sleep 0.2
wmctrl -i -a "$Q"; $FI key super+Right; $FI key super+Up; sleep 0.2
xterm & sleep 0.8; R=$(newest); $FI key super+Right; $FI key super+Down; sleep 0.2
rdrag 630 600 580 600
check "mitad frente a dos cuartos: la mitad encoge" "0,0 590x800" "$(geo "$P")"
check "el cuarto superior sigue al borde" "590,0 690x400" "$(geo "$Q")"
check "y el inferior también" "590,400 690x400" "$(geo "$R")"
rdrag 610 30 640 30
check "desde el otro lado: la vecina sigue" "0,0 620x800" "$(geo "$P")"
check "y la hermana alineada también" "620,400 660x400" "$(geo "$R")"
rdrag 1200 390 1200 490
check "borde horizontal entre cuartos: el de arriba crece" "620,0 660x500" "$(geo "$Q")"
check "y el de abajo encoge" "620,500 660x300" "$(geo "$R")"
rdrag 600 700 3000 700
check "nadie baja de su tamaño mínimo (64 px)" "1216 64 64" \
    "$(geo "$P" | awk '{split($2,a,"x"); print a[1]}') $(geo "$Q" | awk '{split($2,a,"x"); print a[1]}') $(geo "$R" | awk '{split($2,a,"x"); print a[1]}')"
wmctrl -i -c "$P"; wmctrl -i -c "$Q"; wmctrl -i -c "$R"; sleep 0.3; wmctrl -s 0

echo
echo "Resultado: $PASS correctas, $FAIL fallidas   (registro: $LOG)"
[ "$FAIL" -eq 0 ]
