namespace Fenster {
    /* Zonas de ajuste: mitades, cuartos y maximizar. */
    public enum SnapZone {
        NONE,
        LEFT,
        RIGHT,
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT,
        MAXIMIZE;

        /* -1 izquierda, 1 derecha, 0 ninguno */
        public int side () {
            switch (this) {
            case LEFT: case TOP_LEFT: case BOTTOM_LEFT: return -1;
            case RIGHT: case TOP_RIGHT: case BOTTOM_RIGHT: return 1;
            default: return 0;
            }
        }

        public SnapZone mirrored () {
            switch (this) {
            case LEFT: return RIGHT;
            case RIGHT: return LEFT;
            case TOP_LEFT: return TOP_RIGHT;
            case TOP_RIGHT: return TOP_LEFT;
            case BOTTOM_LEFT: return BOTTOM_RIGHT;
            case BOTTOM_RIGHT: return BOTTOM_LEFT;
            default: return this;
            }
        }

        /* Super+↑ desde esta zona: mitad → cuarto superior → maximizar */
        public SnapZone up () {
            switch (this) {
            case LEFT: return TOP_LEFT;
            case RIGHT: return TOP_RIGHT;
            case BOTTOM_LEFT: return LEFT;
            case BOTTOM_RIGHT: return RIGHT;
            default: return MAXIMIZE;
            }
        }

        /* Super+↓ desde esta zona: mitad → cuarto inferior → restaurar */
        public SnapZone down () {
            switch (this) {
            case LEFT: return BOTTOM_LEFT;
            case RIGHT: return BOTTOM_RIGHT;
            case TOP_LEFT: return LEFT;
            case TOP_RIGHT: return RIGHT;
            default: return NONE;
            }
        }

        /* Rectángulo visible de la zona dentro de un área útil. */
        public Rect rect (Rect wa) {
            int g = Style.SNAP_GAP;
            int hw = wa.w / 2, hh = wa.h / 2;
            int lx = wa.x, rx = wa.x + hw + g / 2;
            int lw = hw - g / 2, rw = wa.w - hw - g / 2;
            int ty = wa.y, by = wa.y + hh + g / 2;
            int th = hh - g / 2, bh = wa.h - hh - g / 2;
            switch (this) {
            case LEFT: return Rect (lx, wa.y, lw, wa.h);
            case RIGHT: return Rect (rx, wa.y, rw, wa.h);
            case TOP_LEFT: return Rect (lx, ty, lw, th);
            case TOP_RIGHT: return Rect (rx, ty, rw, th);
            case BOTTOM_LEFT: return Rect (lx, by, lw, bh);
            case BOTTOM_RIGHT: return Rect (rx, by, rw, bh);
            default: return wa;
            }
        }

        /* Zona bajo el puntero al arrastrar. Solo cuentan los bordes exteriores
         * del monitor: los compartidos con otro monitor se cruzan sin ajustar. */
        public static SnapZone at_pointer (Monitors monitors, int x, int y, out Monitor mon) {
            mon = monitors.at (x, y);
            var g = mon.geom;
            var wa = mon.work;
            int e = SNAP_EDGE_PX, k = SNAP_CORNER_PX;
            int bottom = int.min (g.y + g.h, wa.y + wa.h) - 1;
            bool left = x <= g.x + e && !monitors.covers (g.x - 1, y);
            bool right = x >= g.x + g.w - 1 - e && !monitors.covers (g.x + g.w, y);
            bool top = y <= wa.y + e && !monitors.covers (x, g.y - 1);
            bool bot = y >= bottom - e && !monitors.covers (x, g.y + g.h);

            if (left || right) {
                if (y <= wa.y + k) return left ? TOP_LEFT : TOP_RIGHT;
                if (y >= bottom - k) return left ? BOTTOM_LEFT : BOTTOM_RIGHT;
                return left ? LEFT : RIGHT;
            }
            if (top) {
                if (x <= g.x + k) return TOP_LEFT;
                if (x >= g.x + g.w - 1 - k) return TOP_RIGHT;
                return MAXIMIZE;
            }
            if (bot) {
                if (x <= g.x + k) return BOTTOM_LEFT;
                if (x >= g.x + g.w - 1 - k) return BOTTOM_RIGHT;
            }
            return NONE;
        }
    }

    /* Distancia al borde que activa el ajuste y franja de las esquinas (px). */
    public const int SNAP_EDGE_PX = 2;
    public const int SNAP_CORNER_PX = 80;

    /* Vista previa translúcida de la zona al arrastrar (estilo Dock-e).
     * Vive en una ventana transparente del tamaño del monitor para poder
     * animar su rectángulo sin redimensionar nada: aparece creciendo desde la
     * ventana arrastrada, se transforma entre zonas y se desvanece al salir.
     * Se dibuja en el servidor X (XRender) con doble búfer. */
    public class SnapPreview {
        ArgbWindow aw;
        Rect area;                       /* monitor donde está la ventana */
        bool placed = false;
        Cairo.Surface? front = null;
        Cairo.Surface? back = null;

        SnapZone zone = SnapZone.NONE;
        Rect goal;
        Rect from;
        Rect to;
        double alpha_from = 0;
        double alpha_to = 0;
        int64 started = 0;
        int duration_ms = Style.SNAP_PREVIEW_MS;
        uint timer = 0;
        Rect last_drawn;
        bool has_drawn = false;

        public SnapPreview (X.Display dpy, X.Window root, int screen, Atoms atoms) {
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-snap-preview", "Fenster ajuste");
        }

        public X.Window window {
            get { return aw.window; }
        }

        public bool visible {
            get { return aw.visible; }
        }

        static double ease_out_cubic (double t) {
            t = double.min (1, double.max (0, t));
            double u = 1 - t;
            return 1 - u * u * u;
        }

        double progress () {
            return ease_out_cubic ((get_monotonic_time () - started) / (duration_ms * 1000.0));
        }

        Rect current_rect () {
            double p = progress ();
            return Rect ((int) (from.x + (to.x - from.x) * p), (int) (from.y + (to.y - from.y) * p),
                         (int) (from.w + (to.w - from.w) * p), (int) (from.h + (to.h - from.h) * p));
        }

        double current_alpha () {
            return alpha_from + (alpha_to - alpha_from) * progress ();
        }

        /* zone/target: zona bajo el puntero y su rectángulo; window_rect: la
         * ventana que se arrastra (punto de partida al aparecer). */
        public void update (SnapZone zone, Rect target, Monitor mon, Rect window_rect, X.Window below_of) {
            if (zone == SnapZone.NONE) {
                fade_out ();
                return;
            }
            int m = Style.SNAP_PREVIEW_INSET;
            var dest = Rect (target.x + m, target.y + m, target.w - 2 * m, target.h - 2 * m);
            if (aw.visible && zone == this.zone && dest.x == goal.x && dest.y == goal.y
                && dest.w == goal.w && dest.h == goal.h && alpha_to > 0) {
                return;
            }
            bool showing = aw.visible && current_alpha () > 0.01;
            var start_rect = showing ? current_rect () : window_rect;
            double start_alpha = showing ? current_alpha () : 0;
            var g = mon.geom;
            if (!aw.visible || !placed || g.x != area.x || g.y != area.y || g.w != area.w || g.h != area.h) {
                area = g;
                aw.place (area);
                aw.show ();
                placed = true;
                front = aw.xlib_surface ();
                back = new Cairo.Surface.similar (front, Cairo.Content.COLOR_ALPHA, area.w, area.h);
                var c0 = new Cairo.Context (back);
                c0.set_operator (Cairo.Operator.CLEAR);
                c0.paint ();
                has_drawn = false;
            }
            this.zone = zone;
            goal = dest;
            from = start_rect;
            to = dest;
            alpha_from = start_alpha;
            alpha_to = 1;
            duration_ms = Style.SNAP_PREVIEW_MS;
            started = get_monotonic_time ();
            aw.set_rect_hint ("_FENSTER_PREVIEW_RECT", dest);
            aw.stack_below (below_of);
            run ();
        }

        void fade_out () {
            if (!aw.visible || alpha_to == 0) {
                return;
            }
            zone = SnapZone.NONE;
            var r = current_rect ();
            alpha_from = current_alpha ();
            from = to = r;
            alpha_to = 0;
            duration_ms = Style.SNAP_PREVIEW_FADE_MS;
            started = get_monotonic_time ();
            run ();
        }

        void run () {
            draw ();
            if (timer != 0) {
                return;
            }
            timer = Timeout.add_full (Priority.HIGH, 8, () => {
                draw ();
                if (progress () >= 1) {
                    timer = 0;
                    if (alpha_to == 0) {
                        hide ();
                    }
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
        }

        public void restack_below (X.Window w) {
            if (aw.visible && w != 0) {
                aw.stack_below (w);
            }
        }

        public void hide () {
            if (timer != 0) {
                Source.remove (timer);
                timer = 0;
            }
            zone = SnapZone.NONE;
            alpha_to = 0;
            front = null;
            back = null;
            placed = false;
            aw.hide ();
        }

        public void draw () {
            if (!aw.visible || back == null) {
                return;
            }
            var r = current_rect ();
            r.x -= area.x;
            r.y -= area.y;
            double alpha = current_alpha ();
            var cr = new Cairo.Context (back);
            /* Limpiar solo lo pintado antes */
            if (has_drawn) {
                cr.save ();
                cr.rectangle (last_drawn.x - 3, last_drawn.y - 3, last_drawn.w + 6, last_drawn.h + 6);
                cr.set_operator (Cairo.Operator.CLEAR);
                cr.fill ();
                cr.restore ();
            }
            if (alpha > 0.005 && r.w > 4 && r.h > 4) {
                ArgbWindow.rounded (cr, r.x + 1, r.y + 1, r.w - 2, r.h - 2, Style.CORNER_RADIUS);
                cr.set_source_rgba (0, 0, 0, Style.SNAP_PREVIEW_ALPHA * alpha);
                cr.fill_preserve ();
                cr.set_line_width (1.5);
                cr.set_source_rgba (1, 1, 1, Style.SNAP_PREVIEW_STROKE_ALPHA * alpha);
                cr.stroke ();
            }
            /* Copiar al frente la unión de lo viejo y lo nuevo */
            var dirty = has_drawn ? union (last_drawn, r) : r;
            var fc = new Cairo.Context (front);
            fc.set_operator (Cairo.Operator.SOURCE);
            fc.rectangle (dirty.x - 3, dirty.y - 3, dirty.w + 6, dirty.h + 6);
            fc.clip ();
            fc.set_source_surface (back, 0, 0);
            fc.paint ();
            front.flush ();
            aw.flush ();
            last_drawn = r;
            has_drawn = true;
        }

        static Rect union (Rect a, Rect b) {
            int x0 = int.min (a.x, b.x), y0 = int.min (a.y, b.y);
            int x1 = int.max (a.x + a.w, b.x + b.w), y1 = int.max (a.y + a.h, b.y + b.h);
            return Rect (x0, y0, x1 - x0, y1 - y0);
        }
    }
}
