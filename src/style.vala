/* Tokens de estilo y movimiento, tomados del tema "Navbar" de Dock-e
 * (~/.local/share/plank/themes/Navbar/dock.theme) para que Fenster
 * se sienta parte del mismo sistema. Las animaciones las ejecuta picom v12
 * (ver data/picom/fenster.conf); estos valores son la fuente de verdad. */
namespace Fenster.Style {
    /* Superficies */
    public const string SURFACE = "#000000";
    public const string SURFACE_HOVER = "rgba(255,255,255,0.16)";
    public const string TEXT = "#f2f2f2";
    public const int CORNER_RADIUS = 12;   /* TopRoundness / BottomRoundness */
    public const int STROKE_WIDTH = 0;     /* LineWidth */

    /* Duraciones (ms) */
    public const int OPEN_MS = 230;        /* ItemMoveTime */
    public const int CLOSE_MS = 120;       /* HideTime */
    public const int MINIMIZE_MS = 300;    /* SlideTime */

    /* Transición de geometría (maximizar, ajustar, cambiar de monitor) */
    public const int MORPH_MS = 200;
    public const int MORPH_FADE_MS = 90;      /* fundido cruzado al terminar */

    /* Minimizar/restaurar en el sitio: encoger, bajar y desvanecer */
    public const int MINIMIZE_ANIM_MS = 220;
    public const double MINIMIZE_SCALE = 0.90;
    public const int MINIMIZE_DROP = 16;      /* px */
    public const int GEOMETRY_MS = 300;    /* ActiveTime */
    public const int SWITCHER_MS = 120;    /* HideTime */

    /* Escala inicial/final al abrir y cerrar */
    public const double OPEN_SCALE = 0.95;

    /* Alt+Tab: mismos valores que el estilo aplicado a xfwm4 (gtk.css) */
    public const int SWITCHER_RADIUS = 18;     /* panel */
    public const int SWITCHER_PADDING = 14;
    public const int SWITCHER_ICON = 64;
    public const int SWITCHER_ICON_MIN = 32;
    public const int SWITCHER_CELL_PADDING = 10;
    public const int SWITCHER_CELL_RADIUS = 12; /* pastilla de selección = Dock-e */
    public const int SWITCHER_CELL_GAP = 6;
    public const double SWITCHER_SELECTED_ALPHA = 0.16;
    public const int SWITCHER_DELAY_MS = 120;  /* no parpadea con Alt+Tab rápido */
    public const int SWITCHER_APPEAR_MS = 120; /* HideTime de Dock-e */
    public const double SWITCHER_APPEAR_SCALE = 0.97;
    public const int SWITCHER_PILL_MS = 90;

    /* Vista previa del ajuste al arrastrar a un borde */
    public const int SNAP_PREVIEW_INSET = 8;
    public const double SNAP_PREVIEW_ALPHA = 0.40;
    public const double SNAP_PREVIEW_STROKE_ALPHA = 0.25;
    public const int SNAP_PREVIEW_MS = 150;       /* aparecer / cambiar de zona */
    public const int SNAP_PREVIEW_FADE_MS = 100;  /* desaparecer */

    /* Barra de título propia (apps sin decoración) */
    public const int TITLEBAR_HEIGHT = 28;
    public const double TITLEBAR_DOT_R = 6;
    public const int TITLEBAR_DOT_X = 16;       /* centro del primer punto */
    public const int TITLEBAR_DOT_GAP = 20;     /* entre centros */
    public const int TITLEBAR_DOUBLE_CLICK_MS = 400;

    /* Separación entre ventanas al ajustarlas a mitades/cuartos (px) */
    public const int SNAP_GAP = 0;
}
