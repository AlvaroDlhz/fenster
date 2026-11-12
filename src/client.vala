namespace Fenster {
    public enum ClientKind {
        NORMAL,
        DIALOG,
        UTILITY,
        SPLASH,
        DOCK,
        DESKTOP;

        /* Docks y escritorio no reciben foco ni entran en Alt+Tab. */
        public bool is_chrome () {
            return this == DOCK || this == DESKTOP;
        }
    }

    public struct Rect {
        public int x;
        public int y;
        public int w;
        public int h;

        public Rect (int x, int y, int w, int h) {
            this.x = x; this.y = y; this.w = w; this.h = h;
        }

        public bool contains (int px, int py) {
            return px >= x && px < x + w && py >= y && py < y + h;
        }

        public bool intersects (Rect o) {
            return x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
        }

        /* Distancia² de un punto al rectángulo (0 si está dentro). */
        public long distance2 (int px, int py) {
            long dx = px < x ? x - px : (px >= x + w ? px - (x + w - 1) : 0);
            long dy = py < y ? y - py : (py >= y + h ? py - (y + h - 1) : 0);
            return dx * dx + dy * dy;
        }
    }

    /* Área útil mínima aceptable tras aplicar struts. */
    public const int MIN_WORK = 100;

    /* _NET_WM_DESKTOP para ventanas visibles en todos los escritorios. */
    public const uint ALL_DESKTOPS = uint.MAX;

    /* Capas de apilado (abajo → arriba). */
    public enum Layer {
        DESKTOP,
        BELOW,
        NORMAL,
        ABOVE,
        DOCK,
        FULLSCREEN
    }

    /* WM_NORMAL_HINTS (ICCCM 4.1.2.3) ya interpretadas. */
    public struct SizeHints {
        public bool user_position;   /* USPosition | PPosition */
        public int min_w;
        public int min_h;
        public int max_w;            /* 0 = sin límite */
        public int max_h;
        public int inc_w;
        public int inc_h;
        public int base_w;
        public int base_h;

        public static SizeHints parse (long[] d) {
            var h = SizeHints () { min_w = 1, min_h = 1, inc_w = 1, inc_h = 1 };
            if (d.length < 15) {
                return h;
            }
            long f = d[0];
            h.user_position = (f & (1 | 4)) != 0;
            bool has_base = (f & 256) != 0 && d.length >= 17;
            if ((f & 16) != 0) {            /* PMinSize */
                h.min_w = (int) long.max (1, d[5]);
                h.min_h = (int) long.max (1, d[6]);
            } else if (has_base) {           /* ICCCM: base hace de mínimo */
                h.min_w = (int) long.max (1, d[15]);
                h.min_h = (int) long.max (1, d[16]);
            }
            if ((f & 32) != 0) {            /* PMaxSize */
                h.max_w = (int) long.max (0, d[7]);
                h.max_h = (int) long.max (0, d[8]);
            }
            if ((f & 64) != 0) {            /* PResizeInc */
                h.inc_w = (int) long.max (1, d[9]);
                h.inc_h = (int) long.max (1, d[10]);
            }
            if (has_base) {
                h.base_w = (int) long.max (0, d[15]);
                h.base_h = (int) long.max (0, d[16]);
            } else if ((f & 16) != 0) {     /* ICCCM: mínimo hace de base */
                h.base_w = h.min_w;
                h.base_h = h.min_h;
            }
            return h;
        }

        public bool fixed () {
            return max_w > 0 && max_h > 0 && max_w == min_w && max_h == min_h;
        }

        /* Ajusta un tamaño a los límites. Los incrementos (terminales) solo se
         * aplican al redimensionar a mano, no al maximizar o ajustar. */
        public void constrain (ref int w, ref int h, bool use_inc) {
            if (use_inc && (inc_w > 1 || inc_h > 1)) {
                w = base_w + ((w - base_w) / inc_w) * inc_w;
                h = base_h + ((h - base_h) / inc_h) * inc_h;
            }
            w = int.max (w, min_w);
            h = int.max (h, min_h);
            if (max_w > 0) w = int.min (w, max_w);
            if (max_h > 0) h = int.min (h, max_h);
        }
    }

    /* WM_HINTS (ICCCM 4.1.2.4) ya interpretadas. */
    public struct WmHints {
        public bool accepts_input;
        public bool start_iconic;
        public bool urgent;

        public static WmHints parse (long[] d) {
            var h = WmHints () { accepts_input = true };
            if (d.length < 3) {
                return h;
            }
            long f = d[0];
            if ((f & 1) != 0) h.accepts_input = d[1] != 0;        /* InputHint */
            if ((f & 2) != 0) h.start_iconic = d[2] == 3;         /* StateHint = Iconic */
            h.urgent = (f & 256) != 0;                            /* XUrgencyHint */
            return h;
        }
    }

    /* Una ventana de nivel superior gestionada por Fenster. */
    public class Client {
        public X.Window win;
        public ClientKind kind = ClientKind.NORMAL;
        public X.Window transient_for = 0;

        public Rect geom;
        /* Geometría antes de maximizar, ajustar o pantalla completa. */
        public Rect restore;
        public bool has_restore = false;

        public bool fullscreen = false;
        public bool maximized = false;
        public bool snapped = false;
        public SnapZone snap_zone = SnapZone.NONE;  /* mitad o cuarto actual */
        public bool minimized = false;

        /* Escritorios virtuales */
        public uint desktop = 0;
        public bool hidden_by_desktop = false;

        /* Capas y marcas EWMH */
        public bool above = false;
        public bool below = false;
        public bool skip_taskbar = false;
        public bool skip_pager = false;
        public bool modal = false;
        public bool urgent = false;          /* _NET_WM_STATE_DEMANDS_ATTENTION */

        public SizeHints hints = SizeHints () { min_w = 1, min_h = 1, inc_w = 1, inc_h = 1 };
        public bool accepts_input = true;    /* WM_HINTS.input */

        /* WM_CLASS e icono (cacheado para Alt+Tab) */
        public string wm_instance = "";
        public string wm_class = "";
        public Cairo.ImageSurface? icon = null;
        public bool icon_loaded = false;

        /* Clave de agrupación por aplicación (Alt+Tab estilo macOS) */
        public string app_key () {
            if (wm_class != "") return wm_class.down ();
            if (wm_instance != "") return wm_instance.down ();
            return "win-%lx".printf ((ulong) win);
        }

        /* Minimizar hacia Dock-e: captura reducida y animación en curso */
        public Cairo.ImageSurface? mini_snapshot = null;
        public Rect mini_rect;
        public MinimizeAnimation? anim = null;
        public ulong paint_damage = 0;   /* DAMAGE: esperando a que se pinte */

        /* Prevención de robo de foco (_NET_WM_USER_TIME) */
        public X.Window user_time_win = 0;
        public ulong user_time = 0;
        public bool has_user_time = false;

        /* Unmaps que provocamos nosotros (minimizar) y no deben "desgestionar". */
        public int ignore_unmaps = 0;

        public bool supports_delete = false;
        public bool supports_take_focus = false;

        /* _NET_WM_STRUT_PARTIAL: izq, der, arr, aba y sus rangos (12 valores) */
        public long strut[12];

        /* _GTK_FRAME_EXTENTS: margen de sombra de las apps con CSD */
        public long csd[4];

        public Client (X.Window win) {
            this.win = win;
        }

        public bool can_focus () {
            return !kind.is_chrome () && !minimized && !hidden_by_desktop
                && (accepts_input || supports_take_focus);
        }

        public bool on_desktop (uint d) {
            return desktop == ALL_DESKTOPS || desktop == d;
        }

        public bool sticky () {
            return desktop == ALL_DESKTOPS;
        }

        public Layer layer (bool is_focused) {
            if (kind == ClientKind.DESKTOP) return Layer.DESKTOP;
            if (kind == ClientKind.DOCK) return below ? Layer.BELOW : Layer.DOCK;
            if (fullscreen && is_focused) return Layer.FULLSCREEN;
            if (above) return Layer.ABOVE;
            if (below) return Layer.BELOW;
            return Layer.NORMAL;
        }

        public void save_restore () {
            if (!has_restore) {
                restore = geom;
                has_restore = true;
            }
        }
    }
}
