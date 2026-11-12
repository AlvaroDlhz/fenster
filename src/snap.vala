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

    /* Vista previa translúcida de la zona al arrastrar (estilo Dock-e). */
    public class SnapPreview {
        ArgbWindow aw;
        SnapZone zone = SnapZone.NONE;
        Rect shown;

        public SnapPreview (X.Display dpy, X.Window root, int screen, Atoms atoms) {
            aw = new ArgbWindow (dpy, root, screen, atoms, "fenster-snap-preview", "Fenster ajuste");
        }

        public X.Window window {
            get { return aw.window; }
        }

        public bool visible {
            get { return aw.visible; }
        }

        public void update (SnapZone zone, Rect target, X.Window below_of) {
            if (zone == SnapZone.NONE) {
                hide ();
                return;
            }
            bool same = aw.visible && zone == this.zone && target.x == shown.x && target.y == shown.y
                        && target.w == shown.w && target.h == shown.h;
            this.zone = zone;
            shown = target;
            if (same) {
                return;
            }
            int m = Style.SNAP_PREVIEW_INSET;
            aw.place (Rect (target.x + m, target.y + m, target.w - 2 * m, target.h - 2 * m));
            aw.show ();
            aw.stack_below (below_of);
            draw ();
        }

        public void hide () {
            zone = SnapZone.NONE;
            aw.hide ();
        }

        public void draw () {
            if (!aw.visible) {
                return;
            }
            var img = aw.canvas ();
            var cr = new Cairo.Context (img);
            double w = aw.width, h = aw.height;
            ArgbWindow.rounded (cr, 1, 1, w - 2, h - 2, Style.CORNER_RADIUS);
            cr.set_source_rgba (0, 0, 0, Style.SNAP_PREVIEW_ALPHA);
            cr.fill_preserve ();
            cr.set_line_width (1.5);
            cr.set_source_rgba (1, 1, 1, Style.SNAP_PREVIEW_STROKE_ALPHA);
            cr.stroke ();
            aw.paint (img);
        }
    }
}
